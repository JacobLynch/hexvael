# Projectiles — Phase 4 Design Spec

**Date:** 2026-04-11
**Scope:** Deterministic client-side projectile simulation, spawn/despawn network protocol, server-side shooter position rewind, collision against walls / enemies / players / self, 30 Hz server tick rate bump.
**Not in scope:** Damage application, health systems, knockback / impact force, multiple projectile types, friendly-fire toggles, lag-compensated hit validation against moving targets (Phase 6), projectile-vs-projectile collision, spatial-grid acceleration, tunneling fixes for `speed > radius / dt`.

---

## Overview

Add the first projectile to Hexvael. A placeholder "test" projectile that spawns forward of the shooter, travels in a straight line, and destroys itself on contact with any wall, enemy, player, or the shooter themselves (after a short self-immunity grace). No damage is applied on hit — the sole purpose of this phase is proving that the network architecture works end-to-end, that client prediction and server authority stay in sync, and that collision against every entity type fires as expected.

The architecture follows the `docs/projectiles.md` research document's Phase 4 recipe: deterministic client-side simulation of every projectile (both local and remote), driven by a single authoritative spawn event per projectile and a single authoritative despawn event per projectile. No per-tick projectile state in snapshots. The server also rewinds the shooter's position to fire time to eliminate reconciliation drift between the local shooter's predicted projectile and the authoritative one.

Phases 1, 2, 3, and 5 from `docs/projectiles.md` are already shipped (multiplayer foundation + movement feel + enemy spawning/AI). Phase 6 (lag-compensated hit validation against moving enemies) is deliberately not in scope; a future phase will add it on top of the same position-history ring buffer this phase introduces.

---

## 1. Goals and invariants

1. **Projectiles feel instant to fire.** No perceptible input lag between click and visual projectile on the local shooter's screen.
2. **Remote projectiles look correct.** No late-pop, no rubber-banding, no disagreement between clients watching the same shot.
3. **Every client simulates every projectile deterministically.** The server does not broadcast per-tick projectile state. One spawn event + one despawn event is enough for all clients to agree on the full path.
4. **Collision is authoritative on the server** for enemies and players. Wall collision is checked locally on every client as a deterministic optimization (walls are static).
5. **Pure `Vector2` math only.** No `move_and_collide`, no `Area2D`, no PhysicsServer, no rigid bodies. Projectile movement and collision are hand-rolled so they are identical on every machine.
6. **Simulation and view stay strictly separate**, per CLAUDE.md. `ProjectileSystem` lives in `/simulation`. Events flow out via `EventBus`. `/view` never mutates sim state, and never uses `RNG.*` (cosmetic jitter uses Godot `randf()`).

---

## 2. Tick rate bump: 20 Hz → 30 Hz

Before projectiles land, the server tick rate moves from 20 Hz (50 ms/tick) to 30 Hz (33.3 ms/tick). Rationale:

- Projectile spatial "tunneling" per tick is reduced by a third (20 px/tick at 600 px/s instead of 30 px/tick).
- Input processing latency drops ~16 ms in the worst case.
- Remote entity interpolation looks smoother at higher snapshot cadence.
- Bandwidth cost is ~50 % more snapshot traffic, comfortably within WebSocket budget for 8-player co-op.

### Changes

```gdscript
# /shared/network/message_types.gd
const TICK_RATE = 30                                 # was 20
const TICK_INTERVAL_MS: float = 1000.0 / TICK_RATE   # ≈ 33.33
```

`ACK_TIMEOUT_SECONDS` stays as-is; `ACK_TIMEOUT_TICKS` is derived and auto-scales. Any input rate limiter keyed on tick count must be reviewed since the same player can now legitimately push ~30 inputs/sec instead of ~20.

---

## 3. Architecture

### File layout

```
/simulation/entities/projectile_entity.gd       New. RefCounted. Pure data + advance(dt).
/simulation/systems/projectile_system.gd        New. Owns live dict, steps per tick, cooldowns.
/simulation/systems/projectile_spawn_router.gd  New. Shared fire-input dispatcher (server + client).
/simulation/systems/player_position_history.gd  New. Per-player position ring buffer on server.
/simulation/event_bus.gd                         Add: projectile_spawned, projectile_despawned signals.
/shared/projectiles/projectile_params.gd         New. Resource (speed, radius, lifetime, etc.).
/shared/projectiles/projectile_types.gd          New. Type enum + params lookup.
/shared/projectiles/test_projectile.tres         New. Resource instance for the v1 test projectile.
/shared/projectiles/collision_math.gd            New. circle_aabb_overlap, circle_circle_overlap.
/shared/projectiles/wall_geometry.gd             New. Extracts Array[Rect2] from arena scene.
/shared/network/message_types.gd                 Update: new Binary IDs, InputActionFlags, Layout sizes.
/view/projectiles/projectile_view.gd             New. Listens to EventBus, renders live sim position.
/simulation/input/keyboard_mouse_input_provider.gd  Update: fire_latch, action_flags packing.
/simulation/network/net_client.gd                Update: PROJECTILE_SPAWNED/DESPAWNED handlers.
/simulation/network/net_server.gd                Update: per-player RTT tracking, spawn/despawn broadcast.
```

