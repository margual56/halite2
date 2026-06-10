pub const MAX_VELOCITY = 7.0;
/// Turns to dock AND undock
pub const TURNS_TO_DOCK = 5;
pub const DOCK_RADIUS = 4.0;
pub const SHIP_RADIUS = 0.5;

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
    var table: [360][8]f64 = undefined;
    for (0..360) |angle| {
        for (0..8) |magnitude| {
            table[angle][magnitude] = magnitude * @Vector(2, f64){ @cos(angle), @sin(angle) };
        }
    }
    break :blk table;
};

pub const PlanetList = std.AutoHashMap(Id, Planet);
pub const ShipList = std.AutoHashMap(Id, Ship);

fn is_valid_spawn_point(position: @Vector(2, f32), planets: PlanetList) bool {
    for (planets.values()) |planet| {
        if (position - planet.position < planet.radius + SHIP_RADIUS * 2) {
            return false;
        }
    }
    return true;
}

fn is_valid_planet_position(position: @Vector(2, f32), size: f64, planets: []Planet) bool {
    for (planets) |planet| {
        if (position - planet.position < planet.radius + size + SHIP_RADIUS) {
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
    random: std.Random,

    const Self = @This();

    pub fn init(n_players: u32, size_x: u64, size_y: u64, n_planets: u16, allocator: std.mem.Allocator) Self {
        var prng: std.Random.DefaultPrng = .init(blk: {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            break :blk seed;
        });
        var random = prng.random();
        var uuid_generator = IdLib.UUIDGenerator.init(allocator);

        var planets = PlanetList.init(allocator);
        for (0..n_planets) |_| {
            const id = uuid_generator.next();

            _ = planets.put(id, Planet.new(id, size_x, size_y, &planets.valueIterator().items, &random));
        }

        return .{
            .size = .{ size_x, size_y },
            .planets = planets,
            .players = std.mem.zeroes(Player, n_players),
            .uuid_generator = uuid_generator,
            .allocator = allocator,
            .random = random,
        };
    }

    fn get_player_initial_position(self: Self, i: u32) @Vector(2, f32) {
        const candidate = .{
            @as(f32, @floatFromInt(self.size[0])) * @cos((2 * std.math.pi * @as(f32, @floatFromInt(i))) / @as(f32, @floatFromInt(self.players.len)) + self.random.float(f32)) - self.size[0],
            @as(f32, @floatFromInt(self.size[1])) * @sin((2 * std.math.pi * @as(f32, @floatFromInt(i))) / @as(f32, @floatFromInt(self.players.len)) + self.random.float(f32)) - self.size[1],
        };

        while (!is_valid_spawn_point(candidate, self.planets)) {
            candidate[0] = self.random.float(f32) * self.size[0];
            candidate[1] = self.random.float(f32) * self.size[1];
        }

        return candidate;
    }

    pub fn add_player(self: *Self, name_raw: []const u8) !void {
        const id = self.uuid_generator.next();

        const name: [16]u8 = std.mem.zeroes([16]u8);
        std.mem.copyForwards(u8, name[0..], name_raw);

        var player = .{
            .id = id,
            .ships = ShipList.init(self.allocator),
            .resources = 0.0,
            .name = name,
        };

        var i: u32 = 0;
        while (self.players[0] == 0) i += 1;

        const pos = self.get_player_initial_position(i);

        player.ships.append(Ship.new(self.uuid_generator.next(), pos + lut_thrusts[0][SHIP_RADIUS]));
        player.ships.append(Ship.new(self.uuid_generator.next(), pos + lut_thrusts[120][SHIP_RADIUS]));
        player.ships.append(Ship.new(self.uuid_generator.next(), pos + lut_thrusts[240][SHIP_RADIUS]));

        self.players[i] = player;
    }

    pub fn deinit(self: Self) !void {
        self.planets.deinit(self.allocator);
        self.players[0..].deinit(self.allocator);
    }
};

pub const Player = struct {
    id: Id,
    ships: ShipList,
    resources: f64,
    name: [16]u8,

    const Self = @This();

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        self.ships.deinit(allocator);
    }
};

pub const Planet = struct {
    id: Id,
    size: f64,
    halite: f64,
    position: @Vector(2, f64),

    const Self = @This();

    fn generate_planet_size(random: std.Random) f64 {
        const r = random.float();

        // 60% of planets are Small
        if (r < 0.60) {
            return 2.0 + random.float(f32) * 0.5;
            // 30% of planets are Medium
        } else if (r < 0.90) {
            return 3.0 + random.float(f32) * 0.5;
            // 10% of planets are Large (the "jackpots")
        } else {
            return 4.0 + random.float(f32) * 1.0;
        }
    }

    pub fn new(id: Id, size_x: u32, size_y: u32, other_planets: []Planet, random: std.Random) Self {
        const size = generate_planet_size(random);

        var candidate_position = @Vector(2, f32){
            random.float(f32) * size_x,
            random.float(f32) * size_y,
        };

        while (!is_valid_planet_position(candidate_position, 100, other_planets)) {
            candidate_position[0] = random.float(f32) * size_x;
            candidate_position[1] = random.float(f32) * size_y;
        }

        return .{
            .id = id,
            .size = size,
            .halite = size * (0.8 + (random.float() * 0.4)),
            .position = candidate_position,
        };
    }
};

pub const ShipState = union(enum) {
    /// Docking planet in x turns
    DOCKING: .{ Id, u3 },
    DOCKED: Id,

    /// Undocking planet in x turns
    UNDOCKING: .{ Id, u3 },
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
    health: u8,
    position: @Vector(2, f64),
    state: ShipState,
    /// New, validated state
    new_state: ShipState,

    const Self = @This();

    pub fn new(id: Id, position: @Vector(2, f64)) !Self {
        return .{
            .id = id,
            .health = 255,
            .position = position,
            .state = .UNDOCKED,
            .new_state = .UNDOCKED,
        };
    }

    pub fn validate_command(self: Self, command: ShipCommand, planets: PlanetList) !void {
        switch (command) {
            .THRUST => |thrust| {
                if (thrust[1] > MAX_VELOCITY) {
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
                            const distance = self.position - planet.position;

                            if (distance > planet.size + DOCK_RADIUS + SHIP_RADIUS) {
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

    pub fn move(self: Self, command: ShipCommand, map_size: @Vector(2, u64)) !void {
        switch (command) {
            .THRUST => |thrust| self.position = self.position + thrust.to_cartesian(),
            else => return,
        }

        if (self.position[0] < 0 or self.position[1] < 0 or self.position > map_size) {
            return error.InvalidPosition;
        }
    }
};

const std = @import("std");
pub const IdLib = @import("lib/id.zig");
const Id = IdLib.Id;
