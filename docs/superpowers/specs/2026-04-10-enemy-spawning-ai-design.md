# Enemy Spawning & AI Design Spec

**Date:** 2026-04-10
**Scope:** Enemy entities, chase AI with steering behaviors, basic spawning system, network integration, view layer juice
**Not in scope:** Health/damage, combat, spells, death-by-player (enemies are immortal placeholders), audio

---

## Overview

Add the first enemies to Hexvael. Enemies spawn at arena edges, wander until they detect a player, then chase with steering behaviors (seek + separation). No combat yet — this proves that enemies exist, move believably, and sync across the network. Lays the foundation for the combat feel phase.

---

## 1. Enemy Entity

`EnemyEntity` (`/simulation/entities/enemy_entity.gd`) — a `CharacterBody2D`, pure simulation, no visuals.

### States

| State      | Behavior                                                        |
|------------|-----------------------------------------------------------------|
| `SPAWNING` | Telegraph period. No movement, no collision. Countdown timer.   |
| `IDLE`     | Slow wander toward random nearby points. Scans for players.     |
| `CHASING`  | Pursues target player with steering. Full collision.            |
| `DEAD`     | Server emits death event, removes entity next tick.             |

**Transitions:** `SPAWNING -> IDLE -> CHASING <-> IDLE -> DEAD`

- `SPAWNING -> IDLE`: `spawn_timer` reaches 0
- `IDLE -> CHASING`: player detected within `detection_radius`
- `CHASING -> IDLE`: target exceeds `leash_radius` and no other player in `detection_radius`
- `Any -> DEAD`: killed (future combat phase; for now, only via debug/testing)

### Parameters (Resource: `EnemyParams`)

```
base_speed: float                  # px/s, e.g. 120.0
speed_variation: float             # +/- fraction, e.g. 0.15 = +/-15%
turn_rate: float                   # rad/s, facing rotation speed
separation_radius: float           # distance for separation steering
separation_weight: float           # strength of separation vs seek
arrival_radius: float              # distance at which enemy slows to stop (melee range)
detection_radius: float            # max distance to acquire a target
leash_radius: float                # max distance to keep chasing (> detection_radius)
hysteresis_distance: float         # how much closer another player must be to steal aggro, e.g. 80px
base_spawn_duration: float         # seconds in SPAWNING state, e.g. 0.5
spawn_duration_variation: float    # +/- fraction, e.g. 0.15
```

### Fields

```
entity_id: int
state: int                  # SPAWNING, IDLE, CHASING, DEAD
position: Vector2
velocity: Vector2
facing: Vector2             # current facing direction (lerped, not instant)
target_player_id: int       # sticky aggro target (-1 = no target)
actual_speed: float         # randomized at spawn
spawn_timer: float          # countdown during SPAWNING state
```

**Per-enemy randomization at spawn (via RNG singleton):**
- `actual_speed = base_speed * (1.0 + RNG.next_float_range(-speed_variation, speed_variation))`
- `spawn_timer = base_spawn_duration * (1.0 + RNG.next_float_range(-spawn_duration_variation, spawn_duration_variation))`

### Key Methods

- `advance(dt: float)` — dt-independent simulation step. Handles state transitions, steering, movement.
- `to_snapshot_data() -> Dictionary` — serialize for network snapshot.
- `from_snapshot_data(data: Dictionary)` — deserialize (client-side reconstruction if needed).

### Collision Layers

- Enemy: own physics layer (layer 3)
- Mask: walls (layer 1) + players (layer 2)
- Does NOT mask other enemies — no enemy-enemy physics collision
- Players mask enemies — body-blocking works both ways

---

## 2. Steering & AI

### EnemySystem (`/simulation/systems/enemy_system.gd`)

Registry and tick driver for all enemies, analogous to `MovementSystem` for players.

**Interface:**

```
_enemies: Dictionary[int, EnemyEntity]
_spatial_grid: SpatialGrid

register_enemy(enemy: EnemyEntity)
unregister_enemy(entity_id: int)
get_enemy(entity_id: int) -> EnemyEntity
get_all_enemies() -> Array[EnemyEntity]
get_enemies_in_radius(pos: Vector2, radius: float) -> Array[EnemyEntity]
advance_all(dt: float)
```