### Data flow — local shooter fires

1. User left-clicks. `InputProvider` latches `fire = true`.
2. Next input tick, the client builds an input packet with the `FIRE` bit set in `action_flags` and ships it to the server via the existing input path.
3. In the same frame, the client's prediction code calls `ProjectileSpawnRouter.handle_fire(player, input, projectile_system, {authoritative: false})`. If the local `ProjectileSystem` cooldown is clear, this spawns a predicted projectile with temp id `-input_seq`.
4. Predicted projectile begins simulating immediately at display framerate via `ProjectileSystem.advance(frame_delta, [], [])`.
5. ~RTT/2 later the server receives the input. `MovementSystem` applies movement, then calls `ProjectileSpawnRouter.handle_fire(...)` with `{authoritative: true, rtt_ms, position_history, tick}`.
6. Server rewinds the shooter's position to `tick - round(rtt_ms/2 / TICK_INTERVAL_MS)` via `PlayerPositionHistory.lookup`, spawns the authoritative projectile at `rewound_pos + aim * spawn_offset`, and fast-forwards it by `rtt_ms/2000` seconds of straight-line travel so its authoritative position matches "server now." The fast-forward does **wall collision checks only** — enemies and players are not rewound.
7. Server queues a `PROJECTILE_SPAWNED` broadcast for end-of-tick. The packet's `origin` field is the projectile's post-fast-forward position.
8. ~RTT/2 later the broadcast reaches every client (including the shooter). Each client calls `ProjectileSystem.adopt_authoritative(...)`.
9. On the shooter: the adoption finds the predicted projectile by `temp_id = -input_seq`, rekeys the dict entry to the authoritative id, and reconciles any positional drift (typically < 10 px) over a 0.1 s lerp.
10. On remote clients: no matching predicted projectile exists, so adoption spawns a fresh projectile at `origin + direction * speed * (client_rtt_ms / 2000)` and begins deterministic simulation.

### Data flow — projectile despawn

1. Server `ProjectileSystem.advance(dt, players, enemies)` steps every active projectile and runs full collision (walls → enemies → players, in that fixed order). A hit returns a `DespawnReason`; lifetime expiry also returns one.
2. Server removes the projectile from its dict and queues a `PROJECTILE_DESPAWNED` broadcast carrying `{projectile_id, reason, x, y}`.
3. Each client receives the despawn event and removes the projectile from its own dict if still present. If the client already despawned it locally (e.g., because its own wall-only collision detected the same wall hit one tick earlier), the event is a silent no-op.
4. The view emits a despawn effect flavored by `reason` (wall spark, impact flash, soft fade, etc.).

### Key architectural decisions (from brainstorming)

| Decision | Choice | Reason |
|---|---|---|
| Projectile physics | Pure `Vector2` math | Godot physics is not bit-identical across machines; determinism is required for client sim of remote shots. |
| Projectile lifecycle sync | Spawn + despawn events, no per-tick snapshot state | Scales without bandwidth ceiling; zero per-tick cost per projectile; matches `projectiles.md` Phase 4 recipe. |
| Local shooter prediction | Yes, full `ProjectileSystem.spawn_predicted()` via shared router | Zero input lag; reconciliation via input_seq. |
| Server-side shooter rewind | Yes, via `PlayerPositionHistory` ring buffer | Eliminates drift between predicted and authoritative spawn origin for moving shooters. Lays foundation for Phase 6. |
| RTT source for server rewind | Server-measured via `SNAPSHOT_ACK` round trip | Keeps input packets lean; inverts trust direction. |
| Broadcast `origin` field | Server-now position (post fast-forward) | Remote clients only need their own one-way delay for catch-up; no need to know shooter's RTT. |
| `ProjectileEntity` type | `RefCounted` (plain data, no Node2D) | No scene presence needed; `ProjectileSystem` owns the dict; clean sim/view separation. |
| Client collision scope | Walls only in client sim; enemies/players via server despawn events | Client's interpolated enemy positions don't match server's authoritative positions, so client-local enemy collision would disagree. Wall collision is deterministic. |
| `MAX_ACTIVE` | 1024 | Next power-of-2 above the initial 256; fits u16 projectile id; leaves headroom for future chaining/forking. |
| Reconcile behavior | 0.1 s lerp on drift ≥ 2 px; snap on drift > 200 px | Hides typical RTT jitter; loud fallback on catastrophe. |
| Rejection handling | Predicted projectile times out at `2 × RTT + 0.1 s` if no adoption arrives | Cleans up orphans from rare server-side rejection without adding a dedicated "fire denied" message. |

---

## 4. Data structures

### `ProjectileParams` (Resource)

```gdscript
class_name ProjectileParams
extends Resource

@export var speed: float = 600.0          # px/sec
@export var lifetime: float = 1.5         # sec before self-despawn
@export var radius: float = 6.0           # collision radius
@export var spawn_offset: float = 40.0    # px forward of shooter at spawn
@export var spawn_grace: float = 0.10     # sec shooter immune to own projectile
@export var fire_cooldown: float = 0.20   # sec between shots for this projectile type
@export var impact_force: float = 0.0     # reserved for future push-enemies feel
```

