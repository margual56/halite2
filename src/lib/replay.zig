/// HLT2 binary replay format (little-endian)
///
/// Header (written once):
///   [4]u8   magic = "HLT2"
///   u8      version = 1
///   u32     map_width
///   u32     map_height
///   u8      n_players
///   for each player:
///     u32     id
///     [16]u8  name
///   u32     n_planets
///   for each planet:
///     u32  id
///     f64  x, y
///     f64  size
///     f64  initial_halite
///     u8   docking_spots
///
/// Turn record (appended each turn):
///   u32  turn
///   u32  n_ships
///   for each ship:
///     u32  id
///     u32  owner_id
///     f64  x, y
///     u8   health
///     u8   state  (0=UNDOCKED 1=DOCKING 2=DOCKED 3=UNDOCKING)
///     u32  planet_id  (meaningful for states 1–3)
///   for each planet (n_planets):
///     u32  id
///     f64  halite
///     u8   docked_count
/// Footer (written once after all turns):
///   u8      n_players
///   for each player (sorted by rank, best first):
///     u32     id
///     u32     ship_count
///     f64     resources
///     u8      rank  (1 = winner)
pub const Replay = struct {
    /// Accumulates all bytes (header + turns) until finish() writes them.
    data: std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
    file: std.Io.File,
    io: std.Io,

    pub fn init(file: std.Io.File, io: std.Io, map: *const Map, allocator: std.mem.Allocator) !Replay {
        var self = Replay{
            .data = .empty,
            .allocator = allocator,
            .file = file,
            .io = io,
        };

        try self.data.appendSlice(allocator, "HLT2");
        try appendU8(&self.data, allocator, 1); // version

        try appendU32(&self.data, allocator, @intCast(map.size[0]));
        try appendU32(&self.data, allocator, @intCast(map.size[1]));

        try appendU8(&self.data, allocator, @intCast(map.players.len));
        for (map.players) |*player| {
            try appendU32(&self.data, allocator, player.id);
            try self.data.appendSlice(allocator, &player.name);
        }

        const n_planets: u32 = @intCast(map.planets.count());
        std.debug.print("[replay] header: {} players, {} planets\n", .{ map.players.len, n_planets });
        try appendU32(&self.data, allocator, n_planets);
        var pit = map.planets.valueIterator();
        while (pit.next()) |planet| {
            try appendU32(&self.data, allocator, planet.id);
            try appendF64(&self.data, allocator, planet.position[0]);
            try appendF64(&self.data, allocator, planet.position[1]);
            try appendF64(&self.data, allocator, planet.size);
            try appendF64(&self.data, allocator, planet.halite);
            try appendU8(&self.data, allocator, @intCast(planet.docking_spots()));
        }

        return self;
    }

    pub fn writeTurn(self: *Replay, turn: u32, map: *const Map) !void {
        try appendU32(&self.data, self.allocator, turn);

        var n_ships: u32 = 0;
        for (map.players) |*player| n_ships += @intCast(player.ships.items.len);
        try appendU32(&self.data, self.allocator, n_ships);

        for (map.players) |*player| {
            for (player.ships.items) |*ship| {
                try appendU32(&self.data, self.allocator, ship.id);
                try appendU32(&self.data, self.allocator, ship.owner_id);
                try appendF64(&self.data, self.allocator, ship.position[0]);
                try appendF64(&self.data, self.allocator, ship.position[1]);
                try appendU8(&self.data, self.allocator, ship.health);
                try appendU8(&self.data, self.allocator, switch (ship.state) {
                    .UNDOCKED => 0,
                    .DOCKING => 1,
                    .DOCKED => 2,
                    .UNDOCKING => 3,
                });
                try appendU32(&self.data, self.allocator, switch (ship.state) {
                    .DOCKING => |d| d.id,
                    .DOCKED => |id| id,
                    .UNDOCKING => |u| u.id,
                    .UNDOCKED => 0,
                });
            }
        }

        var pit = map.planets.valueIterator();
        while (pit.next()) |planet| {
            try appendU32(&self.data, self.allocator, planet.id);
            try appendF64(&self.data, self.allocator, planet.halite);
            try appendU8(&self.data, self.allocator, @intCast(planet.docked_count));
        }
    }

    pub fn finish(self: *Replay, map: *const Map) void {
        // --- Rankings footer ---
        // Sort players by ship count desc, then resources desc
        const RankedPlayer = struct {
            id: u32,
            ship_count: u32,
            resources: f64,
        };

        var ranked: [16]RankedPlayer = undefined; // max 16 players
        const n = map.players.len;
        for (map.players, 0..) |*player, i| {
            ranked[i] = .{
                .id = player.id,
                .ship_count = @intCast(player.ships.items.len),
                .resources = player.resources,
            };
        }

        // Bubble sort (n is tiny — 2–4 players)
        for (0..n) |i| {
            for (0..n - i - 1) |j| {
                const a = ranked[j];
                const b = ranked[j + 1];
                const a_better = a.ship_count > b.ship_count or
                    (a.ship_count == b.ship_count and a.resources > b.resources);
                if (!a_better) {
                    ranked[j] = b;
                    ranked[j + 1] = a;
                }
            }
        }

        appendU32(&self.data, self.allocator, 0xFFFFFFFF) catch {};
        appendU8(&self.data, self.allocator, @intCast(n)) catch {};
        for (ranked[0..n], 1..) |p, rank| {
            appendU32(&self.data, self.allocator, p.id) catch {};
            appendU32(&self.data, self.allocator, p.ship_count) catch {};
            appendF64(&self.data, self.allocator, p.resources) catch {};
            appendU8(&self.data, self.allocator, @intCast(rank)) catch {};
        }

        std.debug.print("[replay] finish: writing {} bytes total\n", .{self.data.items.len});
        defer {
            self.data.deinit(self.allocator);
            self.file.close(self.io);
        }
        var buf: [65536]u8 = undefined;
        var fw = self.file.writerStreaming(self.io, &buf);
        fw.interface.writeAll(self.data.items) catch |e| {
            std.debug.print("replay: write failed: {}\n", .{e});
            return;
        };
        fw.flush() catch |e| {
            std.debug.print("replay: flush failed: {}\n", .{e});
        };
    }
};

fn appendU8(list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, v: u8) !void {
    try list.append(allocator, v);
}

fn appendU32(list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, v: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, v, .little);
    try list.appendSlice(allocator, &buf);
}

fn appendF64(list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, v: f64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, @bitCast(v), .little);
    try list.appendSlice(allocator, &buf);
}

const std = @import("std");
const Map = @import("map.zig").Map;
