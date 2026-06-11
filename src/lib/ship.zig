pub const ShipList = std.ArrayListUnmanaged(Ship);
pub const DOCK_RADIUS = 4.0;
pub const SHIP_RADIUS = 0.5;

pub const ShipState = union(enum) {
    /// Docking planet in x turns
    DOCKING: struct { id: Id, turns: u8 },
    DOCKED: Id,

    /// Undocking planet in x turns
    UNDOCKING: struct { id: Id, turns: u8 },
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

    pub fn validate_command(self: Self, command: ShipCommand, planets: PlanetList, config: Config) !void {
        switch (command) {
            .THRUST => |thrust| {
                if (@as(f64, @floatFromInt(thrust.magnitude)) > config.max_velocity) {
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
const Id = @import("id.zig").Id;
const lut_thrusts = @import("utils.zig").lut_thrusts;
const PlanetList = @import("planet.zig").PlanetList;
const Config = @import("config.zig").Config;
const dist = @import("utils.zig").dist;
