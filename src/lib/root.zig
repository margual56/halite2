pub const MAX_VELOCITY = 7.0;
/// Turns to dock AND undock
pub const TURNS_TO_DOCK = 5;
pub const DOCK_RADIUS = 4.0;
pub const SHIP_RADIUS = 0.5;
pub const SHIP_DAMAGE = 64;

/// Maximum time for the players to respond to
/// the Initialization Handshake (in seconds)
pub const INITIALIZATION_TIME = 60;
/// Maximum processing time for the players
/// per turn (in seconds)
pub const TURN_PROCESS_TIME = 2;

/// Look-up table for all possible thrust values
/// Angle: [0, 360)
/// Magnitude: [0, 7]
pub const lut_thrusts = blk: {
    @setEvalBranchQuota(4000);
    var table: [360][8]@Vector(2, f64) = undefined;
    for (0..360) |angle| {
        for (0..8) |magnitude| {
            const a = @as(f64, @floatFromInt(angle)) * (std.math.pi / 180.0);
            const m = @as(f64, @floatFromInt(magnitude));
            table[angle][magnitude] = @Vector(2, f64){ m * @cos(a), m * @sin(a) };
        }
    }
    break :blk table;
};

pub fn distSq(a: anytype, b: anytype) @typeInfo(@TypeOf(a)).vector.child {
    const diff = a - b;
    return @reduce(.Add, diff * diff);
}

pub fn dist(a: anytype, b: anytype) @typeInfo(@TypeOf(a)).vector.child {
    return @sqrt(distSq(a, b));
}

pub const PlanetList = std.AutoHashMap(Id, Planet);
pub const ShipList = std.ArrayList(Ship);

fn is_valid_spawn_point(position: @Vector(2, f32), planets: PlanetList) bool {
    var it = planets.valueIterator();
    while (it.next()) |planet| {
        const d2 = distSq(@as(@Vector(2, f64), @floatCast(position)), planet.position);
        const min_dist = planet.size + SHIP_RADIUS * 2;
        if (d2 < min_dist * min_dist) {
            return false;
        }
    }
    return true;
}

fn is_valid_planet_position(position: @Vector(2, f32), size: f64, other_planets: []Planet) bool {
    for (other_planets) |planet| {
        const d2 = distSq(@as(@Vector(2, f64), @floatCast(position)), planet.position);
        const min_dist = planet.size + size + SHIP_RADIUS;
        if (d2 < min_dist * min_dist) {
            return false;
        }
    }
    return true;
}

