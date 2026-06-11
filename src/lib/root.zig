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
    var test_map = try map.Map.init(4, 100, 100, 5, allocator);
    defer test_map.deinit();

    try test_map.add_player("Player 1");
    try test_map.add_player("Player 2");

    try std.testing.expectEqual(@as(usize, 4), test_map.players.len);
    try std.testing.expect(test_map.players[0].id != 0);
    try std.testing.expect(test_map.players[1].id != 0);
}

test "get_spatial_map" {
    const allocator = std.testing.allocator;
    var test_map = try map.Map.init(1, 100, 100, 0, allocator);
    defer test_map.deinit();

    try test_map.add_player("Player 1");

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
