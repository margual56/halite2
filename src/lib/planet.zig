pub const PlanetList = std.AutoHashMap(Id, Planet);

pub const Planet = struct {
    id: Id,
    size: f64,
    halite: f64,
    position: @Vector(2, f32),
    docked_count: u32 = 0,

    pub fn docking_spots(self: Planet) u32 {
        return @intFromFloat(@floor(self.size));
    }

    const Self = @This();

    fn generate_planet_size(random: std.Random) f64 {
        const r = random.float(f64);

        // 60% of planets are Small
        if (r < 0.60) {
            return 2.0 + random.float(f64) * 0.5;
            // 30% of planets are Medium
        } else if (r < 0.90) {
            return 3.0 + random.float(f64) * 0.5;
            // 10% of planets are Large (the "jackpots")
        } else {
            return 4.0 + random.float(f64) * 1.0;
        }
    }

    pub fn new(id: Id, size_x: u32, size_y: u32, other_planets: []Planet, random: std.Random) Self {
        const size = generate_planet_size(random);

        var candidate_position = @Vector(2, f32){
            random.float(f32) * @as(f32, @floatFromInt(size_x)),
            random.float(f32) * @as(f32, @floatFromInt(size_y)),
        };

        while (!is_valid_planet_position(candidate_position, size, other_planets)) {
            candidate_position[0] = random.float(f32) * @as(f32, @floatFromInt(size_x));
            candidate_position[1] = random.float(f32) * @as(f32, @floatFromInt(size_y));
        }

        return .{
            .id = id,
            .size = size,
            .halite = 100 * size * (0.8 + (random.float(f64) * 0.4)),
            .position = candidate_position,
        };
    }
};

fn is_valid_planet_position(position: @Vector(2, f32), size: f64, other_planets: []Planet) bool {
    for (other_planets) |planet| {
        const d2 = distSq(position, planet.position);
        const min_dist = planet.size + size + SHIP_RADIUS;
        if (d2 < min_dist * min_dist) {
            return false;
        }
    }
    return true;
}

const std = @import("std");
const Id = @import("id.zig").Id;
const distSq = @import("utils.zig").distSq;
const SHIP_RADIUS = @import("ship.zig").SHIP_RADIUS;