### Tick Loop (`advance_all(dt)`)

1. Rebuild spatial grid (clear, re-insert all IDLE + CHASING enemies)
2. For each enemy, based on state:
   - `SPAWNING` — decrement `spawn_timer` by `dt`, transition to `IDLE` when <= 0
   - `IDLE` — slow wander toward random point, check for players within `detection_radius`
   - `CHASING` — run full steering toward target
   - `DEAD` — emit death event, remove from registry

### Steering (CHASING state, per enemy, per tick)

```
# 1. Target selection — sticky aggro with hysteresis
if no target OR target disconnected:
    target = nearest player within detection_radius (or none)
elif target distance > leash_radius:
    target = nearest player within detection_radius (or none -> IDLE)
elif another player is closer by > hysteresis_distance (e.g. 80px):
    target = that closer player

# 2. Seek direction
seek_dir = (target.position - enemy.position).normalized()

# 3. Separation — query spatial grid for nearby enemies
separation_dir = Vector2.ZERO
for neighbor in grid.query_nearby(enemy.position):
    if neighbor == self: continue
    offset = enemy.position - neighbor.position
    dist = offset.length()
    if dist < separation_radius and dist > 0:
        separation_dir += offset.normalized() / dist  # stronger when closer

# 4. Combine forces
desired_dir = (seek_dir + separation_dir * separation_weight).normalized()

# 5. Turn rate — exponential lerp facing toward desired direction
facing = facing.lerp(desired_dir, 1.0 - exp(-turn_rate * dt))

# 6. Arrival — slow down near target
dist_to_target = enemy.position.distance_to(target.position)
speed_factor = clampf(dist_to_target / arrival_radius, 0.0, 1.0)

# 7. Apply velocity
velocity = facing * actual_speed * speed_factor
move_and_slide()
```

All math is dt-independent: exponential lerp for turn rate, linear velocity, `move_and_slide()` for physics.

### Idle Wander (IDLE state)

- Pick a random point within ~50px of current position (via `RNG`)
- Drift toward it at ~30% of `actual_speed`
- When within 5px of wander target, pick a new one
- Each tick, check if any player is within `detection_radius` — if so, transition to CHASING

### Spatial Grid (`/simulation/systems/spatial_grid.gd`)

Pure data structure, ~40-50 lines. No Godot node dependencies. Runs identically headless.

```
cell_size: float                           # = separation_radius
grid: Dictionary[Vector2i, Array]          # cell -> entities in that cell

clear()
insert(entity)                             # hash position to cell, append
query_nearby(pos: Vector2) -> Array        # check 3x3 cells around pos
```

Rebuilt from scratch each tick. At 100 enemies: 100 inserts + 100 queries x 9 cells = trivial.

Also exposes `query_radius(pos, radius)` for future use (AoE spells, explosions).

---

## 3. Spawning System

### EnemySpawner (`/simulation/systems/enemy_spawner.gd`)

A system, not an entity. Manages enemy creation.

### Parameters (Resource: `SpawnerParams`)

```
spawn_interval: float           # seconds between spawn attempts, e.g. 2.0
batch_size: int                 # enemies per spawn attempt, e.g. 3
max_alive: int                  # cap on SPAWNING + IDLE + CHASING enemies, default 100
spawn_margin: float             # minimum distance from any player, e.g. 60px
spawn_edge_inset: float         # distance inside arena walls for spawn points, e.g. 16px
```

### Spawn Point Selection