One `.tres` instance at `shared/projectiles/test_projectile.tres` for the v1 test projectile.

### `ProjectileType` (static enum + lookup)

```gdscript
class_name ProjectileType

enum Id {
    TEST = 0,
}

static func get_params(type_id: int) -> ProjectileParams:
    match type_id:
        Id.TEST:
            return preload("res://shared/projectiles/test_projectile.tres")
    return null
```

### `ProjectileEntity` (`RefCounted`)

```gdscript
class_name ProjectileEntity
extends RefCounted

# Identity
var projectile_id: int = -1       # server-assigned u16, or negative temp id for predicted
var type_id: int = 0
var owner_player_id: int = -1

# State
var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.RIGHT    # unit vector
var time_remaining: float = 0.0           # counts down to 0
var spawn_grace_remaining: float = 0.0    # counts down, then owner is hit-able
var time_since_spawn: float = 0.0         # used by client rejection-timeout check
var params: ProjectileParams = null

# Reconciliation bookkeeping (client-side only)
var is_predicted: bool = false
var spawn_input_seq: int = -1
var _reconcile_delta: Vector2 = Vector2.ZERO
var _reconcile_remaining: float = 0.0
const RECONCILE_DURATION: float = 0.1

func initialize(
    id: int, type: int, owner: int,
    origin: Vector2, dir: Vector2,
    p: ProjectileParams) -> void: ...

# Dt-independent step. Returns a DespawnReason if killed this step, else ALIVE.
func advance(dt: float, walls: Array, players: Array, enemies: Array) -> int: ...

func start_reconcile(target: Vector2) -> void:
    _reconcile_delta = target - position
    _reconcile_remaining = RECONCILE_DURATION
```

### `ProjectileSystem.DespawnReason` (enum)

```gdscript
enum DespawnReason {
    ALIVE    = -1,
    LIFETIME = 0,
    WALL     = 1,
    ENEMY    = 2,
    PLAYER   = 3,
    SELF     = 4,
    REJECTED = 5,  # client-only; fires for predicted projectile with no adoption
}
```

### `ProjectileSystem` (Node)

```gdscript
class_name ProjectileSystem
extends Node

const MAX_ACTIVE = 1024

var projectiles: Dictionary = {}           # projectile_id -> ProjectileEntity
var _next_server_id: int = 1                # server-side monotonic, wraps at u16 max
var _walls: Array = []                      # Array[Rect2], built from arena at bootstrap
var _fire_cooldown: Dictionary = {}         # player_id -> seconds remaining
var _current_rtt_ms: int = 0                # local client's estimate, used for rejection timeout

func set_walls(aabbs: Array) -> void
func get_walls() -> Array

# Server-side spawn. Called by ProjectileSpawnRouter.
func spawn_authoritative(
    owner_id: int, type_id: int,
    origin: Vector2, direction: Vector2,
    input_seq: int) -> ProjectileEntity

# Client-side predicted spawn. Uses negative temp id = -input_seq.
func spawn_predicted(
    owner_id: int, type_id: int,
    origin: Vector2, direction: Vector2,
    input_seq: int) -> ProjectileEntity

# Client handler for PROJECTILE_SPAWNED arrival. Reconciles with a matching
# predicted projectile by input_seq if present, otherwise spawns fresh.
func adopt_authoritative(
    projectile_id: int, owner_id: int, type_id: int,
    origin: Vector2, direction: Vector2,
    input_seq: int, current_rtt_ms: int) -> void

# Client handler for PROJECTILE_DESPAWNED arrival. Idempotent.
func on_despawn_event(projectile_id: int, reason: int, pos: Vector2) -> void

# Per-tick step. Emits projectile_spawned/despawned via EventBus.
# Returns Array[{id, reason, position}] for any despawns this step.
func advance(dt: float, players: Array, enemies: Array) -> Array

func can_fire(player_id: int) -> bool
func start_cooldown(player_id: int) -> void
func tick_cooldowns(dt: float) -> void
```

### `PlayerPositionHistory` (server-only, `RefCounted`)

```gdscript
class_name PlayerPositionHistory
extends RefCounted

const MAX_SAMPLES = 32   # ~32 * 33.3 ms = 1066 ms window

var _samples_per_player: Dictionary = {}  # player_id -> Array[{tick: int, pos: Vector2}]

func record(player_id: int, tick: int, position: Vector2) -> void
func lookup(player_id: int, tick: int) -> Vector2   # returns closest sample on miss
func drop_player(player_id: int) -> void
```

Called from the server's tick loop immediately before `MovementSystem.advance()` so the most recent sample is available for same-tick fire processing.

### `ProjectileSpawnRouter` (static helper)

```gdscript
class_name ProjectileSpawnRouter

static func handle_fire(
    player: PlayerEntity,
    input: Dictionary,
    projectile_system: ProjectileSystem,
    context: Dictionary) -> void
```

See `§6. Prediction & reconciliation` for the full body.

---

## 5. Collision model

### Primitives

Pure math, deterministic, no `sqrt`. Both live in `/shared/projectiles/collision_math.gd`.

