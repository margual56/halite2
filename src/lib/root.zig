pub const IdLib = @import("id.zig");
pub const Config = @import("config.zig").Config;
pub const BotCommunicator = @import("bot_protocol.zig").BotCommunicator;
pub const map = @import("map.zig");
pub const planet = @import("planet.zig");
pub const ship = @import("ship.zig");
pub const player = @import("player.zig");

const Id = IdLib.Id;
const std = @import("std");
test "Map init and add_player" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const config = @import("config.zig").Config{
        .n_players = 4,
        .n_planets = 5,
        .map_size_x = 100,
        .map_size_y = 100,
    };
    var test_map = try map.Map.init(config, allocator);
    defer test_map.deinit();

    const null_file = try std.Io.Dir.openFileAbsolute(io, "/dev/null", .{ .mode = .read_write });
    defer null_file.close(io);
    try test_map.add_player("Player 1", null_file, null_file);
    try test_map.add_player("Player 2", null_file, null_file);

    try std.testing.expectEqual(@as(usize, 4), test_map.players.len);
    try std.testing.expect(test_map.players[0].id != 0);
    try std.testing.expect(test_map.players[1].id != 0);
}

test "get_spatial_map" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const config = @import("config.zig").Config{
        .n_players = 1,
        .n_planets = 0,
        .map_size_x = 100,
        .map_size_y = 100,
    };
    var test_map = try map.Map.init(config, allocator);
    defer test_map.deinit();

    const null_file = try std.Io.Dir.openFileAbsolute(io, "/dev/null", .{ .mode = .read_write });
    defer null_file.close(io);
    try test_map.add_player("Player 1", null_file, null_file);

    var spatial_map = try test_map.get_spatial_map();
    defer {
        var it = spatial_map.valueIterator();
        while (it.next()) |list| list.deinit(allocator);
        spatial_map.deinit();
    }

    try std.testing.expect(spatial_map.count() > 0);

    // Check that ships are actually in the map
    var total_ships: usize = 0;
    var it = spatial_map.valueIterator();
    while (it.next()) |list| {
        total_ships += list.items.len;
    }
    try std.testing.expectEqual(@as(usize, 3), total_ships);
}