1. Pick a random point along the arena perimeter, inset by `spawn_edge_inset`
2. Check distance to all players — reject if any player is within `spawn_margin`
3. Retry up to 5 times on rejection, then skip this enemy (don't stall the tick)

Edge-biased spawning means enemies enter from periphery and chase inward. When the world grows, swap spawn-point selection to "from stronghold direction" without changing anything else.

### Tick Logic (`advance(dt)`)

```
spawn_timer -= dt
if spawn_timer <= 0:
    spawn_timer = spawn_interval
    alive_count = count enemies in SPAWNING + IDLE + CHASING
    to_spawn = min(batch_size, max_alive - alive_count)
    for i in to_spawn:
        point = pick_spawn_point()
        if point == null: continue    # all attempts rejected
        enemy = create EnemyEntity at point, state=SPAWNING
        register with EnemySystem
        emit EventBus.enemy_spawned({entity_id, position, spawn_duration})
```

### Entity ID Allocation

Server maintains a monotonically increasing counter starting at 10000 (well above player ID range). Each enemy gets `next_enemy_id += 1`. Simple, no collision with player IDs, no reuse ambiguity. u16 supports up to 65535 before wrapping (not a concern at 100 max alive).

---

## 4. Network

### Snapshot Format Extension

Current: `[header] [player_count: u8] [player_entities...]`

Extended: `[header] [player_count: u8] [player_entities...] [enemy_count: u16] [enemy_entities...]`

**Binary layout per enemy entity (17 bytes):**

| Field         | Type | Bytes | Notes                                  |
|---------------|------|-------|----------------------------------------|
| `entity_id`   | u16  | 2     | 10000+ range                           |
| `x`           | f32  | 4     | position                               |
| `y`           | f32  | 4     | position                               |
| `state`       | u8   | 1     | SPAWNING=0, IDLE=1, CHASING=2          |
| `facing_x`    | f16  | 2     | half-float, unit vector component      |
| `facing_y`    | f16  | 2     | half-float, unit vector component      |
| `spawn_timer` | f16  | 2     | telegraph progress (SPAWNING state)    |

**Bandwidth:** 100 enemies x 17 bytes = 1.7KB per full snapshot. With delta compression (most enemies shift position slightly), typical deltas are much smaller.

**Delta compression:** Same approach as players. Diff against ACK'd baseline. Only include enemies whose data changed. Each entry prefixed with `entity_id` so the client knows which enemy to update.

**enemy_count is u16** (not u8) to support >255 entities in future, even though max_alive defaults to 100.

### Spawn Detection (Client)

Client compares current snapshot's enemy IDs to previous frame's. New ID -> local spawn event. No separate network message needed — the entity arrives in SPAWNING state, client renders the telegraph from snapshot data.

### Death Event (New Binary Message)

```
MESSAGE_TYPES.ENEMY_DIED = 5
```

**Binary layout (13 bytes):**

| Field       | Type | Bytes | Notes                            |
|-------------|------|-------|----------------------------------|
| `type`      | u8   | 1     | ENEMY_DIED constant              |
| `entity_id` | u16  | 2     | which enemy                      |
| `x`         | f32  | 4     | death position                   |
| `y`         | f32  | 4     | death position                   |
| `killer_id` | u16  | 2     | player who killed it (0 = none)  |

Sent once per death, before the entity disappears from the next snapshot. Client emits local `EventBus.enemy_died` signal. Even in a mass kill (20 enemies, one tick): 260 bytes.

### No Input Format Changes

Enemies are server-driven. Client sends no enemy-related inputs.

---

## 5. View Layer

All code in `/view/`. Never touches simulation state. Reads snapshots and EventBus signals only.

### EnemyView (`/view/world/enemy_view.gd`)

**Base visual:** 16x16 colored square (sickly green, configurable). Matches the player placeholder pattern — replaced with sprites later.

**Facing indicator:** Short line (4px) from center in the enemy's `facing` direction. Shorter than the player's aim line. Makes enemy intent visible — you can see who it's targeting.

**Idle wobble:** In IDLE state, subtle sinusoidal scale pulse: `1.0 + sin(time * wobble_freq) * 0.03`. Stops in CHASING state (chasing enemies feel purposeful, idle ones feel restless). View-only, reads state from snapshot.

### Spawn Telegraph (`/view/effects/spawn_telegraph.gd`)

When client detects a new enemy ID in SPAWNING state:
1. Draw a pulsing circle/shadow on the ground at spawn position
2. Circle starts transparent, fades in over the spawn duration
3. Scale grows slightly — "something is arriving"
4. Driven by `spawn_timer` from snapshot (stays synced with server)
5. On state transition to IDLE/CHASING, remove telegraph

### Spawn Pop

When enemy transitions out of SPAWNING: brief scale tween — 0.5x -> 1.1x -> 1.0x over ~0.15s. Enemy "arrives" rather than just appearing.

### WorldView Changes (`/view/world/world_view.gd`)

Extend with a parallel dictionary for `EnemyView` instances keyed by entity ID.

Each frame:
- For each enemy in snapshot: create `EnemyView` if new, update position/state/facing via interpolation
- For each `EnemyView` not in snapshot: remove (enemy was destroyed)

### Death Effect (`/view/effects/enemy_death_effect.gd`)

Listens to local `EventBus.enemy_died`. Spawns a brief particle burst or flash at death position. Simple placeholder — expanded when elements and combat juice arrive.

### Interpolation

Enemies use the same two-snapshot interpolation as remote players. Server sends at 20Hz, client smoothly interpolates each frame. No prediction.

---

## 6. EventBus Signals

### New Signals

```gdscript
signal enemy_spawned(event: Dictionary)
# {entity_id: int, position: Vector2, spawn_duration: float}

signal enemy_state_changed(event: Dictionary)
# {entity_id: int, old_state: int, new_state: int, position: Vector2}

signal enemy_target_changed(event: Dictionary)
# {entity_id: int, old_target_id: int, new_target_id: int, position: Vector2}
```

`enemy_died` and `enemy_hit` already exist on EventBus — `enemy_died` becomes active in this phase; `enemy_hit` stays dormant until combat.

---

## 7. Server Integration

### Tick Loop Changes (`net_server.gd`)

Current:
1. Process player inputs
2. `MovementSystem.advance_all(dt)`
3. Build + send snapshots

Extended:
1. Process player inputs
2. `MovementSystem.advance_all(dt)`
3. `EnemySpawner.advance(dt)`
4. `EnemySystem.advance_all(dt)`
5. Build + send snapshots (now includes enemy section)
6. Send any queued binary death events

Order matters: spawner creates enemies before the system ticks them, so newly spawned enemies get their first `advance()` in the same tick.

### Client Integration (`net_client.gd`)

- Parse extended snapshot format (player section, then enemy section)
- Handle new `ENEMY_DIED` binary message type
- Emit local EventBus signals for view layer consumption
- No prediction, no reconciliation for enemies

---

## 8. File Map

```
/simulation
  /entities
    enemy_entity.gd              # EnemyEntity CharacterBody2D
    enemy_entity.tscn            # collision shape only, no visuals
    enemy_params.gd              # EnemyParams Resource
  /systems
    enemy_system.gd              # registry, steering, tick driver
    enemy_spawner.gd             # spawn logic, timer, point selection
    spatial_grid.gd              # Dictionary-based spatial hash
    spawner_params.gd            # SpawnerParams Resource

/shared/network
  message_types.gd               # add ENEMY_DIED = 5

/view
  /world
    enemy_view.gd                # colored square, facing line, wobble
    enemy_view.tscn              # visual scene
  /effects
    spawn_telegraph.gd           # pulsing circle during SPAWNING
    enemy_death_effect.gd        # particle burst on death
```

---

## 9. Testing Strategy

All tests in `/tests/`, using GUT, runnable headless.

- **test_enemy_entity.gd** — state transitions, advance(dt) produces correct movement, spawn timer countdown, dt-independence
- **test_spatial_grid.gd** — insert/query correctness, cell boundaries, empty grid, single entity, many entities
- **test_enemy_steering.gd** — seek toward target, separation pushes apart, arrival slows down, turn rate lerps facing, combined steering
- **test_enemy_spawner.gd** — respects max_alive, spawn_margin rejection, batch_size, timer reset
- **test_enemy_aggro.gd** — sticky aggro, hysteresis, leash radius, detection radius, target disconnect retarget
- **test_enemy_idle.gd** — wander picks points, transitions to CHASING on player detection, stays IDLE outside detection_radius
- **test_enemy_snapshot.gd** — serialize/deserialize round-trip, delta compression with enemies, enemy_count encoding
- **test_enemy_death_message.gd** — binary encode/decode of ENEMY_DIED message
