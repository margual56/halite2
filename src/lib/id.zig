pub const Id = u32;

pub const UUIDGenerator = struct {
    /// A large prime number close to 2^32
    const PRIME = 2_654_435_761;

    counter: Id,

    const Self = @This();

    pub fn init(seed: Id) Self {
        return .{ .counter = seed };
    }

    pub fn next(self: *Self) Id {
        // Wrap-around addition
        self.counter = self.counter +% 1;

        // Wrap-around multiplication
        return self.counter *% PRIME;
    }
};
