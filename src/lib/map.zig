pub const Map = struct {
    size: @Vector(2, u64),
    planets: PlanetList,
    players: []Player,
    uuid_generator: IdLib.UUIDGenerator,
    allocator: std.mem.Allocator,
    prng: std.Random.DefaultPrng,
    config: Config,

    const Self = @This();

    pub fn init(config: Config, allocator: std.mem.Allocator) !Self {
        const seed: u64 = 42;
        var prng = std.Random.DefaultPrng.init(seed);
        const random = prng.random();
        var uuid_generator = IdLib.UUIDGenerator.init(@as(u32, @intCast(seed & 0xFFFFFFFF)));

        var planets = PlanetList.init(allocator);
        const planet_list = try allocator.alloc(Planet, config.n_planets);
        defer allocator.free(planet_list);

        for (0..config.n_planets) |i| {
            const id = uuid_generator.next();

            const planet = Planet.new(id, @as(u32, @intCast(config.map_size_x)), @as(u32, @intCast(config.map_size_y)), planet_list[0..i], random);
            try planets.put(id, planet);
            planet_list[i] = planet;
        }

        const players = try allocator.alloc(Player, config.n_players);
        for (players) |*p| p.* = .{ .id = 0, .ships = .empty, .resources = 0.0, .name = std.mem.zeroes([16]u8), .stdin = undefined, .stdout = undefined };

        return .{
            .size = .{ config.map_size_x, config.map_size_y },
            .planets = planets,
            .players = players,
            .uuid_generator = uuid_generator,
            .allocator = allocator,
            .prng = prng,
            .config = config,
        };
    }

    fn get_player_initial_position(self: *Self, i: u32) @Vector(2, f32) {
        var random = self.prng.random();
        var candidate = @Vector(2, f32){
            @as(f32, @floatFromInt(self.size[0])) * 0.5 + (@as(f32, @floatFromInt(self.size[0])) * 0.4) * @cos((2 * std.math.pi * @as(f32, @floatFromInt(i))) / @as(f32, @floatFromInt(self.players.len)) + random.float(f32)),
            @as(f32, @floatFromInt(self.size[1])) * 0.5 + (@as(f32, @floatFromInt(self.size[1])) * 0.4) * @sin((2 * std.math.pi * @as(f32, @floatFromInt(i))) / @as(f32, @floatFromInt(self.players.len)) + random.float(f32)),
        };

        while (!is_valid_spawn_point(candidate, self.planets)) {
            candidate[0] =
                @as(f32, @floatFromInt(self.size[0])) * 0.5 + (@as(f32, @floatFromInt(self.size[0])) * 0.4) * @cos((2 * std.math.pi * @as(f32, @floatFromInt(i))) / @as(f32, @floatFromInt(self.players.len)) + random.float(f32));
            candidate[1] =
                @as(f32, @floatFromInt(self.size[1])) * 0.5 + (@as(f32, @floatFromInt(self.size[1])) * 0.4) * @sin((2 * std.math.pi * @as(f32, @floatFromInt(i))) / @as(f32, @floatFromInt(self.players.len)) + random.float(f32));
        }

        return candidate;
    }

    pub fn add_player(self: *Self, id: IdLib.Id, name_raw: []const u8, stdin: std.Io.File, stdout: std.Io.File) !void {

        var name: [16]u8 = std.mem.zeroes([16]u8);
        const copy_len = @min(name_raw.len, 16);
        @memcpy(name[0..copy_len], name_raw[0..copy_len]);

        var i: u32 = 0;
        while (i < self.players.len and self.players[i].id != 0) : (i += 1) {}
        if (i == self.players.len) return error.NoMorePlayers;

        const pos = self.get_player_initial_position(i);

        var player = &self.players[i];
        player.* = .{
            .id = id,
            .ships = .empty,
            .resources = 0.0,
            .name = name,
            .stdin = stdin,
            .stdout = stdout,
        };

        try player.ships.append(self.allocator, try Ship.new(self.uuid_generator.next(), id, @as(@Vector(2, f64), @floatCast(pos)) + lut_thrusts[0][1]));
        try player.ships.append(self.allocator, try Ship.new(self.uuid_generator.next(), id, @as(@Vector(2, f64), @floatCast(pos)) + lut_thrusts[120][1]));
        try player.ships.append(self.allocator, try Ship.new(self.uuid_generator.next(), id, @as(@Vector(2, f64), @floatCast(pos)) + lut_thrusts[240][1]));
    }

    pub const SpatialMap = std.AutoHashMap(u64, std.ArrayListUnmanaged(*Ship));

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
                    gop.value_ptr.* = .empty;
                }
                try gop.value_ptr.append(self.allocator, ship);
            }
        }
        return spatial_map;
    }

    pub fn one_player_remaining(self: *Self) bool {
        var alive: u32 = 0;
        for (self.players) |player| {
            if (player.ships.items.len > 0) alive += 1;
        }
        return alive <= 1;
    }

    pub fn get_winner(self: *Self) ?*Player {
        var best_player: ?*Player = null;
        var best_ships: usize = 0;
        var best_resources: f64 = 0;
        var tied = false;

        for (self.players) |*player| {
            const ship_count = player.ships.items.len;
            if (ship_count > best_ships) {
                best_ships = ship_count;
                best_resources = player.resources;
                best_player = player;
                tied = false;
            } else if (ship_count == best_ships) {
                if (player.resources > best_resources) {
                    best_resources = player.resources;
                    best_player = player;
                    tied = false;
                } else if (player.resources == best_resources) {
                    tied = true;
                }
            }
        }

        return if (tied) null else best_player;
    }
    pub fn deinit(self: *Self) void {
        self.planets.deinit();
        for (self.players) |*player| {
            if (player.id != 0) player.deinit(self.allocator);
        }
        self.allocator.free(self.players);
    }
};

fn is_valid_spawn_point(position: @Vector(2, f32), planets: PlanetList) bool {
    var it = planets.valueIterator();
    while (it.next()) |planet| {
        const d2 = distSq(position, planet.position);
        const min_dist = planet.size + SHIP_RADIUS * 5 + 15.0; // enough room for the 3-ship triangle
        if (d2 < min_dist * min_dist) {
            return false;
        }
    }
    return true;
}

const std = @import("std");
const Planet = @import("planet.zig").Planet;
const PlanetList = @import("planet.zig").PlanetList;
const Player = @import("player.zig").Player;
const Ship = @import("ship.zig").Ship;
const ShipList = @import("ship.zig").ShipList;
const SHIP_RADIUS = @import("ship.zig").SHIP_RADIUS;
const IdLib = @import("id.zig");
const Config = @import("config.zig").Config;
const lut_thrusts = @import("utils.zig").lut_thrusts;
const distSq = @import("utils.zig").distSq;
