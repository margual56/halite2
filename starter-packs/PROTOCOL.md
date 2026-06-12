# HLT2 Bot Communication Protocol

Bots communicate with the engine over **stdin/stdout** using newline-terminated text.
All numbers are base-10 ASCII.

---

## 1. Initialization (once, at game start)

### Engine → Bot

```
{my_player_id}
{map_width} {map_height}
<state line>
```

- `my_player_id` is the bot's own player ID for the whole game.
- The third line is the initial game state (see **State line format** below).
  At init time, player ship data may be incomplete — use it for planet positions only.

### Bot → Engine

```
{name}
```

A single line containing the bot's chosen display name.

---

## 2. Turn update (each turn)

### Engine → Bot

```
<state line>
```

One line containing the complete game state (see **State line format** below).

### Bot → Engine

All commands on **one line**, space-separated, terminated with `\n`.

```
t {ship_id} {magnitude} {angle}   THRUST: magnitude [0,7], angle [0,359]°
d {ship_id} {planet_id}           DOCK
u {ship_id}                       UNDOCK
```

An empty turn (no commands) must still send a blank line: `\n`

---

## 3. State line format

All entities for one game state on a **single space-separated line**:

```
{n_players}
  {player_id} {n_ships}
    {ship_id} {x} {y} {hp} {vel_x} {vel_y} {docked_status} {planet_id} {docking_progress} {cooldown}
    ...   ← n_ships ship records
  ...     ← n_players player blocks
{n_planets}
  {planet_id} {x} {y} {hp} {radius} {docking_spots} {cur_prod} {halite} {owned} {owner_id} {n_docked} [{docked_ship_id} ...]
  ...     ← n_planets planet records
```

**Docked status values:**

| Value | Meaning   |
|-------|-----------|
| 0     | UNDOCKED  |
| 1     | DOCKING   |
| 2     | DOCKED    |
| 3     | UNDOCKING |

- `vel_x`, `vel_y` are always `0` (snapshot of position, not in-flight velocity).
- `cooldown` is always `0`.
- `hp` for planets is always `255`.
- `cur_prod` is always `0` (not yet implemented).
- `planet_id` in ship records is `0` when `docked_status == 0`.
- `owner_id` is `0` and `owned` is `0` for unowned planets.
- `n_docked` docked ship IDs immediately follow the planet record.

---

## 4. Game over (once, at game end)

### Engine → Bot

```
done
{my_player_id} {my_rank}
{player_id} {ship_count} {resources:.2}    ← repeated for all players
```

- `rank` is **1-based**. `1` = winner.
- Bots may read this or ignore it — the engine closes stdin immediately after.

---

## 5. Constants

| Name          | Value | Notes                     |
|---------------|-------|---------------------------|
| MAX_SPEED     | 7     | Max thrust magnitude      |
| DOCK_RADIUS   | 4.0   | Distance to begin docking |
| SHIP_RADIUS   | 0.5   | Collision radius          |
| SHIP_HEALTH   | 255   | Starting / max health     |

---

## 6. Keeping starter packs in sync

The engine implementation lives in `src/lib/bot_protocol.zig`.
When the protocol changes, update this file **and** `bot_protocol.zig` together.
