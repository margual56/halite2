/// HLT2 binary replay format (little-endian)
///
/// Header (written once):
///   [4]u8   magic = "HLT2"
///   u8      version = 1
///   u32     map_width
///   u32     map_height
///   u8      n_players
///   for each player:
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
///   for each planet (n_planets, unordered — match by id):
///     u32  id
///     f64  halite
///     u8   docked_count
pub const Replay = struct {
    file: std.Io.File,
    io: std.Io,

    pub fn init(file: std.Io.File, io: std.Io, map: *const Map) !Replay {
        const self = Replay{ .file = file, .io = io };
        var buf: [16384]u8 = undefined;
        var fw = file.writerStreaming(io, &buf);
        const w = &fw.interface;

        try w.writeAll("HLT2");
        try writeU8(w, 1); // version

        try writeU32(w, @intCast(map.size[0]));
        try writeU32(w, @intCast(map.size[1]));

        try writeU8(w, @intCast(map.players.len));
        for (map.players) |*player| {
            try writeU32(w, player.id);  // needed by visualizer to map owner_id → player slot
            try w.writeAll(&player.name);
        }

        try writeU32(w, @intCast(map.planets.count()));
        var pit = map.planets.valueIterator();
        while (pit.next()) |planet| {
            try writeU32(w, planet.id);
            try writeF64(w, planet.position[0]);
            try writeF64(w, planet.position[1]);
            try writeF64(w, planet.size);
            try writeF64(w, planet.halite);
            try writeU8(w, @intCast(planet.docking_spots()));
        }

        try fw.flush();
        return self;
    }

    pub fn writeTurn(self: *Replay, turn: u32, map: *const Map) !void {
        var buf: [16384]u8 = undefined;
        var fw = self.file.writerStreaming(self.io, &buf);
        const w = &fw.interface;

        try writeU32(w, turn);

        var n_ships: u32 = 0;
        for (map.players) |*player| n_ships += @intCast(player.ships.items.len);
        try writeU32(w, n_ships);

        for (map.players) |*player| {
            for (player.ships.items) |*ship| {
                try writeU32(w, ship.id);
                try writeU32(w, ship.owner_id);
                try writeF64(w, ship.position[0]);
                try writeF64(w, ship.position[1]);
                try writeU8(w, ship.health);
                try writeU8(w, switch (ship.state) {
                    .UNDOCKED  => 0,
                    .DOCKING   => 1,
                    .DOCKED    => 2,
                    .UNDOCKING => 3,
                });
                try writeU32(w, switch (ship.state) {
                    .DOCKING   => |d| d.id,
                    .DOCKED    => |id| id,
                    .UNDOCKING => |u| u.id,
                    .UNDOCKED  => 0,
                });
            }
        }

        var pit = map.planets.valueIterator();
        while (pit.next()) |planet| {
            try writeU32(w, planet.id);
            try writeF64(w, planet.halite);
            try writeU8(w, @intCast(planet.docked_count));
        }

        try fw.flush();
    }

    pub fn finish(self: *Replay) void {
        self.file.close(self.io);
    }
};

fn writeU8(w: *std.Io.Writer, v: u8) !void {
    try w.writeAll(&[1]u8{v});
}

fn writeU32(w: *std.Io.Writer, v: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, v, .little);
    try w.writeAll(&buf);
}

fn writeF64(w: *std.Io.Writer, v: f64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, @bitCast(v), .little);
    try w.writeAll(&buf);
}

const std = @import("std");
const Map = @import("map.zig").Map;
