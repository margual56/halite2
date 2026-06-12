from dataclasses import dataclass, field
import math

DOCK_RADIUS = 4.0
SHIP_RADIUS = 0.5
MAX_SPEED   = 7


@dataclass
class Ship:
    id: int
    owner_id: int
    x: float
    y: float
    health: int
    docked_status: int    # 0=UNDOCKED 1=DOCKING 2=DOCKED 3=UNDOCKING
    planet_id: int        # meaningful when docked_status != 0
    docking_progress: int

    @property
    def is_undocked(self) -> bool:
        return self.docked_status == 0

    def distance_to(self, other) -> float:
        return math.hypot(other.x - self.x, other.y - self.y)

    def angle_to(self, other) -> int:
        return int(math.degrees(math.atan2(other.y - self.y, other.x - self.x))) % 360

    def can_dock(self, planet: "Planet") -> bool:
        return self.distance_to(planet) <= planet.size + DOCK_RADIUS + SHIP_RADIUS


@dataclass
class Planet:
    id: int
    x: float
    y: float
    size: float
    halite: float
    owner_id: int = 0
    docked_count: int = 0

    @property
    def docking_spots(self) -> int:
        return int(self.size)

    @property
    def is_full(self) -> bool:
        return self.docked_count >= self.docking_spots


@dataclass
class Player:
    id: int
    ships: dict = field(default_factory=dict)  # ship_id -> Ship


@dataclass
class GameMap:
    width: int
    height: int
    players: list    # all players in parse order
    planets: dict    # planet_id -> Planet
    my_id: int       # this bot's player ID

    @property
    def me(self) -> Player:
        return next((p for p in self.players if p.id == self.my_id), Player(id=self.my_id))
