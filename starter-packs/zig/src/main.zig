const hlt = @import("hlt.zig");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena.deinit();
    const allocator = arena.allocator();

    var game = try hlt.Game.init(io, "StarterPackBot", allocator);
    defer game.map.deinit();

    var cmd_bufs: [256][32]u8 = undefined;
    var cmds: [256][]const u8 = undefined;

    while (true) {
        const map = try game.update_map();
        var n_cmds: usize = 0;

        if (map.me()) |me| {
            var ship_it = me.ships.valueIterator();
            while (ship_it.next()) |ship| {
                if (!ship.is_undocked()) continue;

                var nearest: ?hlt.Planet = null;
                var nearest_dist: f64 = std.math.floatMax(f64);
                var pit = map.planets.valueIterator();
                while (pit.next()) |planet| {
                    if (planet.is_full()) continue;
                    const d = ship.distance_to_planet(planet.*);
                    if (d < nearest_dist) {
                        nearest_dist = d;
                        nearest = planet.*;
                    }
                }

                if (nearest) |planet| {
                    if (ship.can_dock(planet)) {
                        cmds[n_cmds] = hlt.cmd_dock(&cmd_bufs[n_cmds], ship.id, planet.id);
                    } else {
                        const speed: u8 = @intCast(@min(hlt.MAX_SPEED, @as(u8, @intFromFloat(nearest_dist))));
                        const angle: u16 = ship.angle_to_planet(planet);
                        cmds[n_cmds] = hlt.cmd_thrust(&cmd_bufs[n_cmds], ship.id, speed, angle);
                    }
                    n_cmds += 1;
                }
            }
        }

        try game.send_commands(cmds[0..n_cmds]);
    }
}
