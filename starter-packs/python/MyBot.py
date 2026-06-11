from hlt import Game, thrust, dock, undock

game = Game("MyBot")

while True:
    game_map = game.update_map()
    me = game_map.me
    commands = []

    for ship in me.ships.values():
        if not ship.is_undocked:
            continue

        available = [p for p in game_map.planets.values() if not p.is_full]
        if not available:
            continue

        nearest = min(available, key=ship.distance_to)

        if ship.can_dock(nearest):
            commands.append(dock(ship.id, nearest.id))
        else:
            commands.append(thrust(ship.id, ship.angle_to(nearest),
                                   min(7, int(ship.distance_to(nearest)))))

    game.send_commands(commands)
