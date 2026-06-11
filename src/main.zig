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

    var map = try halite2.Map.init(config, allocator);
    defer map.deinit();

    try map.add_player("Test player 1");
    try map.add_player("Test player 2");
    try map.add_player("Test player 3");
    try map.add_player("Test player 4");

    // Game loop
    var turn: u32 = 0;
    while (turn < config.max_turns) : (turn += 1) {
        // 1. Validate and gather commands for each player
        var all_validated_commands = try allocator.alloc(std.AutoHashMap(IdLib.Id, halite2.ShipCommand), map.players.len);
        defer {
            for (all_validated_commands) |*v| v.deinit();
            allocator.free(all_validated_commands);
        }

        for (map.players, 0..) |*player, i| {
            // In a real game, these would come from player's bot via I/O.
            // For now, we provide an empty command map.
            var raw_commands = std.AutoHashMap(IdLib.Id, halite2.ShipCommand).init(allocator);
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
