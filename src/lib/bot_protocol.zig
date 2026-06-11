pub const BotCommunicator = struct {

    /// Sends the one-time initialization handshake (Engine -> Bot)
    pub fn sendInit(self: *const BotCommunicator, writer: anytype, map: *Map, player_id: Id) !void {
        _ = self;
        // Line 1: <number_of_players> <my_player_id>
        try writer.print("{d} {d}\n", .{ map.players.len, player_id });

        // Line 2: <width> <height>
        try writer.print("{d} {d}\n", .{ map.size[0], map.size[1] });

        // Line 3+: <num_planets> ...
        try writer.print("{d}\n", .{map.planets.count()});
        var planet_it = map.planets.valueIterator();
        while (planet_it.next()) |planet| {
            try writer.print("{d} {d:.2} {d:.2} {d:.2} 3 0 {d:.2}\n", .{
                planet.id, planet.position[0], planet.position[1], planet.size, planet.halite,
            });
        }
    }

    /// Sends the universe state at the start of every turn
    pub fn sendTurnUpdate(self: *const BotCommunicator, writer: anytype, map: *Map, turn_number: u32) !void {
        _ = self;
        try writer.print("{d}\n", .{turn_number});

        // Player Data
        for (map.players) |player| {
            try writer.print("{d} {d}\n", .{ player.id, player.ships.items.len });
            for (player.ships.items) |ship| {
                var status: u8 = 0;
                var planet_id: Id = 0;
                var progress: u8 = 0;

                switch (ship.state) {
                    .UNDOCKED => {
                        status = 0;
                    },
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

                // <ship_id> <x> <y> <health> <docked_status> <docked_planet_id> <docking_progress> <weapon_cooldown>
                try writer.print("{d} {d:.2} {d:.2} {d} {d} {d} {d} 0\n", .{
                    ship.id, ship.position[0], ship.position[1], ship.health,
                    status,  planet_id,        progress,
                });
            }
        }

        // Planet Data
        var planet_it = map.planets.valueIterator();
        while (planet_it.next()) |planet| {
            // <planet_id> <owner_id> <docked_ship_count> <current_production> <remaining_resources>
            // Mocking unowned (-1/0) and production for now
            try writer.print("{d} 0 0 0 {d:.2}\n", .{ planet.id, planet.halite });
        }
    }

    /// Reads command stream from the bot and maps it to Zig structs
    pub fn readCommands(self: *const BotCommunicator, reader: *std.Io.Reader, allocator: std.mem.Allocator) !std.AutoHashMap(Id, ShipCommand) {
        _ = self;
        var commands = std.AutoHashMap(Id, ShipCommand).init(allocator);
        errdefer commands.deinit();

        const line = try reader.takeDelimiterExclusive('\n');

        // Crucial: Manually skip over the 1-byte '\n' delimiter to advance the stream.
        reader.toss(1);

        var it = std.mem.tokenizeAny(u8, line, " \r"); // Handle windows CRLF implicitly

        while (it.next()) |cmd_type| {
            if (std.mem.eql(u8, cmd_type, "t")) {
                const ship_id = try std.fmt.parseInt(Id, it.next() orelse return error.MalformedCommand, 10);
                const angle = try std.fmt.parseInt(u9, it.next() orelse return error.MalformedCommand, 10);
                const magnitude = try std.fmt.parseInt(u3, it.next() orelse return error.MalformedCommand, 10);
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
};

const std = @import("std");
const Map = @import("map.zig").Map;
const Id = @import("id.zig").Id;
const ShipCommand = @import("ship.zig").ShipCommand;
