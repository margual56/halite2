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
    my_id: u32,
    players: []Player,
    planets: std.AutoHashMap(u32, Planet),
    allocator: std.mem.Allocator,

    pub fn me(self: *GameMap) ?*Player {
        for (self.players) |*p| {
            if (p.id == self.my_id) return p;
        }
        return null;
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
    my_id: u32,
    map: GameMap,
    // 32 KB — enough for a state line with ~200 ships and 5 planets
    in_buf: [32768]u8 = undefined,
    out_buf: [512]u8 = undefined,

    pub fn init(io: std.Io, name: []const u8, allocator: std.mem.Allocator) !Game {
        var stdin = std.Io.File.stdin();
        var stdout = std.Io.File.stdout();
        var in_buf: [32768]u8 = undefined;
        var out_buf: [512]u8 = undefined;
        var r = stdin.readerStreaming(io, &in_buf);
        var w = stdout.writerStreaming(io, &out_buf);

        // Line 1: my_player_id
        const l1 = try r.interface.takeDelimiterExclusive('\n');
        r.interface.toss(1);
        const my_id = try std.fmt.parseInt(u32, std.mem.trimEnd(u8, l1, "\r"), 10);

        // Line 2: width height
        const l2 = try r.interface.takeDelimiterExclusive('\n');
        r.interface.toss(1);
        var it2 = std.mem.tokenizeScalar(u8, l2, ' ');
        const width = try std.fmt.parseInt(u32, it2.next().?, 10);
        const height = try std.fmt.parseInt(u32, it2.next().?, 10);

        // Line 3: full game state
        const l3 = try r.interface.takeDelimiterExclusive('\n');
        r.interface.toss(1);
        const state = try parseState(l3, allocator);

        // Send bot name
        try w.interface.print("{s}\n", .{name});
        try w.flush();

        return .{
            .io = io,
            .stdin = stdin,
            .stdout = stdout,
            .my_id = my_id,
            .map = .{
                .width = width,
                .height = height,
                .my_id = my_id,
                .players = state.players,
                .planets = state.planets,
                .allocator = allocator,
            },
            .in_buf = in_buf,
            .out_buf = out_buf,
        };
    }

    pub fn update_map(self: *Game) !*GameMap {
        var r = self.stdin.readerStreaming(self.io, &self.in_buf);
        const line = try r.interface.takeDelimiterExclusive('\n');
        r.interface.toss(1);

        // Replace map contents with fresh parse
        for (self.map.players) |*p| p.ships.deinit();
        self.map.allocator.free(self.map.players);
        self.map.planets.deinit();

        const state = try parseState(line, self.map.allocator);
        self.map.players = state.players;
        self.map.planets = state.planets;

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

const ParseState = struct {
    players: []Player,
    planets: std.AutoHashMap(u32, Planet),
};

fn parseState(line: []const u8, allocator: std.mem.Allocator) !ParseState {
    var it = std.mem.tokenizeAny(u8, line, " \r");

    const n_players = try std.fmt.parseInt(u32, it.next() orelse return error.BadState, 10);
    const players = try allocator.alloc(Player, n_players);
    errdefer allocator.free(players);

    for (players) |*player| {
        const pid = try std.fmt.parseInt(u32, it.next() orelse return error.BadState, 10);
        const n_ships = try std.fmt.parseInt(u32, it.next() orelse return error.BadState, 10);
        player.* = .{ .id = pid, .ships = std.AutoHashMap(u32, Ship).init(allocator) };

        for (0..n_ships) |_| {
            const sid = try std.fmt.parseInt(u32, it.next() orelse return error.BadState, 10);
            const x = try std.fmt.parseFloat(f64, it.next() orelse return error.BadState);
            const y = try std.fmt.parseFloat(f64, it.next() orelse return error.BadState);
            const hp = try std.fmt.parseInt(u8, it.next() orelse return error.BadState, 10);
            _ = it.next(); // vel_x
            _ = it.next(); // vel_y
            const docked = try std.fmt.parseInt(u8, it.next() orelse return error.BadState, 10);
            const planet_id = try std.fmt.parseInt(u32, it.next() orelse return error.BadState, 10);
            const progress = try std.fmt.parseInt(u8, it.next() orelse return error.BadState, 10);
            _ = it.next(); // weapon cooldown
            try player.ships.put(sid, .{
                .id = sid,
                .owner_id = pid,
                .x = x,
                .y = y,
                .health = hp,
                .status = @enumFromInt(docked),
                .planet_id = planet_id,
                .docking_progress = progress,
            });
        }
    }

    const n_planets = try std.fmt.parseInt(u32, it.next() orelse return error.BadState, 10);
    var planets = std.AutoHashMap(u32, Planet).init(allocator);
    errdefer planets.deinit();

    for (0..n_planets) |_| {
        const pid = try std.fmt.parseInt(u32, it.next() orelse return error.BadState, 10);
        const x = try std.fmt.parseFloat(f64, it.next() orelse return error.BadState);
        const y = try std.fmt.parseFloat(f64, it.next() orelse return error.BadState);
        _ = it.next(); // planet hp (255)
        const size = try std.fmt.parseFloat(f64, it.next() orelse return error.BadState);
        _ = it.next(); // docking spots
        _ = it.next(); // current production
        const halite = try std.fmt.parseFloat(f64, it.next() orelse return error.BadState);
        const owned = try std.fmt.parseInt(u32, it.next() orelse return error.BadState, 10);
        const owner_id = try std.fmt.parseInt(u32, it.next() orelse return error.BadState, 10);
        const n_docked = try std.fmt.parseInt(u32, it.next() orelse return error.BadState, 10);
        for (0..n_docked) |_| _ = it.next(); // docked ship ids
        try planets.put(pid, .{
            .id = pid,
            .x = x,
            .y = y,
            .size = size,
            .halite = halite,
            .owner_id = if (owned != 0) owner_id else 0,
            .docked_count = n_docked,
        });
    }

    return .{ .players = players, .planets = planets };
}

pub fn cmd_thrust(buf: []u8, ship_id: u32, mag: u8, angle: u16) []u8 {
    return std.fmt.bufPrint(buf, "t {d} {d} {d}", .{ ship_id, @min(MAX_SPEED, mag), angle % 360 }) catch unreachable;
}

pub fn cmd_dock(buf: []u8, ship_id: u32, planet_id: u32) []u8 {
    return std.fmt.bufPrint(buf, "d {d} {d}", .{ ship_id, planet_id }) catch unreachable;
}

pub fn cmd_undock(buf: []u8, ship_id: u32) []u8 {
    return std.fmt.bufPrint(buf, "u {d}", .{ship_id}) catch unreachable;
}

const std = @import("std");
