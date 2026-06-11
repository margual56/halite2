# HLT2 Bot Communication Protocol

Bots communicate with the engine over **stdin/stdout** using newline-terminated text.
All numbers are base-10 ASCII. Floats use `:.2` formatting (two decimal places).

---

## 1. Initialization (once, at game start)

### Engine → Bot

```
{n_players} {my_player_index}
{map_width} {map_height}
{n_planets}
{planet_id} {x} {y} {size} 3 0 {halite}    ← repeated n_planets times
```

- `my_player_index` is **0-based**. In turn updates, the bot is at position
  `my_player_index` in the ordered player list (players are always sent in the
  same fixed order).
- The `3 0` fields in planet lines are reserved constants (max_docking_turns,
  owner placeholder); parse and discard.

### Bot → Engine

```
{name}
```

A single line containing the bot's chosen display name.

---

## 2. Turn update (each turn)

### Engine → Bot

```
{turn_number}
{player_id} {n_ships}          ← repeated n_players times, always in the same order
{ship_id} {x} {y} {health} {docked_status} {planet_id} {docking_progress} 0
...                            ← n_ships ship lines follow each player header
{planet_id} {owner_id} {docked_count} {production} {halite}   ← repeated n_planets times
```

**Docked status values:**

| Value | Meaning   |
|-------|-----------|
| 0     | UNDOCKED  |
| 1     | DOCKING   |
| 2     | DOCKED    |
| 3     | UNDOCKING |

- `planet_id` in ship lines is only meaningful when `docked_status != 0`.
- Planet lines have **no count prefix** — always read exactly `n_planets` lines.
- `production` is currently always `0` (not yet implemented).

### Bot → Engine

All commands on **one line**, space-separated, terminated with `\n`.

```
t {ship_id} {angle} {magnitude}   THRUST: angle [0,359]°, magnitude [0,7]
d {ship_id} {planet_id}           DOCK
u {ship_id}                       UNDOCK
```

Multiple commands are concatenated: `t 1 90 7 d 2 42 u 3\n`

An empty turn (no commands) must still send a blank line: `\n`

---

## 3. Constants

| Name             | Value | Notes                        |
|------------------|-------|------------------------------|
| MAX_SPEED        | 7     | Max thrust magnitude         |
| DOCK_RADIUS      | 4.0   | Distance to begin docking    |
| SHIP_RADIUS      | 0.5   | Collision radius             |
| SHIP_HEALTH      | 255   | Starting health              |

---

## 4. Keeping starter packs in sync

The engine implementation lives in `src/lib/bot_protocol.zig`.
When the protocol changes, update this file **and** `bot_protocol.zig` together.
Each starter pack contains a minimal `NullBot` that only sends blank command lines —
run it against the engine to verify a pack still speaks the protocol correctly.
