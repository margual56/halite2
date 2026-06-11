pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const config = halite2.Config{
        .n_players = 4,
        .n_planets = 5,
        .map_size_x = 100,
        .map_size_y = 100,
        .max_turns = 200,
        .ship_damage = 64,
        .turns_to_dock = 5,
        .max_velocity = 7.0,
    };

    var map = try Map.init(config, allocator);
    defer map.deinit();

    try map.add_player("Test player 1");
    try map.add_player("Test player 2");
    try map.add_player("Test player 3");
    try map.add_player("Test player 4");

    const comms = halite2.BotCommunicator.init(allocator);

    // Game loop
    var turn: u32 = 0;
    while (turn < config.max_turns) : (turn += 1) {
        // 1. Validate and gather commands for each player
        var all_validated_commands = try allocator.alloc(std.AutoHashMap(IdLib.Id, ShipCommand), map.players.len);
        defer {
            for (all_validated_commands) |*v| v.deinit();
            allocator.free(all_validated_commands);
        }

        for (map.players, 0..) |*player, i| {
            // 1. Where the engine would WRITE to the bot's stdin
            var mock_stdin = std.Io.Writer.Allocating.init(allocator);
            defer mock_stdin.deinit();

            if (turn == 0) {
                try comms.sendInit(&mock_stdin.writer, &map, player.id);
            }
            try comms.sendTurnUpdate(&mock_stdin.writer, &map, turn);

            // 2. Where the engine would READ from the bot's stdout
            // Here we inject a hard-coded command string depending on the player's ships.
            // Example mock: We grab the first ship and tell it to move.
            var mock_bot_writer = std.Io.Writer.Allocating.init(allocator);
            defer mock_bot_writer.deinit();
            const writer = &mock_bot_writer.writer;

            if (player.ships.items.len > 0) {
                const ship_id = player.ships.items[0].id;
                // e.g., "t <ship_id> 90 2\n" -> thrust ship 90 degrees at speed 2
                try writer.print("t {d} 90 2\n", .{ship_id});
            } else {
                try writer.writeAll("\n");
            }

            const mock_bot_response = mock_bot_writer.written();

            // 3. Actually parse the commands back into the engine using the struct
            var mock_stdout_stream = std.Io.Reader.fixed(mock_bot_response);
            var raw_commands = try comms.readCommands(&mock_stdout_stream);
            defer raw_commands.deinit();

            all_validated_commands[i] = try player.validate_and_gather_commands(raw_commands, map.planets, allocator, config);
        }

        // 2. Generate spatial map for this turn's combat and collisions
        var spatial_map = try map.get_spatial_map();
        defer {
            var it = spatial_map.valueIterator();
            while (it.next()) |list| list.deinit(allocator);
            spatial_map.deinit();
        }

        // 3. Process each game stage
        for (map.players, 0..) |*player, i| {
            player.process_moves(all_validated_commands[i], map.size);
        }

        for (map.players) |*player| {
            player.process_combat(spatial_map, map.size, config);
        }

        for (map.players) |*player| {
            player.cleanup_dead_ships();
        }

        for (map.players) |*player| {
            player.process_docking(map.planets);
        }

        for (map.players) |*player| {
            player.process_mining_and_spawning();
        }

        if (turn % 50 == 0) std.debug.print("Processed turn {d}\n", .{turn});
    }

    std.debug.print("Game finished after {d} turns.\n", .{turn});
}

const std = @import("std");
const halite2 = @import("halite2");
const IdLib = halite2.IdLib;
const BotCommunicator = halite2.BotCommunicator;
const Map = halite2.map.Map;
const ShipCommand = halite2.ship.ShipCommand;
