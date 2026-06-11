mod hlt;
use hlt::{dock, thrust};

fn main() {
    let mut game = hlt::Game::new("MyRustBot");

    loop {
        let map = game.update_map();
        let mut cmds: Vec<String> = Vec::new();

        for ship in map.me().ships.values() {
            if !ship.is_undocked() { continue; }

            let nearest = map.planets.values()
                .filter(|p| !p.is_full())
                .min_by(|a, b| {
                    ship.distance_to(a).partial_cmp(&ship.distance_to(b)).unwrap()
                });

            if let Some(planet) = nearest {
                if ship.can_dock(planet) {
                    cmds.push(dock(ship.id, planet.id));
                } else {
                    let angle = ship.angle_to(planet);
                    let speed = (ship.distance_to(planet) as u32).min(hlt::MAX_SPEED);
                    cmds.push(thrust(ship.id, angle, speed));
                }
            }
        }

        game.send_commands(&cmds);
    }
}
