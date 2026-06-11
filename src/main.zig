pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help               Display this help and exit.
        \\-d, --dimensions <str>   Map dimensions as "width height" (default "100 100").
        \\<str>...                 Bot launch commands (e.g. "python bot.py").
        \\
    );

    var diag = clap.Diagnostic{};
    var res: clap.Result(clap.Help, &params, clap.parsers.default) = clap.parse(clap.Help, &params, clap.parsers.default, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = init.gpa,
    }) catch |err| {
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        std.debug.print("Usage: halite [options] <bot1> <bot2> ...\n", .{});
        return clap.usageToFile(init.io, .stdout(), clap.Help, &params);
    }

    var map_size_x: u32 = 100;
    var map_size_y: u32 = 100;

    if (res.args.dimensions) |dim| {
        var it = std.mem.tokenizeAny(u8, dim, " x,");
        if (it.next()) |w_str| map_size_x = try std.fmt.parseInt(u32, w_str, 10);
        if (it.next()) |h_str| map_size_y = try std.fmt.parseInt(u32, h_str, 10);
    }

    const num_bots = @as(u32, @intCast(res.positionals[0].len));
    if (num_bots == 0) {
        std.debug.print("Error: You must provide at least one bot command.\n", .{});
        return error.NoBotsProvided;
    }

    const config = halite2.Config{
        .n_players = @intCast(num_bots),
        .n_planets = 5,
        .map_size_x = map_size_x,
        .map_size_y = map_size_y,
        .max_turns = 200,
        .ship_damage = 64,
        .turns_to_dock = 5,
        .max_velocity = 7.0,
    };

    var map = try Map.init(config, allocator);
    defer map.deinit();

    const comms = BotCommunicator.init(allocator);

    // Keep references to our running bots
    var children = try allocator.alloc(std.process.Child, num_bots);
    defer {
        for (children) |*child| child.kill(io);
        allocator.free(children);
    }

    // --- 1. INITIALIZATION HANDSHAKE ---
    const positionals: []const []const u8 = res.positionals[0];
    for (positionals, 0..) |bot_command, i| {
        // A. Spawn the bot process
        var args = try std.ArrayList([]const u8).initCapacity(allocator, 8);
        defer args.deinit(allocator);
        var cmd_it = std.mem.tokenizeScalar(u8, bot_command, ' ');
        while (cmd_it.next()) |arg| try args.append(allocator, arg);

        children[i] = try std.process.spawn(io, .{
            .argv = args.items,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .ignore,
        });

        var stdin_buf: [4096]u8 = undefined;
        var stdin_writer = children[i].stdin.?.writerStreaming(io, &stdin_buf);
        var stdout_buf: [4096]u8 = undefined;
        var stdout_reader = children[i].stdout.?.readerStreaming(io, &stdout_buf);

        // B. Send Engine State (Blind handshake)
        // We use the loop index 'i' as the bot's player_id to satisfy the engine protocol
        try comms.sendInit(&stdin_writer.interface, &map, @as(IdLib.Id, @intCast(i)));
        try stdin_writer.flush();

        // C. Read the bot's chosen name from stdout
        const line = stdout_reader.interface.takeDelimiterExclusive('\n') catch {
            std.debug.print("Error: Bot {d} failed to respond with its name.\n", .{i});
            return error.BotFailedToInitialize;
        };
        stdout_reader.interface.toss(1);
        const bot_name = std.mem.trimEnd(u8, line, "\r");

        // D. Add player
        try map.add_player(bot_name, children[i].stdin.?, children[i].stdout.?);
        std.debug.print("Bot {d} successfully connected as: {s}\n", .{ i, bot_name });
    }

    // --- 2. MAIN GAME LOOP ---
    var turn: u32 = 0;
    while (turn < config.max_turns) : (turn += 1) {
        var all_validated_commands = try allocator.alloc(std.AutoHashMap(IdLib.Id, ShipCommand), map.players.len);
        defer {
            for (all_validated_commands) |*v| v.deinit();
            allocator.free(all_validated_commands);
        }

        // Phase A: I/O Pipeline
        for (map.players, 0..) |*player, i| {
            var stdin_buf: [4096]u8 = undefined;
            var stdin_writer = children[i].stdin.?.writerStreaming(io, &stdin_buf);
            var stdout_buf: [4096]u8 = undefined;
            var stdout_reader = children[i].stdout.?.readerStreaming(io, &stdout_buf);

            // Push turn snapshot
            try comms.sendTurnUpdate(&stdin_writer.interface, &map, turn);
            try stdin_writer.flush();

            // Pull and parse bot commands
            var raw_commands = try comms.readCommands(&stdout_reader.interface);
            defer raw_commands.deinit();

            all_validated_commands[i] = try player.validate_and_gather_commands(raw_commands, map.planets, allocator, config);
        }

        // Phase B: Resolution Pipeline
        var spatial_map = try map.get_spatial_map();
        defer {
            var it = spatial_map.valueIterator();
            while (it.next()) |list| list.deinit(allocator);
            spatial_map.deinit();
        }

        for (map.players, 0..) |*player, i| player.process_moves(all_validated_commands[i], map.size);
        for (map.players) |*player| player.process_combat(spatial_map, map.size, config);
        for (map.players) |*player| player.cleanup_dead_ships();
        for (map.players) |*player| player.process_docking(map.planets);
        for (map.players) |*player| player.process_mining_and_spawning();

        if (turn % 50 == 0) std.debug.print("Processed turn {d}\n", .{turn});
    }

    std.debug.print("Game finished after {d} turns.\n", .{turn});
}

const std = @import("std");
const clap = @import("clap");
const halite2 = @import("halite2");
const IdLib = halite2.IdLib;
const BotCommunicator = halite2.BotCommunicator;
const Map = halite2.map.Map;
const ShipCommand = halite2.ship.ShipCommand;
