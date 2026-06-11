pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var map = try halite2.Map.init(4, 100, 100, 5, allocator);
    defer map.deinit();

    try map.add_player("Test player 1");
    try map.add_player("Test player 2");
    try map.add_player("Test player 3");
    try map.add_player("Test player 4");

    // Game loop
    // while (true) {}
}

const std = @import("std");
const halite2 = @import("halite2");
const IdLib = halite2.IdLib;