```gdscript
class_name CollisionMath

static func circle_aabb_overlap(
    center: Vector2, radius: float, rect: Rect2) -> bool:
    var closest_x := clampf(center.x, rect.position.x, rect.end.x)
    var closest_y := clampf(center.y, rect.position.y, rect.end.y)
    var dx := center.x - closest_x
    var dy := center.y - closest_y
    return (dx * dx + dy * dy) < (radius * radius)

static func circle_circle_overlap(
    a: Vector2, ra: float, b: Vector2, rb: float) -> bool:
    var sum := ra + rb
    return a.distance_squared_to(b) < (sum * sum)
```

### Wall geometry extraction

Walls live in `shared/world/arena.tscn` as `CollisionShape2D` children under a `Collision` node. Both server and client extract them into `Array[Rect2]` at startup, guaranteeing the projectile collision representation is derived from the same source of truth the rest of the game uses.

```gdscript
# /shared/projectiles/wall_geometry.gd
class_name WallGeometry

static func extract_aabbs(arena_root: Node) -> Array:
    var out: Array = []
    var collision := arena_root.get_node_or_null("Collision")
    assert(collision != null, "arena has no Collision node")
    for child in collision.get_children():
        if not (child is CollisionShape2D):
            continue
        var shape := (child as CollisionShape2D).shape
        assert(shape is RectangleShape2D, "non-rect wall shape not supported")
        var rect_shape: RectangleShape2D = shape
        var half: Vector2 = rect_shape.size / 2.0
        var center: Vector2 = child.global_position
        out.append(Rect2(center - half, rect_shape.size))
    return out
```

Called once during server and client bootstrap: `projectile_system.set_walls(WallGeometry.extract_aabbs(arena))`.

### Entity radii

`PlayerEntity` and `EnemyEntity` each gain a cached `get_collision_radius()` method that reads from their existing `CollisionShape2D` at first call and caches the result. This keeps the collision radius coupled to the actual scene shape, with no magic constants in `projectile_system.gd`.

```gdscript
var _cached_radius: float = -1.0
func get_collision_radius() -> float:
    if _cached_radius < 0.0:
        var shape_node := $CollisionShape2D as CollisionShape2D
        var shape := shape_node.shape
        if shape is CircleShape2D:
            _cached_radius = (shape as CircleShape2D).radius
        elif shape is RectangleShape2D:
            var s := (shape as RectangleShape2D).size
            _cached_radius = max(s.x, s.y) / 2.0
        else:
            push_warning("unknown collision shape type, falling back to 16 px")
            _cached_radius = 16.0
    return _cached_radius
```

### Per-projectile step

```gdscript
# ProjectileEntity.advance
func advance(dt: float, walls: Array, players: Array, enemies: Array) -> int:
    # 1. Motion (straight-line, dt-independent)
    position += direction * params.speed * dt

    # 2. Timers
    time_remaining -= dt
    spawn_grace_remaining -= dt
    time_since_spawn += dt

    # 3. Reconciliation lerp (if any)
    if _reconcile_remaining > 0.0:
        var chunk := min(dt, _reconcile_remaining)
        position += _reconcile_delta * (chunk / RECONCILE_DURATION)
        _reconcile_remaining -= chunk

    # 4. Lifetime
    if time_remaining <= 0.0:
        return ProjectileSystem.DespawnReason.LIFETIME

    # 5. Walls (static, always checked, safe on both server and client)
    for wall: Rect2 in walls:
        if CollisionMath.circle_aabb_overlap(position, params.radius, wall):
            return ProjectileSystem.DespawnReason.WALL

    # 6. Enemies (server-only; client passes empty array)
    for enemy: EnemyEntity in enemies:
        if enemy.state == EnemyEntity.State.DEAD:
            continue
        if CollisionMath.circle_circle_overlap(
                position, params.radius, enemy.position, enemy.get_collision_radius()):
            return ProjectileSystem.DespawnReason.ENEMY

    # 7. Players (server-only; owner excluded during spawn grace)
    for player: PlayerEntity in players:
        var is_owner := (player.player_id == owner_player_id)
        if is_owner and spawn_grace_remaining > 0.0:
            continue
        if CollisionMath.circle_circle_overlap(
                position, params.radius, player.position, player.get_collision_radius()):
            return (ProjectileSystem.DespawnReason.SELF
                    if is_owner else ProjectileSystem.DespawnReason.PLAYER)

    return ProjectileSystem.DespawnReason.ALIVE
```

### Client vs server collision scope

The client's `ProjectileSystem.advance()` always passes **empty arrays** for `players` and `enemies`, because the client's view of those entities is interpolated ~75-100 ms behind the server's authoritative positions:

```gdscript
# client tick / prediction frame
projectile_system.advance(dt, [], [])
```

Walls are still checked. Everything else comes from `PROJECTILE_DESPAWNED` events broadcast by the server. Consequence: on an enemy or player hit, the client's projectile visibly overshoots through the target by up to `speed × RTT/2` pixels before the despawn event arrives and plays the impact effect. Acceptable for Phase 4; removed by Phase 6 lag compensation.

### Collision order

Walls → enemies → players, fixed. Early return after the first hit so we never double-despawn. The fixed order guarantees that if two collisions could plausibly happen on the same step, every machine agrees on which one fires first.

