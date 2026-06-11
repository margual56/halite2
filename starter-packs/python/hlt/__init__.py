from .entities import Ship, Planet, Player, GameMap, DOCK_RADIUS, SHIP_RADIUS, MAX_SPEED
from .game import Game


def thrust(ship_id: int, angle: int, magnitude: int) -> str:
    return f"t {ship_id} {angle % 360} {min(MAX_SPEED, magnitude)}"

def dock(ship_id: int, planet_id: int) -> str:
    return f"d {ship_id} {planet_id}"

def undock(ship_id: int) -> str:
    return f"u {ship_id}"
