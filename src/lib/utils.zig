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

const std = @import("std");
const Ship = @import("ship.zig");
const Planet = @import("planet.zig");
const Id = @import("id.zig").Id;
