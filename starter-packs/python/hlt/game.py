import sys
from .entities import Ship, Planet, Player, GameMap


class Game:
    def __init__(self, name: str):
        my_id = int(input())

        wh = input().split()
        width, height = int(wh[0]), int(wh[1])

        players, planets = _parse_state(input())

        self._my_id = my_id
        self._map = GameMap(
            width=width, height=height,
            players=players,
            planets=planets,
            my_id=my_id,
        )

        print(name, flush=True)

    def update_map(self) -> 'GameMap':
        players, planets = _parse_state(input())
        self._map.players = players
        self._map.planets = planets
        return self._map

    def send_commands(self, commands: list) -> None:
        print(' '.join(commands), flush=True)


def _parse_state(line: str):
    it = iter(line.split())

    def take_int():   return int(next(it))
    def take_float(): return float(next(it))
    def skip():       next(it)

    n_players = take_int()
    players = []
    for _ in range(n_players):
        pid    = take_int()
        n_ships = take_int()
        ships  = {}
        for _ in range(n_ships):
            sid      = take_int()
            x, y     = take_float(), take_float()
            hp       = take_int()
            skip(); skip()          # vel_x, vel_y
            docked   = take_int()
            planet_id = take_int()
            progress  = take_int()
            skip()                  # weapon cooldown
            ships[sid] = Ship(
                id=sid, owner_id=pid, x=x, y=y, health=hp,
                docked_status=docked, planet_id=planet_id,
                docking_progress=progress,
            )
        players.append(Player(id=pid, ships=ships))

    n_planets = take_int()
    planets   = {}
    for _ in range(n_planets):
        pid    = take_int()
        x, y   = take_float(), take_float()
        skip()                      # planet hp (255)
        size   = take_float()
        skip()                      # docking spots
        skip()                      # current production
        halite = take_float()
        owned  = take_int()
        owner_id = take_int()
        n_docked = take_int()
        for _ in range(n_docked):
            skip()                  # docked ship ids
        planets[pid] = Planet(
            id=pid, x=x, y=y, size=size, halite=halite,
            owner_id=owner_id if owned else 0,
            docked_count=n_docked,
        )

    return players, planets
