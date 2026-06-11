pub const DOCK_RADIUS: f64 = 4.0;
pub const SHIP_RADIUS: f64 = 0.5;
pub const MAX_SPEED: u8 = 7;

pub const DockStatus = enum(u8) { undocked = 0, docking = 1, docked = 2, undocking = 3 };

pub const Ship = struct {
    id: u32,
    owner_id: u32,
    x: f64,
    y: f64,
    health: u8,
    status: DockStatus,
    planet_id: u32,
    docking_progress: u8,

    pub fn is_undocked(self: Ship) bool {
        return self.status == .undocked;
    }

    pub fn distance_to_planet(self: Ship, p: Planet) f64 {
        return @sqrt((p.x - self.x) * (p.x - self.x) + (p.y - self.y) * (p.y - self.y));
    }

    pub fn angle_to_planet(self: Ship, p: Planet) u16 {
        const deg = std.math.atan2(p.y - self.y, p.x - self.x) * (180.0 / std.math.pi);
        return @intFromFloat(@mod(deg + 360.0, 360.0));
    }

    pub fn can_dock(self: Ship, p: Planet) bool {
        return self.distance_to_planet(p) <= p.size + DOCK_RADIUS + SHIP_RADIUS;
    }
};

pub const Planet = struct {
    id: u32,
    x: f64,
    y: f64,
    size: f64,
    halite: f64,
    owner_id: u32 = 0,
    docked_count: u32 = 0,

    pub fn docking_spots(self: Planet) u32 {
        return @intFromFloat(@floor(self.size));
    }

    pub fn is_full(self: Planet) bool {
        return self.docked_count >= self.docking_spots();
    }
};

pub const Player = struct {
    id: u32,
    ships: std.AutoHashMap(u32, Ship),
};

pub const GameMap = struct {
    width: u32,
    height: u32,
    my_player_index: u32,
    players: []Player, // ordered; me is players[my_player_index]
    planets: std.AutoHashMap(u32, Planet),
    allocator: std.mem.Allocator,

    pub fn me(self: *GameMap) *Player {
        return &self.players[self.my_player_index];
    }

    pub fn deinit(self: *GameMap) void {
        for (self.players) |*p| p.ships.deinit();
        self.allocator.free(self.players);
        self.planets.deinit();
    }
};