### Self-collision

`spawn_grace = 0.10 s` and `spawn_offset = 40 px` work together. At 600 px/s the projectile travels 60 px during grace, safely past the shooter's collision radius. After grace, the shooter is hit-able by their own projectile — testing self-collision is as simple as firing and walking backwards into your own shot.

---

## 6. Prediction & reconciliation

### Local shooter fires (end-to-end timeline)

```
t = 0 ms     Shooter clicks
             ├─ InputProvider sets fire_latch = true
             └─ Next display frame, client input tick builds input with FIRE flag + input_seq N
                ├─ Client: PlayerEntity.apply_input(input)
                ├─ Client: ProjectileSpawnRouter.handle_fire(authoritative=false)
                │   ├─ Check client-local fire_cooldown — OK
                │   ├─ ProjectileSystem.spawn_predicted(
                │   │     owner=local_id, temp_id=-N,
                │   │     origin=local_pos + aim*spawn_offset,
                │   │     direction=aim, input_seq=N)
                │   └─ Client fire_cooldown[local] := params.fire_cooldown
                └─ Input packet with FIRE flag sent to server

t ≈ RTT/2    Server receives input
             ├─ MovementSystem.apply_input(player, input)
             ├─ ProjectileSpawnRouter.handle_fire(authoritative=true, rtt, history, tick)
             │   ├─ Check server authoritative fire_cooldown — OK
             │   ├─ rewind_ticks = round((rtt_ms / 2) / TICK_INTERVAL_MS)
             │   ├─ rewound_pos = position_history.lookup(player_id, tick - rewind_ticks)
             │   ├─ spawn_origin = rewound_pos + aim * spawn_offset
             │   ├─ proj = ProjectileSystem.spawn_authoritative(owner, spawn_origin, aim, N)
             │   ├─ proj.advance(rtt/2000, walls, [], [])  # catch up to server-now
             │   └─ Queue PROJECTILE_SPAWNED broadcast with origin := proj.position
             └─ Server fire_cooldown[player] := params.fire_cooldown

t ≈ RTT      Broadcast arrives at shooter
             └─ ProjectileSystem.adopt_authoritative(
                    projectile_id, owner_id, origin, direction, input_seq=N, rtt)
                 ├─ temp_id := -N
                 ├─ If projectiles[temp_id] exists AND owner matches:
                 │    ├─ predicted := projectiles[temp_id]
                 │    ├─ projectiles.erase(temp_id)
                 │    ├─ predicted.projectile_id := authoritative id
                 │    ├─ predicted.is_predicted := false
                 │    ├─ projectiles[authoritative_id] := predicted
                 │    ├─ expected := origin + direction * speed * (rtt/2/1000)
                 │    ├─ drift := predicted.position.distance_to(expected)
                 │    ├─ If drift < 2 px: no action
                 │    ├─ Elif drift < 200 px: predicted.start_reconcile(expected)
                 │    └─ Else: predicted.position = expected (hard snap, log warning)
                 └─ Else (no matching predicted): spawn fresh and fast-forward by rtt/2
```

### Spawn origin math — why the broadcast carries server-now, not the rewound origin

The packet's `origin` field is the projectile's position **after** the server's RTT/2 fast-forward, not the raw rewound spawn point. This matters so that remote clients only need their own one-way delay (`RTT_B/2`) for their catch-up calculation, not the shooter's (`RTT_A/2`), which they have no way to know.

Timeline in the shared virtual frame, measured from click:

```
shooter-side projectile at time t:    S0 + aim*offset + aim*speed*(t − 0)

server, receiving at RTT_A/2:
    rewinds to S0, spawns at S0 + aim*offset
    fast-forwards by RTT_A/2 → authoritative position "now":
                                      S0 + aim*offset + aim*speed*(RTT_A/2)
    broadcasts this as `origin`

remote B, receiving at RTT_A/2 + RTT_B/2:
    fast-forwards by RTT_B/2 (its own one-way delay):
                                      S0 + aim*offset + aim*speed*(RTT_A/2 + RTT_B/2)

virtual position at that same moment: S0 + aim*offset + aim*speed*(RTT_A/2 + RTT_B/2)  ✓
```

Shooter's own echo arrives at `RTT_A` full round-trip, fast-forwards by its own `RTT_A/2`, and converges on the same virtual position as its predicted projectile. Zero reconciliation drift in the nominal case; the lerp absorbs RTT jitter.

### `ProjectileSpawnRouter.handle_fire` body

