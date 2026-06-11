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

        // Track how many ships have been accepted for docking per planet this turn,
        // so we don't over-book a planet within a single batch of commands.
        var pending_docks = std.AutoHashMap(Id, u32).init(allocator);
        defer pending_docks.deinit();

        for (self.ships.items) |*ship| {
            if (raw_commands.get(ship.id)) |command| {
                // For DOCK commands, check capacity including already-pending docks this turn
                if (command == .DOCK) {
                    const planet_id = command.DOCK;
                    if (planets.get(planet_id)) |planet| {
                        const pending = pending_docks.get(planet_id) orelse 0;
                        if (planet.docked_count + pending >= planet.docking_spots()) continue;
                        try pending_docks.put(planet_id, pending + 1);
                    }
                }

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
                    if (other_ship.owner_id == self.id) continue;

                    const d2 = distSq(ship.position, other_ship.position);

                    if (d2 < (SHIP_RADIUS * 2) * (SHIP_RADIUS * 2)) {
                        ship.health = 0;
                        other_ship.health = 0;
                        break;
                    }

                    other_ship.health = std.math.sub(u8, other_ship.health, config.ship_damage) catch 0;
                }
            }
        }
    }

    pub fn cleanup_dead_ships(self: *Self, planets: *PlanetList) void {
        var i: usize = self.ships.items.len;
        while (i > 0) {
            i -= 1;
            const ship = &self.ships.items[i];
            if (ship.health == 0) {
                if (ship.state == .DOCKED) {
                    if (planets.getPtr(ship.state.DOCKED)) |planet| planet.docked_count -|= 1;
                }
                _ = self.ships.swapRemove(i);
            }
        }
    }

    pub fn process_docking(self: *Self, planets: *PlanetList) void {
        for (self.ships.items) |*ship| {
            switch (ship.state) {
                .DOCKING => |*d| {
                    if (d.turns > 1) {
                        d.turns -= 1;
                    } else if (planets.getPtr(d.id)) |planet| {
                        if (planet.docked_count < planet.docking_spots()) {
                            planet.docked_count += 1;
                            ship.state = .{ .DOCKED = d.id };
                        } else {
                            ship.state = .UNDOCKED; // planet full, abort docking
                        }
                    } else {
                        ship.state = .UNDOCKED;
                    }
                },
                .UNDOCKING => |*u| {
                    if (u.turns > 1) {
                        u.turns -= 1;
                    } else {
                        if (planets.getPtr(u.id)) |planet| planet.docked_count -|= 1;
                        ship.state = .UNDOCKED;
                    }
                },
                else => {},
            }

            // Apply new state from validated commands
            switch (ship.new_state) {
                .DOCKING => |d| {
                    if (ship.state == .UNDOCKED) {
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

    pub fn process_mining_and_spawning(
        self: *Self,
        planets: *PlanetList,
        uuid_generator: *UUIDGenerator,
        allocator: std.mem.Allocator,
        turn: u32,
        config: Config,
    ) !void {
        var planet_it = planets.valueIterator();
        while (planet_it.next()) |planet| {
            // Count ships owned by this player docked at this planet
            var docked_count: u32 = 0;
            for (self.ships.items) |ship| {
                switch (ship.state) {
                    .DOCKED => |planet_id| {
                        if (planet_id == planet.id and ship.owner_id == self.id)
                            docked_count += 1;
                    },
                    else => {},
                }
            }

            if (docked_count == 0) continue;

            // Mining: each docked ship mines a fraction of remaining halite
            const mined = planet.halite * config.mining_rate * @as(f64, @floatFromInt(docked_count));
            const actual_mined: f64 = @min(mined, planet.halite);
            planet.halite -= actual_mined;
            self.resources += actual_mined;

            // Spawning: every ship_spawn_interval turns, attempt to spawn a ship
            if (turn % config.ship_spawn_interval == 0 and self.resources >= config.ship_cost) {
                // Spawn adjacent to planet surface, at a fixed offset angle per existing ship count
                const angle = @as(f64, @floatFromInt(turn % 360)) * std.math.pi / 180.0;
                const spawn_r = planet.size + SHIP_RADIUS * 2.0 + 1.0;
                const spawn_pos = @Vector(2, f64){
                    @as(f64, @floatCast(planet.position[0])) + spawn_r * @cos(angle),
                    @as(f64, @floatCast(planet.position[1])) + spawn_r * @sin(angle),
                };

                const new_ship = try Ship.new(uuid_generator.next(), self.id, spawn_pos);
                try self.ships.append(allocator, new_ship);
                self.resources -= config.ship_cost;
            }
        }
    }
};

const std = @import("std");

const PlanetList = @import("planet.zig").PlanetList;
const ShipList = @import("ship.zig").ShipList;
const Ship = @import("ship.zig").Ship;
const ShipCommand = @import("ship.zig").ShipCommand;
const Map = @import("map.zig").Map;
const Config = @import("config.zig").Config;
const Id = @import("id.zig").Id;
const UUIDGenerator = @import("id.zig").UUIDGenerator;
const SHIP_RADIUS = @import("ship.zig").SHIP_RADIUS;
const distSq = @import("utils.zig").distSq;
