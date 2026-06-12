pub const BotCommunicator = struct {
    /// Sends the one-time initialization handshake (Engine -> Bot)
    pub fn sendInit(self: *const BotCommunicator, writer: anytype, map: *Map, player_id: Id) !void {
        _ = self;
        // Line 1: <my_player_id>  (bot does int(line))
        try writer.print("{d}\n", .{player_id});
        // Line 2: <width> <height>
        try writer.print("{d} {d}\n", .{ map.size[0], map.size[1] });
        // Line 3: full game state (all entities, space-separated, single line)
        try writeGameState(writer, map);
        try writer.writeByte('\n');
    }

    /// Sends the universe state at the start of every turn
    pub fn sendTurnUpdate(self: *const BotCommunicator, writer: anytype, map: *Map, turn_number: u32) !void {
        _ = self;
        _ = turn_number;
        try writeGameState(writer, map);
        try writer.writeByte('\n');
    }

    /// Reads command stream from the bot and maps it to Zig structs
    pub fn readCommands(self: *const BotCommunicator, reader: *std.Io.Reader, allocator: std.mem.Allocator) !std.AutoHashMap(Id, ShipCommand) {
        _ = self;
        var commands = std.AutoHashMap(Id, ShipCommand).init(allocator);
        errdefer commands.deinit();

        const line = try reader.takeDelimiterExclusive('\n');

        // Manually skip over the 1-byte '\n' delimiter to advance the stream.
        reader.toss(1);

        // The Python SDK concatenates commands without separators between them
        // (e.g. "t 1 7 359t 2 5 180"). Pre-process to insert a space before
        // any command-type character (t/d/u) that directly follows a digit.
        var buf: [8192]u8 = undefined;
        var n: usize = 0;
        for (line) |c| {
            if ((c == 't' or c == 'd' or c == 'u') and n > 0 and buf[n - 1] != ' ') {
                buf[n] = ' ';
                n += 1;
            }
            buf[n] = c;
            n += 1;
        }
        const expanded = buf[0..n];
        var it = std.mem.tokenizeAny(u8, expanded, " \r");

        while (it.next()) |cmd_type| {
            if (std.mem.eql(u8, cmd_type, "t")) {
                const ship_id = try std.fmt.parseInt(Id, it.next() orelse return error.MalformedCommand, 10);
                const magnitude = try std.fmt.parseInt(u3, it.next() orelse return error.MalformedCommand, 10);
                const angle = try std.fmt.parseInt(u9, it.next() orelse return error.MalformedCommand, 10);
                try commands.put(ship_id, .{ .THRUST = .{ .angle = angle, .magnitude = magnitude } });
            } else if (std.mem.eql(u8, cmd_type, "d")) {
                const ship_id = try std.fmt.parseInt(Id, it.next() orelse return error.MalformedCommand, 10);
                const planet_id = try std.fmt.parseInt(u32, it.next() orelse return error.MalformedCommand, 10);
                try commands.put(ship_id, .{ .DOCK = planet_id });
            } else if (std.mem.eql(u8, cmd_type, "u")) {
                const ship_id = try std.fmt.parseInt(Id, it.next() orelse return error.MalformedCommand, 10);
                try commands.put(ship_id, .UNDOCK);
            }
        }

        return commands;
    }

    /// Sends the game-over message to a bot
    pub fn sendFinish(self: *const BotCommunicator, writer: anytype, map: *Map, player_id: Id, rank: u8) !void {
        _ = self;
        try writer.print("done\n", .{});
        try writer.print("{d} {d}\n", .{ player_id, rank });
        for (map.players) |player| {
            try writer.print("{d} {d} {d:.2}\n", .{
                player.id,
                player.ships.items.len,
                player.resources,
            });
        }
    }
};

/// Writes the full game state as a single space-separated line (no trailing newline).
/// Format matches the original Halite II protocol that Python bots expect:
///   <n_players> <p0_id> <p0_n_ships> <sid> <x> <y> <hp> <vx> <vy> <docked> <planet_id> <progress> <cooldown> ...
///   <n_planets> <plid> <x> <y> <hp> <r> <docking_spots> <cur_prod> <remaining> <owned> <owner> <n_docked> [ship_ids...]
fn writeGameState(writer: anytype, map: *Map) !void {
    // Players
    try writer.print("{d}", .{map.players.len});
    for (map.players) |player| {
        try writer.print(" {d} {d}", .{ player.id, player.ships.items.len });
        for (player.ships.items) |ship| {
            var status: u8 = 0;
            var planet_id: Id = 0;
            var progress: u8 = 0;
            switch (ship.state) {
                .UNDOCKED => {},
                .DOCKING => |d| {
                    status = 1;
                    planet_id = d.id;
                    progress = d.turns;
                },
                .DOCKED => |id| {
                    status = 2;
                    planet_id = id;
                },
                .UNDOCKING => |u| {
                    status = 3;
                    planet_id = u.id;
                    progress = u.turns;
                },
            }
            // sid x y hp vel_x vel_y docked_status docked_planet_id docking_progress cooldown
            try writer.print(" {d} {d:.4} {d:.4} {d} 0 0 {d} {d} {d} 0", .{
                ship.id,
                ship.position[0],
                ship.position[1],
                ship.health,
                status,
                planet_id,
                progress,
            });
        }
    }

    // Planets
    try writer.print(" {d}", .{map.planets.count()});
    var planet_it = map.planets.valueIterator();
    while (planet_it.next()) |planet| {
        // Determine ownership by scanning docked/docking/undocking ships
        var owner_id: Id = 0;
        var is_owned: u8 = 0;
        var n_docked: u32 = 0;
        for (map.players) |player| {
            for (player.ships.items) |ship| {
                const on_this = switch (ship.state) {
                    .DOCKED => |pid| pid == planet.id,
                    .DOCKING => |d| d.id == planet.id,
                    .UNDOCKING => |u| u.id == planet.id,
                    .UNDOCKED => false,
                };
                if (on_this) {
                    if (is_owned == 0) {
                        owner_id = player.id;
                        is_owned = 1;
                    }
                    n_docked += 1;
                }
            }
        }

        const docking_spots: u32 = @intFromFloat(@floor(planet.size));
        const halite_int: u64 = @intFromFloat(@round(planet.halite));
        // plid x y hp radius docking_spots current_prod remaining owned owner_id n_docked
        try writer.print(" {d} {d:.4} {d:.4} 255 {d:.4} {d} 0 {d} {d} {d} {d}", .{
            planet.id,
            planet.position[0],
            planet.position[1],
            planet.size,
            docking_spots,
            halite_int,
            is_owned,
            owner_id,
            n_docked,
        });

        // Docked ship IDs (second pass)
        for (map.players) |player| {
            for (player.ships.items) |ship| {
                const on_this = switch (ship.state) {
                    .DOCKED => |pid| pid == planet.id,
                    .DOCKING => |d| d.id == planet.id,
                    .UNDOCKING => |u| u.id == planet.id,
                    .UNDOCKED => false,
                };
                if (on_this) try writer.print(" {d}", .{ship.id});
            }
        }
    }
}

const std = @import("std");
const Map = @import("map.zig").Map;
const Id = @import("id.zig").Id;
const ShipCommand = @import("ship.zig").ShipCommand;
