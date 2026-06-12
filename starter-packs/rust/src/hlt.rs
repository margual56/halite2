use std::collections::HashMap;
use std::io::{self, BufRead, Write};

pub const DOCK_RADIUS: f64 = 4.0;
pub const SHIP_RADIUS: f64 = 0.5;
pub const MAX_SPEED: u32   = 7;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DockStatus { Undocked = 0, Docking = 1, Docked = 2, Undocking = 3 }

impl From<u32> for DockStatus {
    fn from(v: u32) -> Self {
        match v { 1 => Self::Docking, 2 => Self::Docked, 3 => Self::Undocking, _ => Self::Undocked }
    }
}

#[derive(Debug, Clone)]
pub struct Ship {
    pub id: u32, pub owner_id: u32,
    pub x: f64, pub y: f64, pub health: u32,
    pub status: DockStatus, pub planet_id: u32, pub docking_progress: u32,
}

impl Ship {
    pub fn is_undocked(&self) -> bool { self.status == DockStatus::Undocked }

    pub fn distance_to(&self, p: &Planet) -> f64 {
        ((p.x - self.x).powi(2) + (p.y - self.y).powi(2)).sqrt()
    }

    pub fn angle_to(&self, p: &Planet) -> u32 {
        let deg = (p.y - self.y).atan2(p.x - self.x).to_degrees();
        ((deg % 360.0 + 360.0) as u32) % 360
    }

    pub fn can_dock(&self, p: &Planet) -> bool {
        self.distance_to(p) <= p.size + DOCK_RADIUS + SHIP_RADIUS
    }
}

#[derive(Debug, Clone)]
pub struct Planet {
    pub id: u32,
    pub x: f64, pub y: f64, pub size: f64, pub halite: f64,
    pub owner_id: u32, pub docked_count: u32,
}

impl Planet {
    pub fn docking_spots(&self) -> u32 { self.size.floor() as u32 }
    pub fn is_full(&self) -> bool { self.docked_count >= self.docking_spots() }
}

#[derive(Debug)]
pub struct Player {
    pub id: u32,
    pub ships: HashMap<u32, Ship>,
}

pub struct GameMap {
    pub width: u32, pub height: u32,
    pub players: Vec<Player>,
    pub planets: HashMap<u32, Planet>,
    pub my_id: u32,
}

impl GameMap {
    pub fn me(&self) -> Option<&Player> {
        self.players.iter().find(|p| p.id == self.my_id)
    }
}

pub struct Game {
    pub map: GameMap,
    reader: io::BufReader<io::Stdin>,
    buf: String,
}

impl Game {
    pub fn new(name: &str) -> Self {
        let mut reader = io::BufReader::new(io::stdin());
        let mut buf = String::new();

        let mut next_line = |r: &mut io::BufReader<io::Stdin>, b: &mut String| -> String {
            b.clear();
            r.read_line(b).unwrap();
            b.trim_end().to_owned()
        };

        let l1 = next_line(&mut reader, &mut buf);
        let my_id: u32 = l1.trim().parse().unwrap();

        let l2 = next_line(&mut reader, &mut buf);
        let mut it2 = l2.split_whitespace();
        let width:  u32 = it2.next().unwrap().parse().unwrap();
        let height: u32 = it2.next().unwrap().parse().unwrap();

        let l3 = next_line(&mut reader, &mut buf);
        let (players, planets) = parse_state(&l3);

        print!("{}\n", name);
        io::stdout().flush().unwrap();

        Game {
            map: GameMap { width, height, players, planets, my_id },
            reader,
            buf,
        }
    }

    pub fn update_map(&mut self) -> &GameMap {
        self.buf.clear();
        self.reader.read_line(&mut self.buf).unwrap();
        let line = self.buf.trim_end().to_owned();
        let (players, planets) = parse_state(&line);
        self.map.players = players;
        self.map.planets = planets;
        &self.map
    }

    pub fn send_commands(&self, cmds: &[String]) {
        println!("{}", cmds.join(" "));
        io::stdout().flush().unwrap();
    }
}

fn parse_state(line: &str) -> (Vec<Player>, HashMap<u32, Planet>) {
    let tokens: Vec<&str> = line.split_whitespace().collect();
    let mut pos = 0;

    macro_rules! take_u32 {
        () => {{ let v: u32 = tokens[pos].parse().unwrap(); pos += 1; v }};
    }
    macro_rules! take_f64 {
        () => {{ let v: f64 = tokens[pos].parse().unwrap(); pos += 1; v }};
    }
    macro_rules! skip {
        () => {{ pos += 1; }};
    }

    let n_players = take_u32!() as usize;
    let mut players = Vec::with_capacity(n_players);
    for _ in 0..n_players {
        let pid     = take_u32!();
        let n_ships = take_u32!() as usize;
        let mut ships = HashMap::new();
        for _ in 0..n_ships {
            let sid      = take_u32!();
            let x        = take_f64!();
            let y        = take_f64!();
            let hp       = take_u32!();
            skip!(); skip!();           // vel_x, vel_y
            let docked   = take_u32!();
            let planet_id = take_u32!();
            let progress  = take_u32!();
            skip!();                    // weapon cooldown
            ships.insert(sid, Ship {
                id: sid, owner_id: pid,
                x, y, health: hp,
                status: docked.into(), planet_id, docking_progress: progress,
            });
        }
        players.push(Player { id: pid, ships });
    }

    let n_planets = take_u32!() as usize;
    let mut planets = HashMap::new();
    for _ in 0..n_planets {
        let pid      = take_u32!();
        let x        = take_f64!();
        let y        = take_f64!();
        skip!();                        // planet hp (255)
        let size     = take_f64!();
        skip!();                        // docking spots
        skip!();                        // current production
        let halite   = take_f64!();
        let owned    = take_u32!();
        let owner_id = take_u32!();
        let n_docked = take_u32!();
        for _ in 0..n_docked {
            skip!();                    // docked ship ids
        }
        planets.insert(pid, Planet {
            id: pid, x, y, size, halite,
            owner_id: if owned != 0 { owner_id } else { 0 },
            docked_count: n_docked,
        });
    }

    (players, planets)
}

pub fn thrust(ship_id: u32, magnitude: u32, angle: u32) -> String {
    format!("t {} {} {}", ship_id, magnitude.min(MAX_SPEED), angle % 360)
}

pub fn dock(ship_id: u32, planet_id: u32) -> String {
    format!("d {} {}", ship_id, planet_id)
}

pub fn undock(ship_id: u32) -> String {
    format!("u {}", ship_id)
}