```gdscript
static func handle_fire(
    player: PlayerEntity,
    input: Dictionary,
    projectile_system: ProjectileSystem,
    context: Dictionary) -> void:

    if not (input.get("action_flags", 0) & InputActionFlags.FIRE):
        return
    if not projectile_system.can_fire(player.player_id):
        return

    var aim: Vector2 = player.aim_direction
    var type_id: int = ProjectileType.Id.TEST
    var params: ProjectileParams = ProjectileType.get_params(type_id)

    if context.get("authoritative", false):
        var rtt_ms: int = context["rtt_ms"]
        var history: PlayerPositionHistory = context["position_history"]
        var tick: int = context["tick"]
        var rewind_ticks := int(round((rtt_ms / 2.0) / MessageTypes.TICK_INTERVAL_MS))
        var rewound_pos := history.lookup(player.player_id, tick - rewind_ticks)
        var origin := rewound_pos + aim * params.spawn_offset
        var proj := projectile_system.spawn_authoritative(
            player.player_id, type_id, origin, aim, input["input_seq"])
        proj.advance(rtt_ms / 2000.0, projectile_system.get_walls(), [], [])
        context["spawn_events"].append({
            "projectile_id": proj.projectile_id,
            "type_id": type_id,
            "owner_player_id": player.player_id,
            "origin": proj.position,   # server-now, post fast-forward
            "direction": aim,
            "input_seq": input["input_seq"],
        })
    else:
        var origin := player.position + aim * params.spawn_offset
        projectile_system.spawn_predicted(
            player.player_id, type_id, origin, aim, input["input_seq"])

    projectile_system.start_cooldown(player.player_id)
```

### Rejection handling

If the server rejects a fire (cooldown disagreement from input race, dead shooter, etc.), no spawn broadcast ever arrives. The predicted projectile tracks `time_since_spawn` (incremented inside `ProjectileEntity.advance()` alongside the other timers). The timeout check itself lives in `ProjectileSystem.advance()` — not in `ProjectileEntity.advance()` — because only the system has access to the current RTT estimate and should the entity remain free of back-references to its owning system.

```gdscript
# ProjectileSystem.advance(), after stepping each projectile:
if p.is_predicted:
    var timeout_s: float = 2.0 * (_current_rtt_ms / 1000.0) + 0.1
    if p.time_since_spawn > timeout_s:
        reason = DespawnReason.REJECTED
```

`REJECTED` is a client-only reason and never travels over the wire. `_current_rtt_ms` is set by the client tick loop each frame from `net_client.get_rtt_ms()` (see §9).

### Server-side RTT tracking (option B from brainstorming)

The server maintains a rolling per-player RTT estimate via `SNAPSHOT_ACK` round trips: when the server sends snapshot tick T to a player, it records the send time; when the corresponding `SNAPSHOT_ACK` arrives referencing tick T, the server computes `round_trip = now − send_time` and updates a rolling average over the last ~8 samples. This avoids adding bytes to the input packet and keeps the client from being able to report spoofed latency.

The server exposes `NetServer.get_rtt_ms(player_id) -> int` for `ProjectileSpawnRouter.handle_fire` to read.

---

## 7. Network protocol

### Input packet (unchanged size — 26 bytes)

`dodge_pressed: u8` becomes `action_flags: u8` (bitfield):

```
[msg_type:u8][tick:u32][move_x:f32][move_y:f32]
[aim_x:f32][aim_y:f32][action_flags:u8][input_seq:u32]
```

```gdscript
enum InputActionFlags {
    NONE  = 0,
    DODGE = 1,  # bit 0
    FIRE  = 2,  # bit 1
}
```

Callsites reading `dodge_pressed` migrate to `action_flags & InputActionFlags.DODGE != 0`.

### New binary message types

```gdscript
enum Binary {
    FULL_SNAPSHOT        = 1,
    DELTA_SNAPSHOT       = 2,
    SNAPSHOT_ACK         = 3,
    PLAYER_INPUT         = 4,
    ENEMY_DIED           = 5,
    PROJECTILE_SPAWNED   = 6,  # new
    PROJECTILE_DESPAWNED = 7,  # new
}
```

### `PROJECTILE_SPAWNED` — 26 bytes

```
[msg_type:u8]            1
[projectile_id:u16]      2
[type_id:u8]             1
[owner_player_id:u16]    2
[origin_x:f32]           4
[origin_y:f32]           4
[dir_x:f32]              4
[dir_y:f32]              4
[input_seq:u32]          4   (shooter's input_seq; 0 for non-player-sourced shots)
---------------------------
                        26
```

- `origin` is the server-authoritative projectile position at the moment the packet is queued (i.e. post fast-forward), not the raw rewound origin.
- `input_seq` is how the local shooter matches an adoption to its predicted projectile via `temp_id = -input_seq`. Other clients ignore this field.
- No `spawn_tick` field — the doc's "transit offset" recipe uses each client's own one-way delay, computed from its existing rolling RTT average. Avoids a parallel clock-sync path.

### `PROJECTILE_DESPAWNED` — 12 bytes

```
[msg_type:u8]            1
[projectile_id:u16]      2
[reason:u8]              1   (0=LIFETIME, 1=WALL, 2=ENEMY, 3=PLAYER, 4=SELF)
[x:f32]                  4   (server's despawn position, for view effect placement)
[y:f32]                  4
---------------------------
                        12
```

`reason` drives the view's despawn effect flavor. `x, y` are the server's despawn position — more accurate than the client's local sim position (which may have drifted by a few pixels of RTT jitter) for placing the impact effect.

### `Layout` constants

```gdscript
class Layout:
    # ...existing...
    const PROJECTILE_SPAWNED_SIZE   = 26
    const PROJECTILE_DESPAWNED_SIZE = 12
```

### Not on the wire

