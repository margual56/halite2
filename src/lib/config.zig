pub const Config = struct {
    n_players: u8,
    n_planets: u16,
    map_size_x: u32,
    map_size_y: u32,

    max_turns: u32 = 100,
    ship_damage: u8 = 64,
    /// Turns to dock AND undock
    turns_to_dock: u8 = 5,
    max_velocity: f64 = 7.0,

    /// Maximum time for the players to respond to
    /// the Initialization Handshake (in seconds)
    initialization_timeout: u32 = 60,

    /// Maximum processing time for the players
    /// per turn (in seconds)
    turn_timeout: u32 = 2,

    /// Halite mined per docked ship per turn, as a fraction of remaining halite
    mining_rate: f64 = 0.02,
    /// Halite cost to spawn a new ship
    ship_cost: f64 = 40.0,
    /// Turns between ship spawns (per planet)
    ship_spawn_interval: u8 = 8,
};
