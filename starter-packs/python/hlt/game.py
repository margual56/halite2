import sys
from .entities import Ship, Planet, Player, GameMap


class Game:
    def __init__(self, name: str):
        parts = input().split()
        n_players, my_index = int(parts[0]), int(parts[1])

        wh = input().split()
        width, height = int(wh[0]), int(wh[1])

        n_planets = int(input())
        planets: dict = {}
        for _ in range(n_planets):
            p = input().split()
            pid = int(p[0])
            planets[pid] = Planet(
                id=pid, x=float(p[1]), y=float(p[2]),
                size=float(p[3]), halite=float(p[6]),
            )

        self._n_players = n_players
        self._n_planets = n_planets
        self._map = GameMap(
            width=width, height=height,
            players=[Player(id=i) for i in range(n_players)],
            planets=planets,
            my_player_index=my_index,
        )

        print(name, flush=True)

    def update_map(self) -> GameMap:
        _turn = input()  # turn number, unused here

        for slot in range(self._n_players):
            hdr = input().split()
            player_id, n_ships = int(hdr[0]), int(hdr[1])
            ships: dict = {}
            for _ in range(n_ships):
                s = input().split()
                sid = int(s[0])
                ships[sid] = Ship(
                    id=sid, owner_id=player_id,
                    x=float(s[1]), y=float(s[2]),
                    health=int(s[3]),
                    docked_status=int(s[4]),
                    planet_id=int(s[5]),
                    docking_progress=int(s[6]),
                )
            self._map.players[slot] = Player(id=player_id, ships=ships)

        for _ in range(self._n_planets):
            pp = input().split()
            pid = int(pp[0])
            self._map.planets[pid].owner_id    = int(pp[1])
            self._map.planets[pid].docked_count = int(pp[2])
            self._map.planets[pid].halite       = float(pp[4])

        return self._map

    def send_commands(self, commands: list) -> None:
        print(' '.join(commands), flush=True)
