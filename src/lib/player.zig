pub const Player = struct {
    id: Id,
    ships: ShipList,
    resources: f64,
    name: [16]u8,
    stdin: std.Io.File,
    stdout: std.Io.File,

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.ships.deinit(allocator);
    }

    pub fn validate_and_gather_commands(self: *Self, raw_commands: std.AutoHashMap(Id, ShipCommand), planets: PlanetList, allocator: std.mem.Allocator, config: Config) !std.AutoHashMap(Id, ShipCommand) {
        var validated = std.AutoHashMap(Id, ShipCommand).init(allocator);
        errdefer validated.deinit();

        for (self.ships.items) |*ship| {
            if (raw_commands.get(ship.id)) |command| {
                ship.validate_command(command, planets, config) catch continue;

                switch (command) {
                    .DOCK => |planet_id| {
                        ship.new_state = .{ .DOCKING = .{ .id = planet_id, .turns = config.turns_to_dock } };
                    },
                    .UNDOCK => {
                        switch (ship.state) {
                            .DOCKED => |planet_id| {
                                ship.new_state = .{ .UNDOCKING = .{ .id = planet_id, .turns = config.turns_to_dock } };
                            },
                            else => {},
                        }
                    },
                    else => {},
                }

                try validated.put(ship.id, command);
            }
        }
        return validated;
    }

    pub fn process_moves(self: *Self, commands: std.AutoHashMap(Id, ShipCommand), map_size: @Vector(2, u64)) void {
        for (self.ships.items) |*ship| {
            if (commands.get(ship.id)) |command| {
                ship.move(command, map_size) catch {};
            }
        }
    }

    pub fn process_combat(self: *Self, spatial_map: Map.SpatialMap, map_size: @Vector(2, u64), config: Config) void {
        const cells_x = (map_size[0] + 4) / 5;
        for (self.ships.items) |*ship| {
            if (ship.health == 0) continue;

            const cell_vec = @as(@Vector(2, u64), @intFromFloat(@floor(@max(@Vector(2, f64){ 0, 0 }, ship.position) / @Vector(2, f64){ 5, 5 })));
            const key = cell_vec[1] * cells_x + cell_vec[0];

            if (spatial_map.get(key)) |list| {
                for (list.items) |other_ship| {
                    if (other_ship.id == ship.id) continue;
                    if (other_ship.health == 0) continue;

                    const d2 = distSq(ship.position, other_ship.position);

                    if (d2 < (SHIP_RADIUS * 2) * (SHIP_RADIUS * 2)) {
                        ship.health = 0;
                        other_ship.health = 0;
                        break;
                    }

                    // Only damage ships from other players
                    if (other_ship.owner_id != self.id) {
                        other_ship.health = std.math.sub(u8, other_ship.health, config.ship_damage) catch 0;
                    }
                }
            }
        }
    }

    pub fn cleanup_dead_ships(self: *Self) void {
        var i: usize = self.ships.items.len;
        while (i > 0) {
            i -= 1;
            if (self.ships.items[i].health == 0) {
                _ = self.ships.swapRemove(i);
            }
        }
    }

    pub fn process_docking(self: *Self, planets: PlanetList) void {
        for (self.ships.items) |*ship| {
            switch (ship.state) {
                .DOCKING => |*d| {
                    if (d.turns > 1) {
                        d.turns -= 1;
                    } else {
                        ship.state = .{ .DOCKED = d.id };
                    }
                },
                .UNDOCKING => |*u| {
                    if (u.turns > 1) {
                        u.turns -= 1;
                    } else {
                        ship.state = .UNDOCKED;
                    }
                },
                else => {},
            }

            // Apply new state from validated commands
            switch (ship.new_state) {
                .DOCKING => |d| {
                    if (ship.state != .DOCKING) {
                        if (planets.contains(d.id)) {
                            ship.state = ship.new_state;
                        }
                    }
                },
                .UNDOCKING => {
                    if (ship.state != .UNDOCKING) {
                        ship.state = ship.new_state;
                    }
                },
                else => {},
            }
            ship.new_state = ship.state;
        }
    }

    pub fn process_mining_and_spawning(self: *Self) void {
        _ = self;
        // TODO: Implement mining from planets and ship spawning
    }
};

const std = @import("std");

const PlanetList = @import("planet.zig").PlanetList;
const ShipList = @import("ship.zig").ShipList;
const ShipCommand = @import("ship.zig").ShipCommand;
const Map = @import("map.zig").Map;
const Config = @import("config.zig").Config;
const Id = @import("id.zig").Id;
const SHIP_RADIUS = @import("ship.zig").SHIP_RADIUS;
const distSq = @import("utils.zig").distSq;
