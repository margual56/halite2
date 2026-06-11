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
    pub players: Vec<Player>,        // ordered; me is players[my_player_index]
    pub planets: HashMap<u32, Planet>,
    pub my_player_index: usize,
}

impl GameMap {
    pub fn me(&self) -> &Player { &self.players[self.my_player_index] }
}

pub struct Game {
    pub map: GameMap,
    n_planets: usize,
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
        let mut it1 = l1.split_whitespace();
        let n_players: usize = it1.next().unwrap().parse().unwrap();
        let my_index: usize  = it1.next().unwrap().parse().unwrap();

        let l2 = next_line(&mut reader, &mut buf);
        let mut it2 = l2.split_whitespace();
        let width:  u32 = it2.next().unwrap().parse().unwrap();
        let height: u32 = it2.next().unwrap().parse().unwrap();

        let l3 = next_line(&mut reader, &mut buf);
        let n_planets: usize = l3.trim().parse().unwrap();

        let mut planets = HashMap::new();
        for _ in 0..n_planets {
            let lp = next_line(&mut reader, &mut buf);
            let mut itp = lp.split_whitespace();
            let pid:  u32 = itp.next().unwrap().parse().unwrap();
            let px:   f64 = itp.next().unwrap().parse().unwrap();
            let py:   f64 = itp.next().unwrap().parse().unwrap();
            let size: f64 = itp.next().unwrap().parse().unwrap();
            let _:    &str = itp.next().unwrap(); // reserved "3"
            let _:    &str = itp.next().unwrap(); // reserved "0"
            let hal:  f64 = itp.next().unwrap().parse().unwrap();
            planets.insert(pid, Planet { id: pid, x: px, y: py, size, halite: hal, owner_id: 0, docked_count: 0 });
        }

        let players = (0..n_players).map(|i| Player { id: i as u32, ships: HashMap::new() }).collect();

        print!("{}\n", name);
        io::stdout().flush().unwrap();

        Game {
            map: GameMap { width, height, players, planets, my_player_index: my_index },
            n_planets,
            reader,
            buf,
        }
    }

    pub fn update_map(&mut self) -> &GameMap {
        let mut next = |r: &mut io::BufReader<io::Stdin>, b: &mut String| -> String {
            b.clear(); r.read_line(b).unwrap(); b.trim_end().to_owned()
        };

        next(&mut self.reader, &mut self.buf); // turn number

        for player in &mut self.map.players {
            let lhdr = next(&mut self.reader, &mut self.buf);
            let mut ith = lhdr.split_whitespace();
            player.id = ith.next().unwrap().parse().unwrap();
            let n_ships: usize = ith.next().unwrap().parse().unwrap();

            player.ships.clear();
            for _ in 0..n_ships {
                let ls = next(&mut self.reader, &mut self.buf);
                let mut its = ls.split_whitespace();
                let sid:  u32 = its.next().unwrap().parse().unwrap();
                let sx:   f64 = its.next().unwrap().parse().unwrap();
                let sy:   f64 = its.next().unwrap().parse().unwrap();
                let shp:  u32 = its.next().unwrap().parse().unwrap();
                let sst:  u32 = its.next().unwrap().parse().unwrap();
                let spid: u32 = its.next().unwrap().parse().unwrap();
                let sprg: u32 = its.next().unwrap().parse().unwrap();
                player.ships.insert(sid, Ship {
                    id: sid, owner_id: player.id,
                    x: sx, y: sy, health: shp,
                    status: sst.into(), planet_id: spid, docking_progress: sprg,
                });
            }
        }

        for _ in 0..self.n_planets {
            let lp = next(&mut self.reader, &mut self.buf);
            let mut itp = lp.split_whitespace();
            let pid:    u32 = itp.next().unwrap().parse().unwrap();
            let owner:  u32 = itp.next().unwrap().parse().unwrap();
            let docked: u32 = itp.next().unwrap().parse().unwrap();
            let _: &str = itp.next().unwrap(); // production
            let hal: f64 = itp.next().unwrap().parse().unwrap();
            if let Some(p) = self.map.planets.get_mut(&pid) {
                p.owner_id = owner; p.docked_count = docked; p.halite = hal;
            }
        }

        &self.map
    }

    pub fn send_commands(&self, cmds: &[String]) {
        println!("{}", cmds.join(" "));
        io::stdout().flush().unwrap();
    }
}

pub fn thrust(ship_id: u32, angle: u32, magnitude: u32) -> String {
    format!("t {} {} {}", ship_id, angle % 360, magnitude.min(MAX_SPEED))
}

pub fn dock(ship_id: u32, planet_id: u32) -> String {
    format!("d {} {}", ship_id, planet_id)
}

pub fn undock(ship_id: u32) -> String {
    format!("u {}", ship_id)
}