pub const Game = struct {
    io: std.Io,
    stdin: std.Io.File,
    stdout: std.Io.File,
    n_players: u32,
    n_planets: u32,
    map: GameMap,
    in_buf: [4096]u8 = undefined,
    out_buf: [4096]u8 = undefined,

    pub fn init(io: std.Io, name: []const u8, allocator: std.mem.Allocator) !Game {
        var stdin = std.Io.File.stdin();
        var stdout = std.Io.File.stdout();
        var in_buf: [4096]u8 = undefined;
        var out_buf: [4096]u8 = undefined;
        var r = stdin.readerStreaming(io, &in_buf);
        var w = stdout.writerStreaming(io, &out_buf);

        // Line 1: n_players my_index
        const l1 = try r.interface.takeDelimiterExclusive('\n');
        r.interface.toss(1);
        var it1 = std.mem.tokenizeScalar(u8, l1, ' ');
        const n_players = try std.fmt.parseInt(u32, it1.next().?, 10);
        const my_index = try std.fmt.parseInt(u32, it1.next().?, 10);

        // Line 2: width height
        const l2 = try r.interface.takeDelimiterExclusive('\n');
        r.interface.toss(1);
        var it2 = std.mem.tokenizeScalar(u8, l2, ' ');
        const width = try std.fmt.parseInt(u32, it2.next().?, 10);
        const height = try std.fmt.parseInt(u32, it2.next().?, 10);

        // Line 3: n_planets
        const l3 = try r.interface.takeDelimiterExclusive('\n');
        r.interface.toss(1);
        const n_planets = try std.fmt.parseInt(u32, std.mem.trimEnd(u8, l3, "\r"), 10);

        var planets = std.AutoHashMap(u32, Planet).init(allocator);
        for (0..n_planets) |_| {
            const lp = try r.interface.takeDelimiterExclusive('\n');
            r.interface.toss(1);
            var itp = std.mem.tokenizeAny(u8, lp, " \r");
            const pid = try std.fmt.parseInt(u32, itp.next().?, 10);
            const px = try std.fmt.parseFloat(f64, itp.next().?);
            const py = try std.fmt.parseFloat(f64, itp.next().?);
            const psize = try std.fmt.parseFloat(f64, itp.next().?);
            _ = itp.next(); // reserved "3"
            _ = itp.next(); // reserved "0"
            const phal = try std.fmt.parseFloat(f64, itp.next().?);
            try planets.put(pid, .{ .id = pid, .x = px, .y = py, .size = psize, .halite = phal });
        }

        const players = try allocator.alloc(Player, n_players);
        for (players, 0..) |*p, i| p.* = .{ .id = @intCast(i), .ships = std.AutoHashMap(u32, Ship).init(allocator) };

        // Send name
        try w.interface.print("{s}\n", .{name});
        try w.flush();

        return .{
            .io = io,
            .stdin = stdin,
            .stdout = stdout,
            .n_players = n_players,
            .n_planets = n_planets,
            .map = .{ .width = width, .height = height, .my_player_index = my_index, .players = players, .planets = planets, .allocator = allocator },
            .in_buf = in_buf,
            .out_buf = out_buf,
        };
    }

    pub fn update_map(self: *Game) !*GameMap {
        var r = self.stdin.readerStreaming(self.io, &self.in_buf);

        const lturn = try r.interface.takeDelimiterExclusive('\n');
        r.interface.toss(1);
        _ = lturn; // turn number available if needed

        for (self.map.players) |*player| {
            const lhdr = try r.interface.takeDelimiterExclusive('\n');
            r.interface.toss(1);
            var ith = std.mem.tokenizeAny(u8, lhdr, " \r");
            player.id = try std.fmt.parseInt(u32, ith.next().?, 10);
            const n_ships = try std.fmt.parseInt(u32, ith.next().?, 10);

            player.ships.clearRetainingCapacity();
            for (0..n_ships) |_| {
                const ls = try r.interface.takeDelimiterExclusive('\n');
                r.interface.toss(1);
                var its = std.mem.tokenizeAny(u8, ls, " \r");
                const sid = try std.fmt.parseInt(u32, its.next().?, 10);
                const sx = try std.fmt.parseFloat(f64, its.next().?);
                const sy = try std.fmt.parseFloat(f64, its.next().?);
                const shp = try std.fmt.parseInt(u8, its.next().?, 10);
                const sst = try std.fmt.parseInt(u8, its.next().?, 10);
                const spid = try std.fmt.parseInt(u32, its.next().?, 10);
                const sprg = try std.fmt.parseInt(u8, its.next().?, 10);
                try player.ships.put(sid, .{
                    .id = sid,
                    .owner_id = player.id,
                    .x = sx,
                    .y = sy,
                    .health = shp,
                    .status = @enumFromInt(sst),
                    .planet_id = spid,
                    .docking_progress = sprg,
                });
            }
        }

        const pit = self.map.planets.valueIterator();
        _ = pit; // silence unused warning — we re-read below by planet count
        for (0..self.n_planets) |_| {
            const lp = try r.interface.takeDelimiterExclusive('\n');
            r.interface.toss(1);
            var itp = std.mem.tokenizeAny(u8, lp, " \r");
            const pid = try std.fmt.parseInt(u32, itp.next().?, 10);
            const owner = try std.fmt.parseInt(u32, itp.next().?, 10);
            const docked = try std.fmt.parseInt(u32, itp.next().?, 10);
            _ = itp.next(); // production
            const hal = try std.fmt.parseFloat(f64, itp.next().?);
            if (self.map.planets.getPtr(pid)) |p| {
                p.owner_id = owner;
                p.docked_count = docked;
                p.halite = hal;
            }
        }

        return &self.map;
    }

    pub fn send_commands(self: *Game, cmds: []const []const u8) !void {
        var w = self.stdout.writerStreaming(self.io, &self.out_buf);
        for (cmds, 0..) |cmd, i| {
            if (i > 0) try w.interface.writeAll(" ");
            try w.interface.writeAll(cmd);
        }
        try w.interface.writeAll("\n");
        try w.flush();
    }
};

pub fn cmd_thrust(buf: []u8, ship_id: u32, angle: u16, mag: u8) []u8 {
    return std.fmt.bufPrint(buf, "t {d} {d} {d}", .{ ship_id, angle % 360, @min(MAX_SPEED, mag) }) catch unreachable;
}

pub fn cmd_dock(buf: []u8, ship_id: u32, planet_id: u32) []u8 {
    return std.fmt.bufPrint(buf, "d {d} {d}", .{ ship_id, planet_id }) catch unreachable;
}

pub fn cmd_undock(buf: []u8, ship_id: u32) []u8 {
    return std.fmt.bufPrint(buf, "u {d}", .{ship_id}) catch unreachable;
}

const std = @import("std");