pub const Map = struct {
    size: @Vector(2, u64),
    planets: PlanetList,
    players: []Player,
    uuid_generator: IdLib.UUIDGenerator,
    allocator: std.mem.Allocator,
    prng: std.Random.DefaultPrng,

    const Self = @This();

    pub fn init(n_players: u32, size_x: u64, size_y: u64, n_planets: u16, allocator: std.mem.Allocator) !Self {
        const seed: u64 = 42;
        var prng = std.Random.DefaultPrng.init(seed);
        const random = prng.random();
        var uuid_generator = IdLib.UUIDGenerator.init(@as(u32, @intCast(seed & 0xFFFFFFFF)));

        var planets = PlanetList.init(allocator);
        const planet_list = try allocator.alloc(Planet, n_planets);
        defer allocator.free(planet_list);

        for (0..n_planets) |i| {
            const id = uuid_generator.next();

            const planet = Planet.new(id, @as(u32, @intCast(size_x)), @as(u32, @intCast(size_y)), planet_list[0..i], random);
            try planets.put(id, planet);
            planet_list[i] = planet;
        }

        const players = try allocator.alloc(Player, n_players);
        for (players) |*player| {
            player.* = .{
                .id = 0,
                .ships = ShipList.empty,
                .resources = 0,
                .name = std.mem.zeroes([16]u8),
            };
        }

        return .{
            .size = .{ size_x, size_y },
            .planets = planets,
            .players = players,
            .uuid_generator = uuid_generator,
            .allocator = allocator,
            .prng = prng,
        };
    }

    fn get_player_initial_position(self: *Self, i: u32) @Vector(2, f32) {
        var random = self.prng.random();
        var candidate = @Vector(2, f32){
            @as(f32, @floatFromInt(self.size[0])) * 0.5 + (@as(f32, @floatFromInt(self.size[0])) * 0.4) * @cos((2 * std.math.pi * @as(f32, @floatFromInt(i))) / @as(f32, @floatFromInt(self.players.len)) + random.float(f32)),
            @as(f32, @floatFromInt(self.size[1])) * 0.5 + (@as(f32, @floatFromInt(self.size[1])) * 0.4) * @sin((2 * std.math.pi * @as(f32, @floatFromInt(i))) / @as(f32, @floatFromInt(self.players.len)) + random.float(f32)),
        };

        while (!is_valid_spawn_point(candidate, self.planets)) {
            candidate[0] = random.float(f32) * @as(f32, @floatFromInt(self.size[0]));
            candidate[1] = random.float(f32) * @as(f32, @floatFromInt(self.size[1]));
        }

        return candidate;
    }

    pub fn add_player(self: *Self, name_raw: []const u8) !void {
        const id = self.uuid_generator.next();

        var name: [16]u8 = std.mem.zeroes([16]u8);
        const copy_len = @min(name_raw.len, 16);
        @memcpy(name[0..copy_len], name_raw[0..copy_len]);

        var i: u32 = 0;
        while (i < self.players.len and self.players[i].id != 0) : (i += 1) {}
        if (i == self.players.len) return error.NoMorePlayers;

        const pos = self.get_player_initial_position(i);

        var player = &self.players[i];
        player.id = id;
        player.name = name;

        try player.ships.append(self.allocator, try Ship.new(self.uuid_generator.next(), id, @as(@Vector(2, f64), @floatCast(pos)) + lut_thrusts[0][1]));
        try player.ships.append(self.allocator, try Ship.new(self.uuid_generator.next(), id, @as(@Vector(2, f64), @floatCast(pos)) + lut_thrusts[120][1]));
        try player.ships.append(self.allocator, try Ship.new(self.uuid_generator.next(), id, @as(@Vector(2, f64), @floatCast(pos)) + lut_thrusts[240][1]));
    }

    pub const SpatialMap = std.AutoHashMap(u64, std.ArrayList(*Ship));

    pub fn get_spatial_map(self: *Self) !SpatialMap {
        var spatial_map = SpatialMap.init(self.allocator);
        errdefer {
            var it = spatial_map.valueIterator();
            while (it.next()) |list| list.deinit(self.allocator);
            spatial_map.deinit();
        }

        const cells_x = (self.size[0] + 4) / 5;

        for (self.players) |*player| {
            for (player.ships.items) |*ship| {
                const cell_vec = @as(@Vector(2, u64), @intFromFloat(@floor(@max(@Vector(2, f64){ 0, 0 }, ship.position) / @Vector(2, f64){ 5, 5 })));
                const key = cell_vec[1] * cells_x + cell_vec[0];

                const gop = try spatial_map.getOrPut(key);
                if (!gop.found_existing) {
                    gop.value_ptr.* = std.ArrayList(*Ship).empty;
                }
                try gop.value_ptr.append(self.allocator, ship);
            }
        }
        return spatial_map;
    }

    pub fn deinit(self: *Self) void {
        self.planets.deinit();
        for (self.players) |*player| {
            player.deinit(self.allocator);
        }
        self.allocator.free(self.players);
    }
};