- No per-tick projectile state in snapshots. `ENTITY_SIZE` stays 45 bytes, `ENEMY_ENTITY_SIZE` stays 17 bytes.
- No projectile correction/diff packets. v1 trusts deterministic sim.
- No "fire denied" message. Rejection is handled purely by the client's adoption timeout.

---

## 8. View layer

Because every client runs the deterministic projectile sim, `ProjectileView` has **one code path** for both local and remote projectiles: read live position from `ProjectileSystem.projectiles[id].position` each frame, no interpolation buffer, no "local vs remote" branching.

```gdscript
# /view/projectiles/projectile_view.gd
class_name ProjectileView
extends Node2D

@export var projectile_system_path: NodePath
var _projectile_system: ProjectileSystem
var _visuals: Dictionary = {}   # projectile_id -> Node2D

func _ready() -> void:
    _projectile_system = get_node(projectile_system_path)
    EventBus.projectile_spawned.connect(_on_spawned)
    EventBus.projectile_despawned.connect(_on_despawned)

func _process(_delta: float) -> void:
    for id in _visuals.keys():
        var proj: ProjectileEntity = _projectile_system.projectiles.get(id)
        if proj != null:
            _visuals[id].position = proj.position

func _on_spawned(event: Dictionary) -> void:
    var id: int = event["projectile_id"]
    var node := _make_visual(event["type_id"], event["owner_player_id"])
    node.position = event["position"]
    add_child(node)
    _visuals[id] = node

func _on_despawned(event: Dictionary) -> void:
    var id: int = event["projectile_id"]
    if not _visuals.has(id):
        return
    var node: Node2D = _visuals[id]
    _visuals.erase(id)
    _play_despawn_effect(node.position, event["reason"])
    node.queue_free()
```

### Visual style for the TEST projectile

- 6 px bright cyan `Polygon2D` circle (12-vertex approximation, cheap).
- Optional short `Line2D` trail (5 segments, faded) to make direction and speed readable.
- Local shooter's own shots render brighter than remote shots, so playtesting can visually separate who is shooting what.

### Despawn effects

- `WALL` → gray stone spark (8-particle burst)
- `ENEMY` → cyan impact flash (6-particle burst)
- `PLAYER` → red impact flash
- `SELF` → red impact flash, distinct tint from `PLAYER` for debugging
- `LIFETIME` → soft 0.1 s alpha fade, no particles
- `REJECTED` → single-frame desaturation, then free. Should be nearly invisible.

All despawn effects use Godot's built-in `randf()` for jitter. Never `RNG.*` — the CLAUDE.md exception for `/view` applies.

### Input provider change

`InputProvider` gains a `fire_latch: bool` that is set on left-mouse-press and consumed when building the input packet, packed into `action_flags` alongside the existing dodge latch. Same pattern already in use for dodge.

---

## 9. Tick loop integration

### Server tick (pseudocode)

```gdscript
func _physics_process(dt: float) -> void:
    for player in players:
        player_position_history.record(player.player_id, current_tick, player.position)

    for input in drained_inputs:
        var player := players[input.player_id]
        MovementSystem.apply_input(player, input)
        ProjectileSpawnRouter.handle_fire(player, input, projectile_system, {
            "authoritative": true,
            "rtt_ms": net_server.get_rtt_ms(input.player_id),
            "position_history": player_position_history,
            "tick": current_tick,
            "spawn_events": queued_spawn_events,
        })

    MovementSystem.advance(dt)
    EnemySystem.advance(dt)

    projectile_system.tick_cooldowns(dt)
    var despawned := projectile_system.advance(dt, players, enemies)
    for entry in despawned:
        queued_despawn_events.append(entry)

    net_server.broadcast_snapshot_and_events(
        queued_spawn_events, queued_despawn_events)
    queued_spawn_events.clear()
    queued_despawn_events.clear()

    current_tick += 1
```

### Client prediction loop (pseudocode)

```gdscript
func _process(frame_delta: float) -> void:
    var input := input_provider.consume_input()
    PlayerEntity(local_player).apply_input(input)
    PlayerEntity(local_player).advance(frame_delta)

    ProjectileSpawnRouter.handle_fire(local_player, input, projectile_system, {
        "authoritative": false,
    })
    projectile_system.tick_cooldowns(frame_delta)
    projectile_system._current_rtt_ms = net_client.get_rtt_ms()
    var despawned := projectile_system.advance(frame_delta, [], [])
    for entry in despawned:
        EventBus.projectile_despawned.emit({
            "projectile_id": entry["id"],
            "reason": entry["reason"],
            "position": entry["position"],
        })

    if input.has_pending():
        net_client.send_input(input)
```

### Client network message handlers

- On `PROJECTILE_SPAWNED`: `projectile_system.adopt_authoritative(...)`, then emit `projectile_spawned`.
- On `PROJECTILE_DESPAWNED`: `projectile_system.on_despawn_event(...)`, which emits `projectile_despawned` internally.

---

## 10. Testing strategy

### Unit tests (GUT)

