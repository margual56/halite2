mod hlt;
use hlt::{dock, thrust};

fn main() {
    let mut game = hlt::Game::new("StarterPackBot");

    loop {
        let map = game.update_map();
        let mut cmds: Vec<String> = Vec::new();

        if let Some(me) = map.me() {
            for ship in me.ships.values() {
                if !ship.is_undocked() {
                    continue;
                }

                let nearest = map
                    .planets
                    .values()
                    .filter(|p| !p.is_full())
                    .min_by(|a, b| {
                        ship.distance_to(a)
                            .partial_cmp(&ship.distance_to(b))
                            .unwrap()
                    });

                if let Some(planet) = nearest {
                    if ship.can_dock(planet) {
                        cmds.push(dock(ship.id, planet.id));
                    } else {
                        let speed = (ship.distance_to(planet) as u32).min(hlt::MAX_SPEED);
                        cmds.push(thrust(ship.id, speed, ship.angle_to(planet)));
                    }
                }
            }
        }

        game.send_commands(&cmds);
    }
}