pub const Player = struct {
    id: Id,
    ships: ShipList,
    resources: f64,
    name: [16]u8,

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.ships.deinit(allocator);
    }

    pub fn validate_and_gather_commands(self: *Self, raw_commands: std.AutoHashMap(Id, ShipCommand), planets: PlanetList, allocator: std.mem.Allocator) !std.AutoHashMap(Id, ShipCommand) {
        var validated = std.AutoHashMap(Id, ShipCommand).init(allocator);
        errdefer validated.deinit();

        for (self.ships.items) |*ship| {
            if (raw_commands.get(ship.id)) |command| {
                ship.validate_command(command, planets) catch continue;

                switch (command) {
                    .DOCK => |planet_id| {
                        ship.new_state = .{ .DOCKING = .{ .id = planet_id, .turns = TURNS_TO_DOCK } };
                    },
                    .UNDOCK => {
                        switch (ship.state) {
                            .DOCKED => |planet_id| {
                                ship.new_state = .{ .UNDOCKING = .{ .id = planet_id, .turns = TURNS_TO_DOCK } };
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

    pub fn process_combat(self: *Self, spatial_map: Map.SpatialMap, map_size: @Vector(2, u64)) void {
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
                        other_ship.health = std.math.sub(u8, other_ship.health, SHIP_DAMAGE) catch 0;
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

pub const Planet = struct {
    id: Id,
    size: f64,
    halite: f64,
    position: @Vector(2, f64),

    const Self = @This();

    fn generate_planet_size(random: std.Random) f64 {
        const r = random.float(f64);

        // 60% of planets are Small
        if (r < 0.60) {
            return 2.0 + random.float(f64) * 0.5;
            // 30% of planets are Medium
        } else if (r < 0.90) {
            return 3.0 + random.float(f64) * 0.5;
            // 10% of planets are Large (the "jackpots")
        } else {
            return 4.0 + random.float(f64) * 1.0;
        }
    }

    pub fn new(id: Id, size_x: u32, size_y: u32, other_planets: []Planet, random: std.Random) Self {
        const size = generate_planet_size(random);

        var candidate_position = @Vector(2, f32){
            random.float(f32) * @as(f32, @floatFromInt(size_x)),
            random.float(f32) * @as(f32, @floatFromInt(size_y)),
        };

        while (!is_valid_planet_position(candidate_position, size, other_planets)) {
            candidate_position[0] = random.float(f32) * @as(f32, @floatFromInt(size_x));
            candidate_position[1] = random.float(f32) * @as(f32, @floatFromInt(size_y));
        }

        return .{
            .id = id,
            .size = size,
            .halite = size * (0.8 + (random.float(f64) * 0.4)),
            .position = @as(@Vector(2, f64), @floatCast(candidate_position)),
        };
    }
};

pub const ShipState = union(enum) {
    /// Docking planet in x turns
    DOCKING: struct { id: Id, turns: u3 },
    DOCKED: Id,

    /// Undocking planet in x turns
    UNDOCKING: struct { id: Id, turns: u3 },
    UNDOCKED,
};

/// In polar coordinates
pub const ShipThrust = packed struct {
    angle: u9,
    magnitude: u3,

    const Self = @This();

    pub inline fn to_cartesian(self: Self) @Vector(2, f64) {
        return lut_thrusts[self.angle][self.magnitude];
    }
};

pub const ShipCommand = union(enum) {
    THRUST: ShipThrust,
    DOCK: u32,
    UNDOCK,
    NA,
};

pub const Ship = struct {
    id: Id,
    owner_id: Id,
    health: u8,
    position: @Vector(2, f64),
    state: ShipState,
    /// New, validated state
    new_state: ShipState,

    const Self = @This();

    pub fn new(id: Id, owner_id: Id, position: @Vector(2, f64)) !Self {
        return .{
            .id = id,
            .owner_id = owner_id,
            .health = 255,
            .position = position,
            .state = .UNDOCKED,
            .new_state = .UNDOCKED,
        };
    }

    pub fn validate_command(self: Self, command: ShipCommand, planets: PlanetList) !void {
        switch (command) {
            .THRUST => |thrust| {
                if (@as(f64, @floatFromInt(thrust.magnitude)) > MAX_VELOCITY) {
                    return error.InvalidThrust;
                }

                if (self.state != .UNDOCKED) {
                    return error.InvalidCommand;
                }
            },
            .DOCK => |planet1| {
                switch (self.state) {
                    .UNDOCKED => {
                        if (planets.get(planet1)) |planet| {
                            const d = dist(self.position, planet.position);

                            if (d > planet.size + DOCK_RADIUS + SHIP_RADIUS) {
                                return error.InvalidCommand;
                            }
                        } else {
                            return error.InvalidCommand;
                        }
                    },
                    else => return error.InvalidCommand,
                }
            },
            .UNDOCK => {
                switch (self.state) {
                    .DOCKED => {},
                    else => return error.InvalidCommand,
                }
            },
            .NA => {},
        }
    }

    pub fn move(self: *Self, command: ShipCommand, map_size: @Vector(2, u64)) !void {
        switch (command) {
            .THRUST => |thrust| self.position = self.position + thrust.to_cartesian(),
            else => return,
        }

        if (self.position[0] < 0 or self.position[1] < 0 or
            self.position[0] > @as(f64, @floatFromInt(map_size[0])) or
            self.position[1] > @as(f64, @floatFromInt(map_size[1])))
        {
            return error.InvalidPosition;
        }
    }
};

const std = @import("std");
pub const IdLib = @import("id.zig");
const Id = IdLib.Id;

test "Map init and add_player" {
    const allocator = std.testing.allocator;
    var map = try Map.init(4, 100, 100, 5, allocator);
    defer map.deinit();

    try map.add_player("Player 1");
    try map.add_player("Player 2");

    try std.testing.expectEqual(@as(usize, 4), map.players.len);
    try std.testing.expect(map.players[0].id != 0);
    try std.testing.expect(map.players[1].id != 0);
}

test "get_spatial_map" {
    const allocator = std.testing.allocator;
    var map = try Map.init(1, 100, 100, 0, allocator);
    defer map.deinit();

    try map.add_player("Player 1");

    var spatial_map = try map.get_spatial_map();
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