| File | Coverage |
|---|---|
| `test_collision_math.gd` | `circle_aabb_overlap` at corners, edges, interior, far; `circle_circle_overlap` at exact-touching, overlap, separation. |
| `test_wall_geometry.gd` | `extract_aabbs` on the real `arena.tscn` returns exactly 4 rects at expected coords. Asserts on non-rect shapes. |
| `test_projectile_entity_motion.gd` | `advance()` straight-line motion is dt-independent (100 × 0.01 s ≈ 1 × 1.0 s). Canary regression guard. |
| `test_projectile_entity_collision.gd` | Wall collision at expected distance; self-grace excludes owner during grace and includes after; walls-before-enemies order; lifetime despawn at exactly `params.lifetime`. |
| `test_projectile_system_spawn.gd` | `spawn_predicted` uses `-input_seq` temp id; `spawn_authoritative` assigns monotonic positive id; `adopt_authoritative` rekeys dict entry without losing state. |
| `test_projectile_system_advance.gd` | `advance(dt, players, enemies)` returns correct despawn list; removes entries from dict; cooldowns decrement. |
| `test_projectile_system_reject.gd` | Predicted projectile with no adoption times out at `2*rtt + 0.1 s` and emits `REJECTED`. |
| `test_projectile_system_reconcile.gd` | `start_reconcile()` sets target; `advance()` lerps over `RECONCILE_DURATION` and converges exactly. |
| `test_player_position_history.gd` | Record N samples, lookup returns correct position for any recorded tick; `drop_player` removes all samples; ring buffer prunes old entries. |
| `test_projectile_network_encoding.gd` | `PROJECTILE_SPAWNED` and `PROJECTILE_DESPAWNED` encode/decode round-trip preserves all fields; input packet with FIRE bit encodes/decodes correctly; layout byte counts match `Layout.*_SIZE`. |

### Determinism canary

```gdscript
func test_projectile_determinism_across_dt_chunks():
    var a := _make_projectile(Vector2.ZERO, Vector2.RIGHT)
    var b := _make_projectile(Vector2.ZERO, Vector2.RIGHT)

    for _i in 60:
        a.advance(1.0 / 60.0, [], [], [])
    for _i in 30:
        b.advance(1.0 / 30.0, [], [], [])

    assert_true(a.position.distance_to(b.position) < 0.01,
        "server tick and client frame must converge for same spawn event")
```

### Integration tests

| Test | Setup | Assertion |
|---|---|---|
| `test_fire_round_trip.gd` | Headless server + 1 client, client sends fire input. | Client's `ProjectileSystem.projectiles` ends up with the adopted authoritative projectile; owner matches local player. |
| `test_fire_server_rejection.gd` | Client sends two fires within cooldown. | Server broadcasts one spawn only; second predicted times out to `REJECTED`. |
| `test_projectile_wall_collision.gd` | Fire at a wall. | Server broadcasts `PROJECTILE_DESPAWNED` with `reason = WALL`; client's projectile is gone. |
| `test_projectile_enemy_collision.gd` | Spawn enemy, fire at it. | Despawn event with `reason = ENEMY`; enemy stays alive (no damage in v1). |
| `test_projectile_self_collision.gd` | Fire, advance past `spawn_grace`, walk shooter into projectile path. | Despawn event with `reason = SELF`; shooter stays alive. |
| `test_server_rewind_shooter_origin.gd` | Shooter at `S0`, advance one tick to `S1`, fire input arrives with synthetic 100 ms RTT. | Spawn event `origin` is closer to `S0 + aim*(offset + speed*0.05)` than to `S1 + aim*(offset + speed*0.05)`. Validates the history lookup actually rewound. |
| `test_two_clients_agree.gd` | 2 headless clients + 1 server. Shooter fires. | Both clients' `ProjectileSystem.projectiles[id].position` converge within 1 px after N ticks of deterministic sim. |

### Manual visual smoke test

Run two browser clients against a headless server:

1. Instant feel on local shooter's click — no input lag.
2. Remote projectiles trail slightly behind a moving remote shooter, which is physically correct (see §6 math).
3. Self-collision works: fire, move into own shot, watch it destroy.
4. Walls destroy projectiles at the wall edge.
5. No projectile escapes the arena, ever.
6. Two clients firing simultaneously: no id collisions, no ghosts, both see each other's shots correctly.

---

## 11. Scope boundaries (recap)

**In Phase 4:**
- Single placeholder `TEST` projectile type
- Straight-line motion, pure `Vector2` math
- Collision with walls, enemies, other players, self (after grace)
- Destroy projectile on collision (no damage, no victim state change)
- Server-side shooter position rewind for clean spawn origin
- Deterministic client sim from spawn events
- Local shooter prediction + adoption via `input_seq`
- 0.1 s reconcile lerp; hard snap on drift > 200 px
- Rejection timeout for orphan predicted projectiles
- 30 Hz tick rate bump
- Full unit + integration + determinism canary test suite

**Not in Phase 4:**
- Damage, health, death events for hit targets
- Knockback / impact force (param field reserved but unused)
- Phase 6 lag-compensated hit detection against moving targets
- Projectile-vs-projectile collision
- Multiple projectile types
- Spatial grid acceleration for projectile collision
- Friendly-fire toggle
- Tunneling fix for `speed > radius / dt` projectiles
- View trail polish beyond the basic Line2D afterimage
