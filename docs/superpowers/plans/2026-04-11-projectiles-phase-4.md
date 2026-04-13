# Projectiles Phase 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship deterministic client-side projectile simulation with spawn/despawn network protocol, server-side shooter position rewind, and collision against walls/enemies/players/self (no damage yet — destroy on collision only).

**Architecture:** Pure `Vector2` math projectiles, spawned once via authoritative server event, simulated deterministically on every client thereafter. Local shooter predicts its own projectile from click and reconciles via `input_seq` match. Server rewinds shooter position to fire time using a per-player position history ring buffer. Collision against walls is client+server; collision against enemies/players is server-authoritative. Bump server tick rate 20 → 30 Hz. See `docs/superpowers/specs/2026-04-11-projectiles-phase-4-design.md` for full design rationale.

**Tech Stack:** Godot 4 + GDScript, WebSocketMultiplayerPeer, GUT test framework, binary network protocol via `PackedByteArray`.

---

## Reference commands

Use these throughout the plan. All commands run from the repository root.

**Rebuild Godot class cache** (required after creating any new file with `class_name`):
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

**Run a single test file:**
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/<subdir>/<test_file>.gd -gexit
```

**Run all tests:**
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

---

## File map

**New files:**
- `godot/shared/projectiles/collision_math.gd` — circle-AABB and circle-circle overlap
- `godot/shared/projectiles/wall_geometry.gd` — extract Array[Rect2] from arena.tscn
- `godot/shared/projectiles/projectile_params.gd` — Resource with speed/radius/lifetime/etc.
- `godot/shared/projectiles/projectile_types.gd` — type enum + params lookup
- `godot/shared/projectiles/test_projectile.tres` — v1 test projectile params instance
- `godot/simulation/entities/projectile_entity.gd` — pure data RefCounted
- `godot/simulation/systems/projectile_system.gd` — dict owner + advance + cooldowns
- `godot/simulation/systems/projectile_spawn_router.gd` — shared fire-input dispatcher
- `godot/simulation/systems/player_position_history.gd` — per-player ring buffer (server)
- `godot/view/projectiles/projectile_view.gd` — listens to EventBus, renders live position
- `godot/tests/systems/test_collision_math.gd`
- `godot/tests/systems/test_wall_geometry.gd`
- `godot/tests/entities/test_projectile_entity_motion.gd`
- `godot/tests/entities/test_projectile_entity_collision.gd`
- `godot/tests/systems/test_projectile_system_spawn.gd`
- `godot/tests/systems/test_projectile_system_advance.gd`
- `godot/tests/systems/test_projectile_system_reconcile.gd`
- `godot/tests/systems/test_projectile_system_reject.gd`
- `godot/tests/systems/test_projectile_system_cooldown.gd`
- `godot/tests/systems/test_player_position_history.gd`
- `godot/tests/network/test_projectile_network.gd`
- `godot/tests/network/test_fire_round_trip.gd`
- `godot/tests/network/test_projectile_collision_integration.gd`
- `godot/tests/network/test_projectile_determinism.gd`

**Modified files:**
- `godot/shared/network/message_types.gd` — `TICK_RATE` 20→30, new Binary enum values, `InputActionFlags` bitfield, new Layout constants
- `godot/simulation/event_bus.gd` — add `projectile_spawned`, `projectile_despawned` signals
- `godot/simulation/entities/player_entity.gd` — add `get_collision_radius()`
- `godot/simulation/entities/enemy_entity.gd` — add `get_collision_radius()`
- `godot/simulation/input/keyboard_mouse_input_provider.gd` — add `fire_latch`, pack into `action_flags`
- `godot/simulation/network/net_server.gd` — per-player RTT tracking, spawn/despawn broadcast, server tick loop hooks
- `godot/simulation/network/net_client.gd` — spawn/despawn handlers, client tick loop hooks, RTT setter on ProjectileSystem
- `godot/simulation/systems/movement_system.gd` — call `ProjectileSpawnRouter.handle_fire()` for each input
- (various tests) — existing dodge/input packet tests updated for `action_flags`

---

## Test file conventions

Every test file follows the GUT pattern already used in the repo:

```gdscript
extends GutTest

var Thing = preload("res://path/to/thing.gd")

func test_some_behavior():
    var x = Thing.new()
    assert_eq(x.foo(), 42)
```

Use `assert_eq`, `assert_true`, `assert_false`, `assert_almost_eq`, `assert_null`, `assert_not_null` from GUT. No `@test` decorators.

---

## Task 1: Bump server tick rate 20 → 30 Hz

**Files:**
- Modify: `godot/shared/network/message_types.gd`

- [ ] **Step 1: Change the TICK_RATE constant**

In `godot/shared/network/message_types.gd`, change:

```gdscript
const TICK_RATE = 20
const TICK_INTERVAL_MS: float = 1000.0 / TICK_RATE
```

to:

```gdscript
const TICK_RATE = 30
const TICK_INTERVAL_MS: float = 1000.0 / TICK_RATE
```

`ACK_TIMEOUT_TICKS` is computed from `ACK_TIMEOUT_SECONDS` and auto-scales — no change needed.

- [ ] **Step 2: Run existing tests to see what breaks**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Any test that asserted a tick-count-based timing will now fail. Expected culprits: reconciliation timing tests, zombie timeout test (if it uses tick counts instead of seconds), movement-system tests using `TICK_INTERVAL_MS`.

- [ ] **Step 3: Update broken tests**

For each failing test, adjust expected tick counts to match the new rate. Timings expressed in seconds should already work. Commit the individual test fixes as small edits in this same task.

- [ ] **Step 4: Run all tests green**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: all existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add godot/shared/network/message_types.gd godot/tests
git commit -m "Bump server tick rate 20 Hz → 30 Hz"
```

---

## Task 2: Input packet — replace `dodge_pressed` with `action_flags` bitfield

**Files:**
- Modify: `godot/shared/network/message_types.gd`
- Modify: `godot/simulation/network/net_client.gd` (input encode)
- Modify: `godot/simulation/network/net_server.gd` (input decode)
- Modify: `godot/simulation/input/keyboard_mouse_input_provider.gd`
- Modify: `godot/simulation/entities/player_entity.gd` (reads the flag)
- Modify: `godot/tests/network/test_net_message.gd` (or wherever input packet tests live)

- [ ] **Step 1: Add `InputActionFlags` enum to `message_types.gd`**

Add near the other enums:

```gdscript
enum InputActionFlags {
    NONE  = 0,
    DODGE = 1,  # bit 0
    FIRE  = 2,  # bit 1
}
```

The `INPUT_SIZE` constant stays at 26 bytes — we're replacing one u8 with another u8.

- [ ] **Step 2: Write a failing test for encoding FIRE bit**

Add to `godot/tests/network/test_net_message.gd` (or create `test_input_action_flags.gd` if the existing file is overcrowded):

```gdscript
func test_input_packet_encodes_fire_flag():
    var input = {
        "tick": 100,
        "move_direction": Vector2(0, 1),
        "aim_direction": Vector2(1, 0),
        "action_flags": MessageTypes.InputActionFlags.FIRE,
        "input_seq": 42,
    }
    var bytes = NetClient.encode_input(input)
    var decoded = NetServer.decode_input(bytes)
    assert_eq(decoded["action_flags"] & MessageTypes.InputActionFlags.FIRE,
        MessageTypes.InputActionFlags.FIRE)
    assert_eq(decoded["action_flags"] & MessageTypes.InputActionFlags.DODGE, 0)

func test_input_packet_encodes_dodge_and_fire_together():
    var input = {
        "tick": 100,
        "move_direction": Vector2(0, 1),
        "aim_direction": Vector2(1, 0),
        "action_flags": MessageTypes.InputActionFlags.DODGE | MessageTypes.InputActionFlags.FIRE,
        "input_seq": 42,
    }
    var bytes = NetClient.encode_input(input)
    var decoded = NetServer.decode_input(bytes)
    assert_eq(decoded["action_flags"],
        MessageTypes.InputActionFlags.DODGE | MessageTypes.InputActionFlags.FIRE)
```

- [ ] **Step 3: Run to verify it fails**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_net_message.gd -gexit
```

Expected: failure because `encode_input`/`decode_input` still use `dodge_pressed` key.

- [ ] **Step 4: Update `NetClient.encode_input` and `NetServer.decode_input`**

In both, replace the `dodge_pressed: u8` byte with `action_flags: u8`. The byte position is the same (right after `aim_y`, before `input_seq`). Read from/write to the `action_flags` key in the dict. Drop all reads of `dodge_pressed` from `NetClient`.

- [ ] **Step 5: Update `PlayerEntity.apply_input`**

Change:

```gdscript
if input.get("dodge_pressed", false) and can_dodge():
    start_dodge()
```

to:

```gdscript
var flags: int = input.get("action_flags", 0)
if (flags & MessageTypes.InputActionFlags.DODGE) != 0 and can_dodge():
    start_dodge()
```

- [ ] **Step 6: Update `KeyboardMouseInputProvider`**

Replace the dodge-only output with a flag-packed output:

```gdscript
func consume_input() -> Dictionary:
    var flags: int = 0
    if _dodge_latch:
        flags |= MessageTypes.InputActionFlags.DODGE
    if _fire_latch:
        flags |= MessageTypes.InputActionFlags.FIRE
    _dodge_latch = false
    _fire_latch = false
    return {
        "move_direction": _current_move,
        "aim_direction": _current_aim,
        "action_flags": flags,
    }
```

Add `var _fire_latch: bool = false` as a new field. The actual input detection on left mouse click is wired up in Task 22 — for this task, just declare the field and have `consume_input` pack it into `action_flags`.

- [ ] **Step 7: Run all tests green**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: all tests pass. The new FIRE test passes because flag round-trip works. Existing DODGE tests still pass because the DODGE bit has the same effect via `action_flags & DODGE`.

- [ ] **Step 8: Commit**

```bash
git add godot/shared/network/message_types.gd godot/simulation/network/net_client.gd godot/simulation/network/net_server.gd godot/simulation/entities/player_entity.gd godot/simulation/input/keyboard_mouse_input_provider.gd godot/tests/network/test_net_message.gd
git commit -m "Input packet: replace dodge_pressed u8 with action_flags bitfield"
```

---

## Task 3: `CollisionMath` primitives

**Files:**
- Create: `godot/shared/projectiles/collision_math.gd`
- Create: `godot/tests/systems/test_collision_math.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/systems/test_collision_math.gd`:

```gdscript
extends GutTest

var CollisionMath = preload("res://shared/projectiles/collision_math.gd")

func test_circle_aabb_overlap_inside():
    var rect = Rect2(Vector2(0, 0), Vector2(100, 100))
    assert_true(CollisionMath.circle_aabb_overlap(Vector2(50, 50), 10.0, rect))

func test_circle_aabb_overlap_touching_edge():
    var rect = Rect2(Vector2(0, 0), Vector2(100, 100))
    assert_true(CollisionMath.circle_aabb_overlap(Vector2(105, 50), 6.0, rect))
    assert_false(CollisionMath.circle_aabb_overlap(Vector2(110, 50), 6.0, rect))

func test_circle_aabb_overlap_corner():
    var rect = Rect2(Vector2(0, 0), Vector2(100, 100))
    # Circle at (103, 103), radius 5 → closest point (100,100), distance ≈ 4.24
    assert_true(CollisionMath.circle_aabb_overlap(Vector2(103, 103), 5.0, rect))
    # Circle at (108, 108), radius 5 → distance ≈ 11.3
    assert_false(CollisionMath.circle_aabb_overlap(Vector2(108, 108), 5.0, rect))

func test_circle_aabb_overlap_far():
    var rect = Rect2(Vector2(0, 0), Vector2(100, 100))
    assert_false(CollisionMath.circle_aabb_overlap(Vector2(500, 500), 50.0, rect))

func test_circle_circle_overlap_touching():
    # Centers 10 apart, radii 5 and 5 → sum is 10, not strictly less, so NO overlap
    assert_false(CollisionMath.circle_circle_overlap(
        Vector2(0, 0), 5.0, Vector2(10, 0), 5.0))
    # Sum 10.1, strictly greater → overlap
    assert_true(CollisionMath.circle_circle_overlap(
        Vector2(0, 0), 5.05, Vector2(10, 0), 5.05))

func test_circle_circle_overlap_distant():
    assert_false(CollisionMath.circle_circle_overlap(
        Vector2(0, 0), 5.0, Vector2(100, 0), 5.0))
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_collision_math.gd -gexit
```

Expected: file not found error for the preload, test suite aborts.

- [ ] **Step 3: Create `CollisionMath` class**

Create `godot/shared/projectiles/collision_math.gd`:

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

- [ ] **Step 4: Rebuild class cache**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 5: Run tests green**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_collision_math.gd -gexit
```

Expected: 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add godot/shared/projectiles/collision_math.gd godot/tests/systems/test_collision_math.gd
git commit -m "Add CollisionMath circle-AABB and circle-circle overlap primitives"
```

---

## Task 4: `WallGeometry` — extract AABBs from arena scene

**Files:**
- Create: `godot/shared/projectiles/wall_geometry.gd`
- Create: `godot/tests/systems/test_wall_geometry.gd`

- [ ] **Step 1: Write failing test**

Create `godot/tests/systems/test_wall_geometry.gd`:

```gdscript
extends GutTest

var WallGeometry = preload("res://shared/projectiles/wall_geometry.gd")
var ArenaScene = preload("res://shared/world/arena.tscn")

func test_extract_returns_four_walls():
    var arena = ArenaScene.instantiate()
    add_child_autofree(arena)
    var aabbs = WallGeometry.extract_aabbs(arena)
    assert_eq(aabbs.size(), 4, "arena has exactly 4 walls")

func test_extract_wall_positions_match_arena():
    var arena = ArenaScene.instantiate()
    add_child_autofree(arena)
    var aabbs: Array = WallGeometry.extract_aabbs(arena)

    # The arena walls, per shared/world/arena.tscn:
    #   Top:    center (1200, -4),  size (2400, 8)
    #   Bottom: center (1200, 1604),size (2400, 8)
    #   Left:   center (-4,   800), size (8, 1600)
    #   Right:  center (2404, 800), size (8, 1600)
    var centers: Array[Vector2] = []
    for rect: Rect2 in aabbs:
        centers.append(rect.get_center())
    assert_true(centers.has(Vector2(1200, -4)))
    assert_true(centers.has(Vector2(1200, 1604)))
    assert_true(centers.has(Vector2(-4, 800)))
    assert_true(centers.has(Vector2(2404, 800)))
```

- [ ] **Step 2: Run to verify failure**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_wall_geometry.gd -gexit
```

Expected: preload fails.

- [ ] **Step 3: Create `WallGeometry`**

Create `godot/shared/projectiles/wall_geometry.gd`:

```gdscript
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

- [ ] **Step 4: Rebuild class cache**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 5: Run tests green**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_wall_geometry.gd -gexit
```

Expected: 2 tests pass.

- [ ] **Step 6: Commit**

```bash
git add godot/shared/projectiles/wall_geometry.gd godot/tests/systems/test_wall_geometry.gd
git commit -m "Add WallGeometry.extract_aabbs for deterministic wall collision"
```

---

## Task 5: `ProjectileParams` resource and `ProjectileType` lookup

**Files:**
- Create: `godot/shared/projectiles/projectile_params.gd`
- Create: `godot/shared/projectiles/projectile_types.gd`
- Create: `godot/shared/projectiles/test_projectile.tres`

No test file for this task — resources are data and will be exercised by downstream tests.

- [ ] **Step 1: Create `ProjectileParams`**

Create `godot/shared/projectiles/projectile_params.gd`:

```gdscript
class_name ProjectileParams
extends Resource

@export var speed: float = 600.0
@export var lifetime: float = 1.5
@export var radius: float = 6.0
@export var spawn_offset: float = 40.0
@export var spawn_grace: float = 0.10
@export var fire_cooldown: float = 0.20
@export var impact_force: float = 0.0
```

- [ ] **Step 2: Create `ProjectileType`**

Create `godot/shared/projectiles/projectile_types.gd`:

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

- [ ] **Step 3: Create `test_projectile.tres` resource**

Create `godot/shared/projectiles/test_projectile.tres` by hand:

```
[gd_resource type="Resource" script_class="ProjectileParams" load_steps=2 format=3]

[ext_resource type="Script" path="res://shared/projectiles/projectile_params.gd" id="1_params"]

[resource]
script = ExtResource("1_params")
speed = 600.0
lifetime = 1.5
radius = 6.0
spawn_offset = 40.0
spawn_grace = 0.10
fire_cooldown = 0.20
impact_force = 0.0
```

- [ ] **Step 4: Rebuild class cache**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

Watch for any import errors on the `.tres` file. If the class cache needed the `.gd` files first, the first import pass may error on the `.tres` — run import once more and it should resolve.

- [ ] **Step 5: Sanity check**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

All existing tests still pass (no regression).

- [ ] **Step 6: Commit**

```bash
git add godot/shared/projectiles/projectile_params.gd godot/shared/projectiles/projectile_types.gd godot/shared/projectiles/test_projectile.tres
git commit -m "Add ProjectileParams resource and ProjectileType lookup"
```

---

## Task 6: Collision radius getters on `PlayerEntity` and `EnemyEntity`

**Files:**
- Modify: `godot/simulation/entities/player_entity.gd`
- Modify: `godot/simulation/entities/enemy_entity.gd`
- Create: `godot/tests/entities/test_entity_collision_radius.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/entities/test_entity_collision_radius.gd`:

```gdscript
extends GutTest

var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")

func test_player_collision_radius_positive():
    var p = PlayerEntityScene.instantiate()
    add_child_autofree(p)
    assert_gt(p.get_collision_radius(), 0.0)
    assert_lt(p.get_collision_radius(), 100.0)

func test_enemy_collision_radius_positive():
    var e = EnemyEntityScene.instantiate()
    add_child_autofree(e)
    assert_gt(e.get_collision_radius(), 0.0)
    assert_lt(e.get_collision_radius(), 100.0)

func test_player_collision_radius_cached():
    var p = PlayerEntityScene.instantiate()
    add_child_autofree(p)
    var r1 = p.get_collision_radius()
    var r2 = p.get_collision_radius()
    assert_eq(r1, r2)
```

- [ ] **Step 2: Run to verify failure**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_entity_collision_radius.gd -gexit
```

Expected: failure, `get_collision_radius` doesn't exist.

- [ ] **Step 3: Add getter to `PlayerEntity`**

In `godot/simulation/entities/player_entity.gd`, add these fields near the top (next to other `var` declarations):

```gdscript
var _cached_collision_radius: float = -1.0
```

And this method anywhere in the file:

```gdscript
func get_collision_radius() -> float:
    if _cached_collision_radius < 0.0:
        var shape_node := $CollisionShape2D as CollisionShape2D
        var shape := shape_node.shape
        if shape is CircleShape2D:
            _cached_collision_radius = (shape as CircleShape2D).radius
        elif shape is RectangleShape2D:
            var s := (shape as RectangleShape2D).size
            _cached_collision_radius = max(s.x, s.y) / 2.0
        else:
            push_warning("PlayerEntity: unknown collision shape, defaulting to 16 px")
            _cached_collision_radius = 16.0
    return _cached_collision_radius
```

- [ ] **Step 4: Add the same getter to `EnemyEntity`**

Copy the same pattern into `godot/simulation/entities/enemy_entity.gd`. The field name and method body are identical.

- [ ] **Step 5: Run tests green**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_entity_collision_radius.gd -gexit
```

Expected: 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add godot/simulation/entities/player_entity.gd godot/simulation/entities/enemy_entity.gd godot/tests/entities/test_entity_collision_radius.gd
git commit -m "Add get_collision_radius() getters on player and enemy entities"
```

---

## Task 7: EventBus projectile signals

**Files:**
- Modify: `godot/simulation/event_bus.gd`

- [ ] **Step 1: Add the signals**

In `godot/simulation/event_bus.gd`, add near the Combat section:

```gdscript
# Projectiles
signal projectile_spawned(event: Dictionary)
signal projectile_despawned(event: Dictionary)
```

- [ ] **Step 2: Sanity check**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: all existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add godot/simulation/event_bus.gd
git commit -m "Add projectile_spawned and projectile_despawned EventBus signals"
```

---

## Task 8: `ProjectileSystem` skeleton + `DespawnReason` enum

Create the system shell with enum and empty fields, before any entity references it. Later tasks fill in spawn/advance methods.

**Files:**
- Create: `godot/simulation/systems/projectile_system.gd`

- [ ] **Step 1: Create the skeleton**

Create `godot/simulation/systems/projectile_system.gd`:

```gdscript
class_name ProjectileSystem
extends Node

const MAX_ACTIVE = 1024

enum DespawnReason {
    ALIVE    = -1,
    LIFETIME = 0,
    WALL     = 1,
    ENEMY    = 2,
    PLAYER   = 3,
    SELF     = 4,
    REJECTED = 5,  # client-only, never broadcast
}

var projectiles: Dictionary = {}        # projectile_id -> ProjectileEntity
var _next_server_id: int = 1
var _walls: Array = []
var _fire_cooldown: Dictionary = {}      # player_id -> seconds remaining
var _current_rtt_ms: int = 0             # local client's RTT estimate (used for rejection timeout)

func set_walls(aabbs: Array) -> void:
    _walls = aabbs

func get_walls() -> Array:
    return _walls
```

Subsequent tasks add methods inside this class.

- [ ] **Step 2: Rebuild class cache**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 3: Sanity check**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

All existing tests still pass.

- [ ] **Step 4: Commit**

```bash
git add godot/simulation/systems/projectile_system.gd
git commit -m "Add ProjectileSystem skeleton with DespawnReason enum"
```

---

## Task 9: `ProjectileEntity` class + motion + timers + wall collision + reconcile + dt-independence canary

**Files:**
- Create: `godot/simulation/entities/projectile_entity.gd`
- Create: `godot/tests/entities/test_projectile_entity_motion.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/entities/test_projectile_entity_motion.gd`:

```gdscript
extends GutTest

var ProjectileEntity = preload("res://simulation/entities/projectile_entity.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")
var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")

func _make(origin: Vector2 = Vector2.ZERO,
           dir: Vector2 = Vector2.RIGHT) -> ProjectileEntity:
    var p = ProjectileEntity.new()
    var params = ProjectileType.get_params(ProjectileType.Id.TEST)
    p.initialize(1, ProjectileType.Id.TEST, 42, origin, dir, params)
    return p

func test_advance_moves_projectile_along_direction():
    var p = _make(Vector2(100, 100), Vector2.RIGHT)
    var reason = p.advance(0.5, [], [], [])   # walls empty, no collision
    assert_eq(reason, ProjectileSystemCls.DespawnReason.ALIVE)
    assert_almost_eq(p.position.x, 100.0 + 600.0 * 0.5, 0.01)
    assert_almost_eq(p.position.y, 100.0, 0.01)

func test_advance_lifetime_despawn():
    var p = _make()
    p.advance(2.0, [], [], [])   # past the 1.5 s lifetime
    assert_true(p.time_remaining <= 0.0)

func test_advance_returns_lifetime_reason():
    var p = _make()
    var reason = p.advance(2.0, [], [], [])
    assert_eq(reason, ProjectileSystemCls.DespawnReason.LIFETIME)

func test_advance_wall_collision_returns_wall_reason():
    var p = _make(Vector2(100, 800), Vector2.LEFT)  # flying toward left wall at x=-8..0
    var walls: Array = [Rect2(Vector2(-8, 0), Vector2(8, 1600))]
    var reason: int = ProjectileSystemCls.DespawnReason.ALIVE
    for i in 30:
        reason = p.advance(0.033, walls, [], [])
        if reason != ProjectileSystemCls.DespawnReason.ALIVE:
            break
    assert_eq(reason, ProjectileSystemCls.DespawnReason.WALL)

func test_dt_independence_canary_straight_line():
    var a = _make()
    var b = _make()
    for _i in 60:
        a.advance(1.0 / 60.0, [], [], [])
    for _i in 30:
        b.advance(1.0 / 30.0, [], [], [])
    assert_true(a.position.distance_to(b.position) < 0.01,
        "server tick and client frame must converge for same straight-line path")

func test_start_reconcile_sets_target_delta():
    var p = _make(Vector2(0, 0), Vector2.RIGHT)
    p.start_reconcile(Vector2(20, 0))  # target 20 px to the right of current
    assert_almost_eq(p._reconcile_delta.x, 20.0, 0.01)
    assert_almost_eq(p._reconcile_remaining, 0.1, 0.01)

func test_reconcile_lerp_converges_over_duration():
    var p = _make(Vector2(0, 0), Vector2.RIGHT)
    # Disable motion contribution for the test by setting direction to zero
    p.direction = Vector2.ZERO
    p.start_reconcile(Vector2(20, 0))
    var total_dt = 0.0
    while p._reconcile_remaining > 0.0 and total_dt < 1.0:
        p.advance(1.0 / 60.0, [], [], [])
        total_dt += 1.0 / 60.0
    assert_almost_eq(p.position.x, 20.0, 0.5)
```

- [ ] **Step 2: Run to verify failure**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_projectile_entity_motion.gd -gexit
```

Expected: preload fails.

- [ ] **Step 3: Create `ProjectileEntity`**

Create `godot/simulation/entities/projectile_entity.gd`:

```gdscript
class_name ProjectileEntity
extends RefCounted

const _Sys = preload("res://simulation/systems/projectile_system.gd")
const RECONCILE_DURATION: float = 0.1

# Identity
var projectile_id: int = -1
var type_id: int = 0
var owner_player_id: int = -1

# State
var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.RIGHT
var time_remaining: float = 0.0
var spawn_grace_remaining: float = 0.0
var time_since_spawn: float = 0.0
var params: ProjectileParams = null

# Reconciliation bookkeeping (client only)
var is_predicted: bool = false
var spawn_input_seq: int = -1
var _reconcile_delta: Vector2 = Vector2.ZERO
var _reconcile_remaining: float = 0.0


func initialize(
        id: int, type: int, owner: int,
        origin: Vector2, dir: Vector2,
        p: ProjectileParams) -> void:
    projectile_id = id
    type_id = type
    owner_player_id = owner
    position = origin
    direction = dir.normalized() if dir.length_squared() > 0.0 else Vector2.ZERO
    params = p
    time_remaining = p.lifetime
    spawn_grace_remaining = p.spawn_grace
    time_since_spawn = 0.0


func start_reconcile(target: Vector2) -> void:
    _reconcile_delta = target - position
    _reconcile_remaining = RECONCILE_DURATION


func advance(dt: float, walls: Array, players: Array, enemies: Array) -> int:
    # 1. Motion
    position += direction * params.speed * dt

    # 2. Timers
    time_remaining -= dt
    spawn_grace_remaining -= dt
    time_since_spawn += dt

    # 3. Reconcile lerp
    if _reconcile_remaining > 0.0:
        var chunk := min(dt, _reconcile_remaining)
        position += _reconcile_delta * (chunk / RECONCILE_DURATION)
        _reconcile_remaining -= chunk

    # 4. Lifetime
    if time_remaining <= 0.0:
        return _Sys.DespawnReason.LIFETIME

    # 5. Walls
    for wall in walls:
        if CollisionMath.circle_aabb_overlap(position, params.radius, wall):
            return _Sys.DespawnReason.WALL

    # 6. Enemies (filled in next task)
    # 7. Players (filled in next task)

    return _Sys.DespawnReason.ALIVE
```

- [ ] **Step 4: Rebuild class cache**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 5: Run tests green**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_projectile_entity_motion.gd -gexit
```

Expected: 7 tests pass.

- [ ] **Step 6: Commit**

```bash
git add godot/simulation/entities/projectile_entity.gd godot/tests/entities/test_projectile_entity_motion.gd
git commit -m "Add ProjectileEntity with motion, lifetime, wall collision, reconcile lerp"
```

---

## Task 10: `ProjectileEntity.advance()` — enemy, player, and self-grace collision

**Files:**
- Modify: `godot/simulation/entities/projectile_entity.gd`
- Create: `godot/tests/entities/test_projectile_entity_collision.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/entities/test_projectile_entity_collision.gd`:

```gdscript
extends GutTest

var ProjectileEntity = preload("res://simulation/entities/projectile_entity.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")
var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")

func _make_projectile(origin: Vector2, dir: Vector2, owner_id: int) -> ProjectileEntity:
    var p = ProjectileEntity.new()
    var params = ProjectileType.get_params(ProjectileType.Id.TEST)
    p.initialize(1, ProjectileType.Id.TEST, owner_id, origin, dir, params)
    return p

func test_projectile_hits_enemy_returns_enemy_reason():
    var proj = _make_projectile(Vector2(100, 100), Vector2.RIGHT, 42)
    var enemy = EnemyEntityScene.instantiate()
    add_child_autofree(enemy)
    enemy.position = Vector2(120, 100)   # 20 px ahead, definitely in hit range
    enemy.state = 1   # IDLE, not DEAD
    var reason = proj.advance(0.05, [], [], [enemy])
    assert_eq(reason, ProjectileSystemCls.DespawnReason.ENEMY)

func test_projectile_skips_dead_enemies():
    var proj = _make_projectile(Vector2(100, 100), Vector2.RIGHT, 42)
    var enemy = EnemyEntityScene.instantiate()
    add_child_autofree(enemy)
    enemy.position = Vector2(120, 100)
    enemy.state = 3   # DEAD
    var reason = proj.advance(0.05, [], [], [enemy])
    assert_eq(reason, ProjectileSystemCls.DespawnReason.ALIVE)

func test_projectile_hits_non_owner_player_returns_player_reason():
    var proj = _make_projectile(Vector2(100, 100), Vector2.RIGHT, 42)
    var other = PlayerEntityScene.instantiate()
    add_child_autofree(other)
    other.player_id = 99
    other.position = Vector2(120, 100)
    var reason = proj.advance(0.05, [], [other], [])
    assert_eq(reason, ProjectileSystemCls.DespawnReason.PLAYER)

func test_owner_immune_during_spawn_grace():
    var proj = _make_projectile(Vector2(100, 100), Vector2.ZERO, 42)
    proj.direction = Vector2.ZERO   # don't move
    var owner = PlayerEntityScene.instantiate()
    add_child_autofree(owner)
    owner.player_id = 42
    owner.position = Vector2(100, 100)   # same spot
    # spawn_grace is 0.10, so at dt=0.05 the grace is still active
    var reason = proj.advance(0.05, [], [owner], [])
    assert_eq(reason, ProjectileSystemCls.DespawnReason.ALIVE)

func test_owner_hit_after_grace_expires():
    var proj = _make_projectile(Vector2(100, 100), Vector2.ZERO, 42)
    proj.direction = Vector2.ZERO
    # Burn off the spawn grace first
    proj.spawn_grace_remaining = 0.0
    var owner = PlayerEntityScene.instantiate()
    add_child_autofree(owner)
    owner.player_id = 42
    owner.position = Vector2(100, 100)
    var reason = proj.advance(0.05, [], [owner], [])
    assert_eq(reason, ProjectileSystemCls.DespawnReason.SELF)

func test_collision_order_walls_before_enemies():
    # Wall and enemy both in range — walls win
    var proj = _make_projectile(Vector2(10, 10), Vector2.ZERO, 42)
    proj.direction = Vector2.ZERO
    var walls: Array = [Rect2(Vector2(0, 0), Vector2(20, 20))]
    var enemy = EnemyEntityScene.instantiate()
    add_child_autofree(enemy)
    enemy.position = Vector2(10, 10)
    enemy.state = 1
    var reason = proj.advance(0.01, walls, [], [enemy])
    assert_eq(reason, ProjectileSystemCls.DespawnReason.WALL)
```

- [ ] **Step 2: Run to verify failure**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_projectile_entity_collision.gd -gexit
```

Expected: tests fail — enemy/player branches not yet implemented.

- [ ] **Step 3: Fill in the enemy and player branches**

In `godot/simulation/entities/projectile_entity.gd`, replace the placeholder comments:

```gdscript
    # 6. Enemies (filled in next task)
    # 7. Players (filled in next task)
```

with:

```gdscript
    # 6. Enemies (server-only — client passes empty)
    for enemy in enemies:
        if enemy.state == EnemyEntity.State.DEAD:
            continue
        if CollisionMath.circle_circle_overlap(
                position, params.radius, enemy.position, enemy.get_collision_radius()):
            return _Sys.DespawnReason.ENEMY

    # 7. Players (owner excluded during spawn grace)
    for player in players:
        var is_owner: bool = (player.player_id == owner_player_id)
        if is_owner and spawn_grace_remaining > 0.0:
            continue
        if CollisionMath.circle_circle_overlap(
                position, params.radius, player.position, player.get_collision_radius()):
            return (_Sys.DespawnReason.SELF
                    if is_owner else _Sys.DespawnReason.PLAYER)
```

- [ ] **Step 4: Run tests green**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_projectile_entity_collision.gd -gexit
```

Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/entities/projectile_entity.gd godot/tests/entities/test_projectile_entity_collision.gd
git commit -m "ProjectileEntity.advance: enemy, player, and self-grace collision"
```

---

## Task 11: `ProjectileSystem.spawn_authoritative` and `spawn_predicted`

**Files:**
- Modify: `godot/simulation/systems/projectile_system.gd`
- Create: `godot/tests/systems/test_projectile_system_spawn.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/systems/test_projectile_system_spawn.gd`:

```gdscript
extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")

func _make_system() -> ProjectileSystem:
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    return sys

func test_spawn_authoritative_assigns_monotonic_ids():
    var sys = _make_system()
    var a = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
        Vector2(100, 100), Vector2.RIGHT, 1)
    var b = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
        Vector2(100, 100), Vector2.RIGHT, 2)
    assert_gt(b.projectile_id, a.projectile_id)
    assert_eq(sys.projectiles.size(), 2)

func test_spawn_authoritative_stores_owner_and_direction():
    var sys = _make_system()
    var p = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
        Vector2(100, 100), Vector2.RIGHT, 7)
    assert_eq(p.owner_player_id, 42)
    assert_eq(p.direction, Vector2.RIGHT)
    assert_eq(p.spawn_input_seq, 7)

func test_spawn_predicted_uses_negative_id():
    var sys = _make_system()
    var p = sys.spawn_predicted(42, ProjectileType.Id.TEST,
        Vector2(100, 100), Vector2.RIGHT, 55)
    assert_eq(p.projectile_id, -55)
    assert_true(p.is_predicted)
    assert_true(sys.projectiles.has(-55))

func test_spawn_predicted_does_not_collide_with_authoritative_ids():
    var sys = _make_system()
    var auth = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
        Vector2(100, 100), Vector2.RIGHT, 1)
    var pred = sys.spawn_predicted(42, ProjectileType.Id.TEST,
        Vector2(100, 100), Vector2.RIGHT, 99)
    assert_ne(auth.projectile_id, pred.projectile_id)
    assert_eq(sys.projectiles.size(), 2)
```

- [ ] **Step 2: Run to verify failure**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_system_spawn.gd -gexit
```

Expected: method-missing errors.

- [ ] **Step 3: Add spawn methods to `ProjectileSystem`**

In `godot/simulation/systems/projectile_system.gd`, add:

```gdscript
func spawn_authoritative(
        owner_id: int, type_id: int,
        origin: Vector2, direction: Vector2,
        input_seq: int) -> ProjectileEntity:
    var id: int = _next_server_id
    _next_server_id = ((_next_server_id + 1) % 65535)
    if _next_server_id == 0:
        _next_server_id = 1
    var params := ProjectileType.get_params(type_id)
    var p := ProjectileEntity.new()
    p.initialize(id, type_id, owner_id, origin, direction, params)
    p.is_predicted = false
    p.spawn_input_seq = input_seq
    projectiles[id] = p
    EventBus.projectile_spawned.emit({
        "projectile_id": id,
        "type_id": type_id,
        "owner_player_id": owner_id,
        "position": p.position,
        "direction": direction,
    })
    return p


func spawn_predicted(
        owner_id: int, type_id: int,
        origin: Vector2, direction: Vector2,
        input_seq: int) -> ProjectileEntity:
    var temp_id: int = -input_seq
    var params := ProjectileType.get_params(type_id)
    var p := ProjectileEntity.new()
    p.initialize(temp_id, type_id, owner_id, origin, direction, params)
    p.is_predicted = true
    p.spawn_input_seq = input_seq
    projectiles[temp_id] = p
    EventBus.projectile_spawned.emit({
        "projectile_id": temp_id,
        "type_id": type_id,
        "owner_player_id": owner_id,
        "position": p.position,
        "direction": direction,
    })
    return p
```

- [ ] **Step 4: Rebuild class cache and run tests green**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_system_spawn.gd -gexit
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/systems/projectile_system.gd godot/tests/systems/test_projectile_system_spawn.gd
git commit -m "ProjectileSystem: spawn_authoritative and spawn_predicted"
```

---

## Task 12: `ProjectileSystem.advance` + rejection timeout

**Files:**
- Modify: `godot/simulation/systems/projectile_system.gd`
- Create: `godot/tests/systems/test_projectile_system_advance.gd`
- Create: `godot/tests/systems/test_projectile_system_reject.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/systems/test_projectile_system_advance.gd`:

```gdscript
extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")

func _make_system() -> ProjectileSystem:
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    return sys

func test_advance_steps_all_projectiles():
    var sys = _make_system()
    sys.spawn_authoritative(42, ProjectileType.Id.TEST,
        Vector2.ZERO, Vector2.RIGHT, 1)
    sys.spawn_authoritative(42, ProjectileType.Id.TEST,
        Vector2(500, 500), Vector2.DOWN, 2)
    sys.advance(0.05, [], [])
    for id in sys.projectiles.keys():
        var p = sys.projectiles[id]
        assert_ne(p.position, Vector2.ZERO)

func test_advance_removes_despawned_projectiles():
    var sys = _make_system()
    var p = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
        Vector2.ZERO, Vector2.RIGHT, 1)
    # Force lifetime expiry
    p.time_remaining = 0.001
    var despawned = sys.advance(0.1, [], [])
    assert_eq(despawned.size(), 1)
    assert_eq(despawned[0]["reason"], ProjectileSystemCls.DespawnReason.LIFETIME)
    assert_false(sys.projectiles.has(p.projectile_id))

func test_advance_returns_empty_array_when_no_despawns():
    var sys = _make_system()
    sys.spawn_authoritative(42, ProjectileType.Id.TEST,
        Vector2(1000, 1000), Vector2.RIGHT, 1)
    var despawned = sys.advance(0.05, [], [])
    assert_eq(despawned.size(), 0)
```

Create `godot/tests/systems/test_projectile_system_reject.gd`:

```gdscript
extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")

func test_predicted_projectile_times_out_to_rejected():
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    sys._current_rtt_ms = 100   # 0.1 s RTT, so timeout = 0.3 s
    var p = sys.spawn_predicted(42, ProjectileType.Id.TEST,
        Vector2.ZERO, Vector2.RIGHT, 77)

    # Advance past the timeout in small chunks
    var despawned: Array = []
    for _i in 20:
        despawned = sys.advance(0.02, [], [])
        if despawned.size() > 0:
            break

    assert_eq(despawned.size(), 1)
    assert_eq(despawned[0]["reason"], ProjectileSystemCls.DespawnReason.REJECTED)
    assert_false(sys.projectiles.has(-77))

func test_authoritative_projectile_never_times_out_to_rejected():
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    sys._current_rtt_ms = 100
    var p = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
        Vector2.ZERO, Vector2.RIGHT, 1)
    # Force lifetime to be very large so only rejection could fire
    p.time_remaining = 100.0
    for _i in 20:
        var despawned = sys.advance(0.02, [], [])
        for entry in despawned:
            assert_ne(entry["reason"], ProjectileSystemCls.DespawnReason.REJECTED)
```

- [ ] **Step 2: Run to verify failure**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_system_advance.gd -gexit
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_system_reject.gd -gexit
```

Both should fail — method missing.

- [ ] **Step 3: Implement `advance` in `ProjectileSystem`**

Add to `godot/simulation/systems/projectile_system.gd`:

```gdscript
func advance(dt: float, players: Array, enemies: Array) -> Array:
    var despawned: Array = []
    var rejection_timeout_s: float = 2.0 * (_current_rtt_ms / 1000.0) + 0.1

    for id in projectiles.keys():
        var p: ProjectileEntity = projectiles[id]
        var reason: int = p.advance(dt, _walls, players, enemies)

        # Rejection timeout check for predicted projectiles — lives here, not in
        # ProjectileEntity, because only the system holds the current RTT estimate.
        if reason == DespawnReason.ALIVE and p.is_predicted:
            if p.time_since_spawn > rejection_timeout_s:
                reason = DespawnReason.REJECTED

        if reason != DespawnReason.ALIVE:
            despawned.append({
                "id": id,
                "reason": reason,
                "position": p.position,
            })

    for entry in despawned:
        var dead_id: int = entry["id"]
        projectiles.erase(dead_id)
        EventBus.projectile_despawned.emit({
            "projectile_id": dead_id,
            "reason": entry["reason"],
            "position": entry["position"],
        })

    return despawned
```

- [ ] **Step 4: Run tests green**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_system_advance.gd -gexit
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_system_reject.gd -gexit
```

Expected: both test files pass.

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/systems/projectile_system.gd godot/tests/systems/test_projectile_system_advance.gd godot/tests/systems/test_projectile_system_reject.gd
git commit -m "ProjectileSystem.advance with rejection timeout for predicted projectiles"
```

---

## Task 13: `ProjectileSystem.adopt_authoritative` + `on_despawn_event`

**Files:**
- Modify: `godot/simulation/systems/projectile_system.gd`
- Create: `godot/tests/systems/test_projectile_system_reconcile.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/systems/test_projectile_system_reconcile.gd`:

```gdscript
extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")

func _make_system() -> ProjectileSystem:
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    return sys

func test_adopt_rekeys_matching_predicted_by_input_seq():
    var sys = _make_system()
    var pred = sys.spawn_predicted(42, ProjectileType.Id.TEST,
        Vector2.ZERO, Vector2.RIGHT, 77)
    assert_true(sys.projectiles.has(-77))

    sys.adopt_authoritative(500, 42, ProjectileType.Id.TEST,
        Vector2.ZERO, Vector2.RIGHT, 77, 0)

    assert_false(sys.projectiles.has(-77))
    assert_true(sys.projectiles.has(500))
    assert_eq(sys.projectiles[500].projectile_id, 500)
    assert_false(sys.projectiles[500].is_predicted)

func test_adopt_spawns_fresh_when_no_matching_predicted():
    var sys = _make_system()
    sys.adopt_authoritative(500, 99, ProjectileType.Id.TEST,
        Vector2(100, 100), Vector2.RIGHT, 77, 100)  # rtt 100
    assert_true(sys.projectiles.has(500))
    # Fresh spawn should fast-forward by rtt/2 = 50 ms of travel
    var p: ProjectileEntity = sys.projectiles[500]
    assert_gt(p.position.x, 100.0)

func test_on_despawn_event_removes_projectile():
    var sys = _make_system()
    var pred = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
        Vector2.ZERO, Vector2.RIGHT, 1)
    var id = pred.projectile_id
    sys.on_despawn_event(id, ProjectileSystemCls.DespawnReason.WALL, Vector2(10, 10))
    assert_false(sys.projectiles.has(id))

func test_on_despawn_event_idempotent_on_missing_id():
    var sys = _make_system()
    # No crash when despawning a projectile that doesn't exist
    sys.on_despawn_event(999, ProjectileSystemCls.DespawnReason.WALL, Vector2(10, 10))
    pass_test("did not crash")
```

- [ ] **Step 2: Run to verify failure**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_system_reconcile.gd -gexit
```

Expected: method missing.

- [ ] **Step 3: Implement the two methods**

Add to `godot/simulation/systems/projectile_system.gd`:

```gdscript
const _RECONCILE_NO_ACTION_THRESHOLD: float = 2.0
const _RECONCILE_SNAP_THRESHOLD: float = 200.0


func adopt_authoritative(
        projectile_id: int, owner_id: int, type_id: int,
        origin: Vector2, direction: Vector2,
        input_seq: int, current_rtt_ms: int) -> void:
    var temp_id: int = -input_seq
    if projectiles.has(temp_id) and projectiles[temp_id].owner_player_id == owner_id:
        var predicted: ProjectileEntity = projectiles[temp_id]
        projectiles.erase(temp_id)
        predicted.projectile_id = projectile_id
        predicted.is_predicted = false
        projectiles[projectile_id] = predicted

        var one_way_s: float = current_rtt_ms / 2000.0
        var expected: Vector2 = origin + direction * predicted.params.speed * one_way_s
        var drift: float = predicted.position.distance_to(expected)
        if drift < _RECONCILE_NO_ACTION_THRESHOLD:
            pass
        elif drift < _RECONCILE_SNAP_THRESHOLD:
            predicted.start_reconcile(expected)
        else:
            push_warning("projectile %d hard snap, drift %.1f px" % [projectile_id, drift])
            predicted.position = expected
        return

    # No matching predicted — spawn a fresh remote projectile and fast-forward.
    var params := ProjectileType.get_params(type_id)
    var fresh := ProjectileEntity.new()
    var one_way_s: float = current_rtt_ms / 2000.0
    var spawn_pos: Vector2 = origin + direction * params.speed * one_way_s
    fresh.initialize(projectile_id, type_id, owner_id, spawn_pos, direction, params)
    projectiles[projectile_id] = fresh
    EventBus.projectile_spawned.emit({
        "projectile_id": projectile_id,
        "type_id": type_id,
        "owner_player_id": owner_id,
        "position": spawn_pos,
        "direction": direction,
    })


func on_despawn_event(projectile_id: int, reason: int, pos: Vector2) -> void:
    if not projectiles.has(projectile_id):
        return
    projectiles.erase(projectile_id)
    EventBus.projectile_despawned.emit({
        "projectile_id": projectile_id,
        "reason": reason,
        "position": pos,
    })
```

- [ ] **Step 4: Run tests green**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_system_reconcile.gd -gexit
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/systems/projectile_system.gd godot/tests/systems/test_projectile_system_reconcile.gd
git commit -m "ProjectileSystem: adopt_authoritative rekey + on_despawn_event handler"
```

---

## Task 14: Fire cooldown API

**Files:**
- Modify: `godot/simulation/systems/projectile_system.gd`
- Create: `godot/tests/systems/test_projectile_system_cooldown.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/systems/test_projectile_system_cooldown.gd`:

```gdscript
extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")

func test_can_fire_defaults_true():
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    assert_true(sys.can_fire(42))

func test_start_cooldown_blocks_can_fire():
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    sys.start_cooldown(42)
    assert_false(sys.can_fire(42))

func test_tick_cooldowns_decrements():
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    sys.start_cooldown(42)
    sys.tick_cooldowns(0.30)  # longer than 0.20 fire_cooldown
    assert_true(sys.can_fire(42))

func test_cooldown_is_per_player():
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    sys.start_cooldown(42)
    assert_false(sys.can_fire(42))
    assert_true(sys.can_fire(99))
```

- [ ] **Step 2: Run to verify failure**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_system_cooldown.gd -gexit
```

- [ ] **Step 3: Implement cooldown API**

Add to `godot/simulation/systems/projectile_system.gd`:

```gdscript
func can_fire(player_id: int) -> bool:
    return _fire_cooldown.get(player_id, 0.0) <= 0.0


func start_cooldown(player_id: int) -> void:
    var params := ProjectileType.get_params(ProjectileType.Id.TEST)
    _fire_cooldown[player_id] = params.fire_cooldown


func tick_cooldowns(dt: float) -> void:
    for id in _fire_cooldown.keys():
        _fire_cooldown[id] = max(0.0, _fire_cooldown[id] - dt)
```

- [ ] **Step 4: Run tests green**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_system_cooldown.gd -gexit
```

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/systems/projectile_system.gd godot/tests/systems/test_projectile_system_cooldown.gd
git commit -m "ProjectileSystem: fire cooldown API"
```

---

## Task 15: Binary message types + Layout constants

**Files:**
- Modify: `godot/shared/network/message_types.gd`

- [ ] **Step 1: Add new enum values and Layout constants**

In `godot/shared/network/message_types.gd`, update the `Binary` enum:

```gdscript
enum Binary {
    FULL_SNAPSHOT        = 1,
    DELTA_SNAPSHOT       = 2,
    SNAPSHOT_ACK         = 3,
    PLAYER_INPUT         = 4,
    ENEMY_DIED           = 5,
    PROJECTILE_SPAWNED   = 6,
    PROJECTILE_DESPAWNED = 7,
}
```

And add to the `Layout` class (inside the existing class body):

```gdscript
    const PROJECTILE_SPAWNED_SIZE   = 26
    const PROJECTILE_DESPAWNED_SIZE = 12
```

- [ ] **Step 2: Sanity check**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: all existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add godot/shared/network/message_types.gd
git commit -m "Add PROJECTILE_SPAWNED/DESPAWNED binary message types and layout sizes"
```

---

## Task 16: `PROJECTILE_SPAWNED` encode/decode

**Files:**
- Modify: `godot/simulation/network/net_server.gd` (add `encode_projectile_spawned`)
- Modify: `godot/simulation/network/net_client.gd` (add `decode_projectile_spawned`)
- Create: `godot/tests/network/test_projectile_network.gd`

- [ ] **Step 1: Write failing test**

Create `godot/tests/network/test_projectile_network.gd`:

```gdscript
extends GutTest

var NetServerCls = preload("res://simulation/network/net_server.gd")
var NetClientCls = preload("res://simulation/network/net_client.gd")

func test_projectile_spawned_round_trip():
    var event = {
        "projectile_id": 1234,
        "type_id": 0,
        "owner_player_id": 42,
        "origin": Vector2(100.5, 200.25),
        "direction": Vector2(0.6, 0.8),
        "input_seq": 999,
    }
    var bytes: PackedByteArray = NetServerCls.encode_projectile_spawned(event)
    assert_eq(bytes.size(), MessageTypes.Layout.PROJECTILE_SPAWNED_SIZE)
    var decoded: Dictionary = NetClientCls.decode_projectile_spawned(bytes)
    assert_eq(decoded["projectile_id"], 1234)
    assert_eq(decoded["type_id"], 0)
    assert_eq(decoded["owner_player_id"], 42)
    assert_almost_eq(decoded["origin"].x, 100.5, 0.01)
    assert_almost_eq(decoded["origin"].y, 200.25, 0.01)
    assert_almost_eq(decoded["direction"].x, 0.6, 0.01)
    assert_almost_eq(decoded["direction"].y, 0.8, 0.01)
    assert_eq(decoded["input_seq"], 999)
```

- [ ] **Step 2: Run to verify failure**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_projectile_network.gd -gexit
```

- [ ] **Step 3: Implement encode on server side**

Add to `godot/simulation/network/net_server.gd`:

```gdscript
static func encode_projectile_spawned(event: Dictionary) -> PackedByteArray:
    var buf := PackedByteArray()
    buf.resize(MessageTypes.Layout.PROJECTILE_SPAWNED_SIZE)
    buf.encode_u8(0, MessageTypes.Binary.PROJECTILE_SPAWNED)
    buf.encode_u16(1, event["projectile_id"])
    buf.encode_u8(3, event["type_id"])
    buf.encode_u16(4, event["owner_player_id"])
    buf.encode_float(6,  event["origin"].x)
    buf.encode_float(10, event["origin"].y)
    buf.encode_float(14, event["direction"].x)
    buf.encode_float(18, event["direction"].y)
    buf.encode_u32(22, event["input_seq"])
    return buf
```

- [ ] **Step 4: Implement decode on client side**

Add to `godot/simulation/network/net_client.gd`:

```gdscript
static func decode_projectile_spawned(bytes: PackedByteArray) -> Dictionary:
    return {
        "projectile_id": bytes.decode_u16(1),
        "type_id": bytes.decode_u8(3),
        "owner_player_id": bytes.decode_u16(4),
        "origin": Vector2(bytes.decode_float(6),  bytes.decode_float(10)),
        "direction": Vector2(bytes.decode_float(14), bytes.decode_float(18)),
        "input_seq": bytes.decode_u32(22),
    }
```

- [ ] **Step 5: Run tests green**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_projectile_network.gd -gexit
```

- [ ] **Step 6: Commit**

```bash
git add godot/simulation/network/net_server.gd godot/simulation/network/net_client.gd godot/tests/network/test_projectile_network.gd
git commit -m "Add PROJECTILE_SPAWNED encode/decode"
```

---

## Task 17: `PROJECTILE_DESPAWNED` encode/decode

**Files:**
- Modify: `godot/simulation/network/net_server.gd`
- Modify: `godot/simulation/network/net_client.gd`
- Modify: `godot/tests/network/test_projectile_network.gd`

- [ ] **Step 1: Add failing test**

In `godot/tests/network/test_projectile_network.gd`, append:

```gdscript
func test_projectile_despawned_round_trip():
    var event = {
        "projectile_id": 1234,
        "reason": 2,  # ENEMY
        "position": Vector2(500.75, 300.5),
    }
    var bytes: PackedByteArray = NetServerCls.encode_projectile_despawned(event)
    assert_eq(bytes.size(), MessageTypes.Layout.PROJECTILE_DESPAWNED_SIZE)
    var decoded = NetClientCls.decode_projectile_despawned(bytes)
    assert_eq(decoded["projectile_id"], 1234)
    assert_eq(decoded["reason"], 2)
    assert_almost_eq(decoded["position"].x, 500.75, 0.01)
    assert_almost_eq(decoded["position"].y, 300.5, 0.01)
```

- [ ] **Step 2: Run to verify failure**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_projectile_network.gd -gexit
```

- [ ] **Step 3: Implement encode/decode**

Add to `godot/simulation/network/net_server.gd`:

```gdscript
static func encode_projectile_despawned(event: Dictionary) -> PackedByteArray:
    var buf := PackedByteArray()
    buf.resize(MessageTypes.Layout.PROJECTILE_DESPAWNED_SIZE)
    buf.encode_u8(0, MessageTypes.Binary.PROJECTILE_DESPAWNED)
    buf.encode_u16(1, event["projectile_id"])
    buf.encode_u8(3, event["reason"])
    buf.encode_float(4, event["position"].x)
    buf.encode_float(8, event["position"].y)
    return buf
```

Add to `godot/simulation/network/net_client.gd`:

```gdscript
static func decode_projectile_despawned(bytes: PackedByteArray) -> Dictionary:
    return {
        "projectile_id": bytes.decode_u16(1),
        "reason": bytes.decode_u8(3),
        "position": Vector2(bytes.decode_float(4), bytes.decode_float(8)),
    }
```

- [ ] **Step 4: Run tests green**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_projectile_network.gd -gexit
```

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/network/net_server.gd godot/simulation/network/net_client.gd godot/tests/network/test_projectile_network.gd
git commit -m "Add PROJECTILE_DESPAWNED encode/decode"
```

---

## Task 18: `PlayerPositionHistory` ring buffer

**Files:**
- Create: `godot/simulation/systems/player_position_history.gd`
- Create: `godot/tests/systems/test_player_position_history.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/systems/test_player_position_history.gd`:

```gdscript
extends GutTest

var PlayerPositionHistory = preload("res://simulation/systems/player_position_history.gd")

func test_record_and_lookup_exact_tick():
    var hist = PlayerPositionHistory.new()
    hist.record(1, 100, Vector2(50, 50))
    assert_eq(hist.lookup(1, 100), Vector2(50, 50))

func test_lookup_returns_closest_older_sample():
    var hist = PlayerPositionHistory.new()
    hist.record(1, 100, Vector2(50, 50))
    hist.record(1, 105, Vector2(100, 100))
    # Lookup at tick 103 should return the older sample (tick 100)
    # since 103 is between 100 and 105 and we pick the one at or before.
    assert_eq(hist.lookup(1, 103), Vector2(50, 50))

func test_lookup_returns_latest_when_target_in_future():
    var hist = PlayerPositionHistory.new()
    hist.record(1, 100, Vector2(50, 50))
    hist.record(1, 105, Vector2(100, 100))
    assert_eq(hist.lookup(1, 200), Vector2(100, 100))

func test_lookup_returns_oldest_when_target_too_far_back():
    var hist = PlayerPositionHistory.new()
    hist.record(1, 100, Vector2(50, 50))
    hist.record(1, 105, Vector2(100, 100))
    assert_eq(hist.lookup(1, 50), Vector2(50, 50))

func test_ring_buffer_prunes_to_max_samples():
    var hist = PlayerPositionHistory.new()
    for i in 100:
        hist.record(1, i, Vector2(i, 0))
    # Should keep only MAX_SAMPLES recent ones
    assert_eq(hist._samples_per_player[1].size(), PlayerPositionHistory.MAX_SAMPLES)
    # Oldest sample should be tick 100 - MAX_SAMPLES
    assert_eq(hist._samples_per_player[1][0]["tick"],
        100 - PlayerPositionHistory.MAX_SAMPLES)

func test_drop_player_removes_all_samples():
    var hist = PlayerPositionHistory.new()
    hist.record(1, 100, Vector2(50, 50))
    hist.drop_player(1)
    assert_false(hist._samples_per_player.has(1))

func test_per_player_isolation():
    var hist = PlayerPositionHistory.new()
    hist.record(1, 100, Vector2(50, 50))
    hist.record(2, 100, Vector2(200, 200))
    assert_eq(hist.lookup(1, 100), Vector2(50, 50))
    assert_eq(hist.lookup(2, 100), Vector2(200, 200))
```

- [ ] **Step 2: Run to verify failure**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_player_position_history.gd -gexit
```

- [ ] **Step 3: Implement `PlayerPositionHistory`**

Create `godot/simulation/systems/player_position_history.gd`:

```gdscript
class_name PlayerPositionHistory
extends RefCounted

const MAX_SAMPLES = 32

var _samples_per_player: Dictionary = {}  # player_id -> Array[{tick: int, pos: Vector2}]

func record(player_id: int, tick: int, pos: Vector2) -> void:
    if not _samples_per_player.has(player_id):
        _samples_per_player[player_id] = []
    var samples: Array = _samples_per_player[player_id]
    samples.append({"tick": tick, "pos": pos})
    while samples.size() > MAX_SAMPLES:
        samples.pop_front()

func lookup(player_id: int, target_tick: int) -> Vector2:
    if not _samples_per_player.has(player_id):
        return Vector2.ZERO
    var samples: Array = _samples_per_player[player_id]
    if samples.is_empty():
        return Vector2.ZERO
    if target_tick <= samples[0]["tick"]:
        return samples[0]["pos"]
    if target_tick >= samples[-1]["tick"]:
        return samples[-1]["pos"]
    # Binary search not necessary for 32 samples — linear scan is fine.
    var best = samples[0]
    for s in samples:
        if s["tick"] <= target_tick:
            best = s
        else:
            break
    return best["pos"]

func drop_player(player_id: int) -> void:
    _samples_per_player.erase(player_id)
```

- [ ] **Step 4: Rebuild class cache and run tests**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_player_position_history.gd -gexit
```

Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/systems/player_position_history.gd godot/tests/systems/test_player_position_history.gd
git commit -m "Add PlayerPositionHistory ring buffer for server shooter rewind"
```

---

## Task 19: `NetServer` per-player RTT tracking via `SNAPSHOT_ACK` timing

**Files:**
- Modify: `godot/simulation/network/net_server.gd`
- (optional) create `godot/tests/network/test_net_server_rtt.gd` if testable headlessly

- [ ] **Step 1: Add RTT tracking state**

In `godot/simulation/network/net_server.gd`, add per-connection state (find where per-player state is stored and add alongside):

```gdscript
# Per-player RTT tracking
# For each snapshot we send, record tick -> send_time_ms
# On ACK receipt, compute round trip and update rolling average.
var _pending_snapshot_sends: Dictionary = {}  # player_id -> Dictionary[tick, send_ms]
var _rtt_samples: Dictionary = {}             # player_id -> Array[int] (ms samples)
const _RTT_SAMPLE_WINDOW = 8
```

- [ ] **Step 2: Hook into snapshot send and ACK receive**

Wherever `NetServer` currently sends a snapshot to a peer, record the send time:

```gdscript
func _record_snapshot_send(player_id: int, tick: int) -> void:
    if not _pending_snapshot_sends.has(player_id):
        _pending_snapshot_sends[player_id] = {}
    _pending_snapshot_sends[player_id][tick] = Time.get_ticks_msec()
```

And wherever `NetServer` currently processes a `SNAPSHOT_ACK`, call:

```gdscript
func _record_snapshot_ack(player_id: int, tick: int) -> void:
    if not _pending_snapshot_sends.has(player_id):
        return
    var sends: Dictionary = _pending_snapshot_sends[player_id]
    if not sends.has(tick):
        return
    var send_ms: int = sends[tick]
    var rtt_ms: int = Time.get_ticks_msec() - send_ms
    sends.erase(tick)

    if not _rtt_samples.has(player_id):
        _rtt_samples[player_id] = []
    var samples: Array = _rtt_samples[player_id]
    samples.append(rtt_ms)
    while samples.size() > _RTT_SAMPLE_WINDOW:
        samples.pop_front()
```

- [ ] **Step 3: Expose `get_rtt_ms`**

Add:

```gdscript
func get_rtt_ms(player_id: int) -> int:
    if not _rtt_samples.has(player_id):
        return 0
    var samples: Array = _rtt_samples[player_id]
    if samples.is_empty():
        return 0
    var sum: int = 0
    for s in samples:
        sum += s
    return sum / samples.size()
```

- [ ] **Step 4: Clean up on disconnect**

Wherever the server handles player disconnection, call:

```gdscript
_pending_snapshot_sends.erase(player_id)
_rtt_samples.erase(player_id)
```

- [ ] **Step 5: Sanity check**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: all existing tests pass (no regressions).

- [ ] **Step 6: Commit**

```bash
git add godot/simulation/network/net_server.gd
git commit -m "NetServer: per-player RTT tracking via snapshot ACK round trip"
```

---

## Task 20: `ProjectileSpawnRouter.handle_fire`

**Files:**
- Create: `godot/simulation/systems/projectile_spawn_router.gd`
- Create: `godot/tests/systems/test_projectile_spawn_router.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/systems/test_projectile_spawn_router.gd`:

```gdscript
extends GutTest

var ProjectileSpawnRouter = preload("res://simulation/systems/projectile_spawn_router.gd")
var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
var PlayerPositionHistory = preload("res://simulation/systems/player_position_history.gd")

func _make_player(id: int, pos: Vector2) -> PlayerEntity:
    var p = PlayerEntityScene.instantiate()
    add_child_autofree(p)
    p.player_id = id
    p.position = pos
    p.aim_direction = Vector2.RIGHT
    return p

func test_no_fire_flag_no_spawn():
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    var player = _make_player(42, Vector2(100, 100))
    var input = {
        "action_flags": 0,
        "input_seq": 1,
    }
    ProjectileSpawnRouter.handle_fire(player, input, sys, {"authoritative": false})
    assert_eq(sys.projectiles.size(), 0)

func test_cooldown_blocks_spawn():
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    sys.start_cooldown(42)
    var player = _make_player(42, Vector2(100, 100))
    var input = {
        "action_flags": MessageTypes.InputActionFlags.FIRE,
        "input_seq": 1,
    }
    ProjectileSpawnRouter.handle_fire(player, input, sys, {"authoritative": false})
    assert_eq(sys.projectiles.size(), 0)

func test_client_branch_spawns_predicted_from_player_position():
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    var player = _make_player(42, Vector2(100, 100))
    var input = {
        "action_flags": MessageTypes.InputActionFlags.FIRE,
        "input_seq": 1,
    }
    ProjectileSpawnRouter.handle_fire(player, input, sys, {"authoritative": false})
    assert_eq(sys.projectiles.size(), 1)
    assert_true(sys.projectiles.has(-1))   # negative temp id
    var proj: ProjectileEntity = sys.projectiles[-1]
    var params = ProjectileType.get_params(ProjectileType.Id.TEST)
    # Predicted spawn position is player position + aim * spawn_offset
    assert_almost_eq(proj.position.x, 100.0 + params.spawn_offset, 0.01)
    assert_almost_eq(proj.position.y, 100.0, 0.01)

func test_server_branch_rewinds_from_history_and_fast_forwards():
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    var history = PlayerPositionHistory.new()
    history.record(42, 100, Vector2(50, 100))   # past position
    history.record(42, 105, Vector2(80, 100))   # current-ish
    var player = _make_player(42, Vector2(80, 100))
    var spawn_events: Array = []
    var context = {
        "authoritative": true,
        "rtt_ms": 100,   # 50 ms one-way
        "position_history": history,
        "tick": 105,
        "spawn_events": spawn_events,
    }
    var input = {
        "action_flags": MessageTypes.InputActionFlags.FIRE,
        "input_seq": 77,
    }
    ProjectileSpawnRouter.handle_fire(player, input, sys, context)
    assert_eq(sys.projectiles.size(), 1)
    assert_eq(spawn_events.size(), 1)
    # The spawn origin should be closer to the rewound position (50,100) than to
    # the current position (80,100), after adding spawn_offset on the x axis.
    # With 100ms RTT, rewind = ~1.5 ticks at 33.3ms/tick, so rewound_tick ≈ 103.5
    # which maps to sample at tick 100 (Vector2(50,100)).
    var origin: Vector2 = spawn_events[0]["origin"]
    # After rewind + offset (+40) + fast-forward (50ms * 600 px/s = 30)
    # Expected near x = 50 + 40 + 30 = 120
    assert_almost_eq(origin.x, 120.0, 10.0)
    assert_almost_eq(origin.y, 100.0, 1.0)
    assert_eq(spawn_events[0]["owner_player_id"], 42)
    assert_eq(spawn_events[0]["input_seq"], 77)
```

- [ ] **Step 2: Run to verify failure**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_spawn_router.gd -gexit
```

- [ ] **Step 3: Implement the router**

Create `godot/simulation/systems/projectile_spawn_router.gd`:

```gdscript
class_name ProjectileSpawnRouter

static func handle_fire(
        player: PlayerEntity,
        input: Dictionary,
        projectile_system: ProjectileSystem,
        context: Dictionary) -> void:

    var flags: int = input.get("action_flags", 0)
    if (flags & MessageTypes.InputActionFlags.FIRE) == 0:
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
        var rewind_ticks: int = int(round((rtt_ms / 2.0) / MessageTypes.TICK_INTERVAL_MS))
        var rewound_pos: Vector2 = history.lookup(player.player_id, tick - rewind_ticks)
        var origin: Vector2 = rewound_pos + aim * params.spawn_offset
        var proj: ProjectileEntity = projectile_system.spawn_authoritative(
            player.player_id, type_id, origin, aim, input["input_seq"])
        proj.advance(rtt_ms / 2000.0, projectile_system.get_walls(), [], [])
        context["spawn_events"].append({
            "projectile_id": proj.projectile_id,
            "type_id": type_id,
            "owner_player_id": player.player_id,
            "origin": proj.position,
            "direction": aim,
            "input_seq": input["input_seq"],
        })
    else:
        var origin := player.position + aim * params.spawn_offset
        projectile_system.spawn_predicted(
            player.player_id, type_id, origin, aim, input["input_seq"])

    projectile_system.start_cooldown(player.player_id)
```

- [ ] **Step 4: Rebuild class cache and run tests**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_spawn_router.gd -gexit
```

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/systems/projectile_spawn_router.gd godot/tests/systems/test_projectile_spawn_router.gd
git commit -m "Add ProjectileSpawnRouter for shared fire-input dispatch"
```

---

## Task 21: Server tick loop integration

**Files:**
- Modify: `godot/simulation/network/net_server.gd` (tick loop body)
- Modify: `godot/simulation/systems/movement_system.gd` (or wherever server applies per-player inputs) to call the router

This task wires all the simulation pieces into the existing server tick loop. The exact method names in `net_server.gd` may differ; adapt to whatever it currently calls per tick.

- [ ] **Step 1: Instantiate `ProjectileSystem` and `PlayerPositionHistory` on server boot**

In `net_server.gd`, add fields:

```gdscript
var _projectile_system: ProjectileSystem
var _player_position_history: PlayerPositionHistory
var _queued_spawn_events: Array = []
var _queued_despawn_events: Array = []
```

In the server's `_ready()` or bootstrap method (after the arena is loaded), add:

```gdscript
_projectile_system = ProjectileSystem.new()
add_child(_projectile_system)
_projectile_system.set_walls(WallGeometry.extract_aabbs(get_node("/root/Server/Arena")))
# ^ Adjust the arena node path to match your server scene layout.
_player_position_history = PlayerPositionHistory.new()

EventBus.projectile_despawned.connect(_on_projectile_despawned)
```

And the handler:

```gdscript
func _on_projectile_despawned(event: Dictionary) -> void:
    _queued_despawn_events.append(event)
```

- [ ] **Step 2: Record positions every tick**

In the server's `_physics_process` (or tick method), at the top:

```gdscript
for player in _players.values():
    _player_position_history.record(player.player_id, _current_tick, player.position)
```

- [ ] **Step 3: Call the router for each incoming input**

Find the per-input processing loop. For each input applied to a player, add a fire dispatch right after the movement application:

```gdscript
for input in inputs_this_tick:
    var player: PlayerEntity = _players[input["player_id"]]
    MovementSystem.apply_input(player, input)
    ProjectileSpawnRouter.handle_fire(player, input, _projectile_system, {
        "authoritative": true,
        "rtt_ms": get_rtt_ms(input["player_id"]),
        "position_history": _player_position_history,
        "tick": _current_tick,
        "spawn_events": _queued_spawn_events,
    })
```

Drain `_queued_spawn_events` at broadcast time (next step).

- [ ] **Step 4: Advance the projectile system every tick**

After enemy system advance:

```gdscript
_projectile_system.tick_cooldowns(MessageTypes.TICK_INTERVAL_MS / 1000.0)
var despawns: Array = _projectile_system.advance(
    MessageTypes.TICK_INTERVAL_MS / 1000.0, _players.values(), _enemy_system.enemies)
# EventBus already populated _queued_despawn_events via the signal handler.
```

- [ ] **Step 5: Broadcast spawn and despawn events**

At the end of the tick, before sending snapshots (or right after — order doesn't matter since they're independent messages):

```gdscript
for evt in _queued_spawn_events:
    var bytes = NetServer.encode_projectile_spawned(evt)
    _broadcast_to_all(bytes)
_queued_spawn_events.clear()

for evt in _queued_despawn_events:
    var bytes = NetServer.encode_projectile_despawned(evt)
    _broadcast_to_all(bytes)
_queued_despawn_events.clear()
```

- [ ] **Step 6: Run existing tests to catch regressions**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: all existing tests pass. New integration tests arrive in later tasks.

- [ ] **Step 7: Commit**

```bash
git add godot/simulation/network/net_server.gd godot/simulation/systems/movement_system.gd
git commit -m "Server tick loop: record position history, route fire input, advance projectiles, broadcast events"
```

---

## Task 22: Input provider — fire latch

**Files:**
- Modify: `godot/simulation/input/keyboard_mouse_input_provider.gd`

This finishes the work started in Task 2: wiring up the actual input detection for mouse clicks.

- [ ] **Step 1: Add left-click detection**

In `keyboard_mouse_input_provider.gd`, in whatever method handles input polling (likely `_process` or `_unhandled_input`), add:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            _fire_latch = true
    # ... keep existing dodge / other handling
```

The latch field `_fire_latch` was already declared in Task 2. `consume_input()` from Task 2 already packs it into `action_flags`.

- [ ] **Step 2: Sanity check**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: no regressions.

- [ ] **Step 3: Commit**

```bash
git add godot/simulation/input/keyboard_mouse_input_provider.gd
git commit -m "Input provider: fire latch on left mouse click"
```

---

## Task 23: Client network message handlers

**Files:**
- Modify: `godot/simulation/network/net_client.gd`

- [ ] **Step 1: Add dispatch in the binary message handler**

In `net_client.gd`, find the binary-message switch (there's existing handling for `FULL_SNAPSHOT`, `DELTA_SNAPSHOT`, `ENEMY_DIED`, etc.). Add cases:

```gdscript
MessageTypes.Binary.PROJECTILE_SPAWNED:
    _handle_projectile_spawned(bytes)
MessageTypes.Binary.PROJECTILE_DESPAWNED:
    _handle_projectile_despawned(bytes)
```

- [ ] **Step 2: Implement handlers**

Add methods:

```gdscript
func _handle_projectile_spawned(bytes: PackedByteArray) -> void:
    var event = NetClient.decode_projectile_spawned(bytes)
    _projectile_system.adopt_authoritative(
        event["projectile_id"],
        event["owner_player_id"],
        event["type_id"],
        event["origin"],
        event["direction"],
        event["input_seq"],
        get_rtt_ms())

func _handle_projectile_despawned(bytes: PackedByteArray) -> void:
    var event = NetClient.decode_projectile_despawned(bytes)
    _projectile_system.on_despawn_event(
        event["projectile_id"], event["reason"], event["position"])
```

- [ ] **Step 3: Instantiate `ProjectileSystem` on client boot**

Near where other systems are created on the client:

```gdscript
_projectile_system = ProjectileSystem.new()
add_child(_projectile_system)
_projectile_system.set_walls(WallGeometry.extract_aabbs(get_node("/root/Client/Arena")))
# ^ Adjust the arena node path for the client scene layout.
```

Add the field:

```gdscript
var _projectile_system: ProjectileSystem
```

- [ ] **Step 4: Sanity check**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/network/net_client.gd
git commit -m "Client: handle PROJECTILE_SPAWNED and PROJECTILE_DESPAWNED binary messages"
```

---

## Task 24: Client tick loop — call router, advance, set RTT

**Files:**
- Modify: `godot/simulation/network/net_client.gd` (or wherever the client per-frame prediction runs)

- [ ] **Step 1: Wire fire router and cooldown tick**

In the client's per-display-frame prediction method, after `PlayerEntity.apply_input()` and `PlayerEntity.advance()`:

```gdscript
ProjectileSpawnRouter.handle_fire(_local_player, input, _projectile_system, {
    "authoritative": false,
})
_projectile_system.tick_cooldowns(frame_delta)
_projectile_system._current_rtt_ms = get_rtt_ms()
var despawns = _projectile_system.advance(frame_delta, [], [])
# despawns already emit projectile_despawned via EventBus inside advance()
```

Important: client passes empty arrays for players/enemies. See spec §5 — client-side projectile sim only checks walls, everything else comes from server despawn events.

- [ ] **Step 2: Sanity check**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

- [ ] **Step 3: Commit**

```bash
git add godot/simulation/network/net_client.gd
git commit -m "Client tick loop: route fire input, advance projectiles, update RTT"
```

---

## Task 25: `ProjectileView` — listeners, live position, visual styling

**Files:**
- Create: `godot/view/projectiles/projectile_view.gd`
- Modify: client scene (hook ProjectileView into the view tree)

- [ ] **Step 1: Create `ProjectileView`**

Create `godot/view/projectiles/projectile_view.gd`:

```gdscript
class_name ProjectileView
extends Node2D

@export var projectile_system_path: NodePath

var _projectile_system: ProjectileSystem
var _visuals: Dictionary = {}   # projectile_id -> Node2D
var _local_player_id: int = -1

func set_local_player_id(id: int) -> void:
    _local_player_id = id

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
    if _visuals.has(id):
        return
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

func _make_visual(type_id: int, owner_player_id: int) -> Node2D:
    var node := Node2D.new()
    var polygon := Polygon2D.new()
    polygon.color = _color_for_owner(owner_player_id)
    var verts := PackedVector2Array()
    for i in 12:
        var angle := TAU * float(i) / 12.0
        verts.append(Vector2(cos(angle), sin(angle)) * 6.0)
    polygon.polygon = verts
    node.add_child(polygon)
    return node

func _color_for_owner(owner_player_id: int) -> Color:
    if owner_player_id == _local_player_id:
        return Color(0.2, 1.0, 1.0, 1.0)   # bright cyan for local shooter
    return Color(0.2, 0.8, 0.8, 0.9)       # dimmer cyan for remote shooters

func _play_despawn_effect(pos: Vector2, reason: int) -> void:
    # Filled in by Task 26.
    pass
```

- [ ] **Step 2: Add to client scene**

Instance `ProjectileView` as a child of the client's world root. Set its `projectile_system_path` to point at the client's `ProjectileSystem` node. Wire it up in whatever scene your client currently uses (likely a `client.tscn` or the world node).

After the local player is known, call `projectile_view.set_local_player_id(local_id)`.

- [ ] **Step 3: Rebuild class cache**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 4: Sanity check**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

- [ ] **Step 5: Commit**

```bash
git add godot/view/projectiles/projectile_view.gd
git commit -m "ProjectileView: live position rendering from simulation"
```

---

## Task 26: `ProjectileView` despawn effects per reason

**Files:**
- Modify: `godot/view/projectiles/projectile_view.gd`

- [ ] **Step 1: Fill in `_play_despawn_effect`**

Replace the placeholder method:

```gdscript
func _play_despawn_effect(pos: Vector2, reason: int) -> void:
    match reason:
        ProjectileSystem.DespawnReason.WALL:
            _spawn_particle_burst(pos, Color(0.6, 0.6, 0.65), 8)
        ProjectileSystem.DespawnReason.ENEMY:
            _spawn_particle_burst(pos, Color(0.2, 1.0, 1.0), 6)
        ProjectileSystem.DespawnReason.PLAYER:
            _spawn_particle_burst(pos, Color(1.0, 0.3, 0.3), 6)
        ProjectileSystem.DespawnReason.SELF:
            _spawn_particle_burst(pos, Color(1.0, 0.2, 0.2), 6)
        ProjectileSystem.DespawnReason.LIFETIME:
            pass  # soft fade only — no particles
        ProjectileSystem.DespawnReason.REJECTED:
            pass  # deliberately invisible

func _spawn_particle_burst(pos: Vector2, color: Color, count: int) -> void:
    var particles := CPUParticles2D.new()
    particles.emitting = false
    particles.one_shot = true
    particles.explosiveness = 1.0
    particles.amount = count
    particles.lifetime = 0.25
    particles.direction = Vector2(0, -1)
    particles.spread = 180.0
    particles.initial_velocity_min = 40.0
    particles.initial_velocity_max = 90.0
    particles.color = color
    particles.gravity = Vector2.ZERO
    particles.position = pos
    add_child(particles)
    particles.emitting = true
    # Free after lifetime + buffer
    get_tree().create_timer(0.5).timeout.connect(particles.queue_free)
```

- [ ] **Step 2: Sanity check**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

- [ ] **Step 3: Commit**

```bash
git add godot/view/projectiles/projectile_view.gd
git commit -m "ProjectileView: despawn effects flavored by DespawnReason"
```

---

## Task 27: Integration — fire round-trip test

**Files:**
- Create: `godot/tests/network/test_fire_round_trip.gd`

This test uses the same harness pattern as existing `test_net_client_movement.gd` — run a headless server and a fake client in-process.

- [ ] **Step 1: Write the test**

Create `godot/tests/network/test_fire_round_trip.gd`:

```gdscript
extends GutTest

# Fires a projectile from a simulated client, pumps the network for N ticks,
# and verifies that the client ends up with an adopted authoritative projectile
# whose id is positive and whose owner matches the firing player.

var NetServerCls = preload("res://simulation/network/net_server.gd")
var NetClientCls = preload("res://simulation/network/net_client.gd")

# This test assumes the same test harness helpers used by the existing
# test_net_client_movement.gd — reuse whatever spawning/bootstrapping is
# already there rather than duplicating.

func test_fire_input_results_in_adopted_projectile_on_client():
    # Spin up server + client via existing harness (see test_net_client_movement.gd)
    var server = _bootstrap_headless_server()
    var client = _bootstrap_client_connected_to(server)

    # Wait for the handshake so local player id is known
    _pump_until(server, client, func(): return client.get_local_player_id() != -1)

    # Send a fire input
    var input = {
        "tick": client.get_current_tick(),
        "move_direction": Vector2.ZERO,
        "aim_direction": Vector2.RIGHT,
        "action_flags": MessageTypes.InputActionFlags.FIRE,
        "input_seq": client.get_next_input_seq(),
    }
    client.send_input(input)
    # Also run client prediction for this input
    ProjectileSpawnRouter.handle_fire(
        client.get_local_player(), input, client._projectile_system,
        {"authoritative": false})

    # Pump ticks until the authoritative spawn event arrives
    var found_authoritative := false
    for _i in 20:
        _pump_tick(server, client)
        for id in client._projectile_system.projectiles.keys():
            if id > 0:
                found_authoritative = true
                break
        if found_authoritative:
            break

    assert_true(found_authoritative, "client must adopt an authoritative projectile")

    # Verify owner matches
    var adopted: ProjectileEntity = null
    for id in client._projectile_system.projectiles.keys():
        if id > 0:
            adopted = client._projectile_system.projectiles[id]
            break
    assert_eq(adopted.owner_player_id, client.get_local_player_id())

# _bootstrap_headless_server, _bootstrap_client_connected_to, _pump_tick,
# and _pump_until should be copied from (or extracted from) the existing
# test_net_client_movement.gd test harness. If those helpers don't already
# exist as shared code, extract them into godot/tests/helpers/test_harness.gd
# as part of this task so the other integration tests can reuse them.
```

- [ ] **Step 2: Extract test harness helpers if needed**

If `test_net_client_movement.gd` has inline helpers for spawning a server and client, pull them out into `godot/tests/helpers/test_harness.gd` and reference from both files. Otherwise reuse the existing helpers directly. The new test must be runnable without modifying any production code.

- [ ] **Step 3: Run the test**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_fire_round_trip.gd -gexit
```

Expected: 1 test passes.

- [ ] **Step 4: Commit**

```bash
git add godot/tests/network/test_fire_round_trip.gd godot/tests/helpers/
git commit -m "Integration test: fire round-trip spawns and adopts on client"
```

---

## Task 28: Integration — collision tests (wall, self)

**Files:**
- Create: `godot/tests/network/test_projectile_collision_integration.gd`

- [ ] **Step 1: Write the tests**

Create `godot/tests/network/test_projectile_collision_integration.gd`:

```gdscript
extends GutTest

# Full-stack collision tests: client fires, server simulates, despawn event arrives.

func test_projectile_destroyed_on_wall_hit():
    var server = _bootstrap_headless_server()
    var client = _bootstrap_client_connected_to(server)
    _pump_until(server, client, func(): return client.get_local_player_id() != -1)

    # Move the player near the left wall, aim left, fire
    client.get_local_player().position = Vector2(30, 800)
    client.get_local_player().aim_direction = Vector2.LEFT

    var input = _build_fire_input(client)
    client.send_input(input)
    ProjectileSpawnRouter.handle_fire(
        client.get_local_player(), input, client._projectile_system,
        {"authoritative": false})

    # Pump until either a WALL despawn or timeout
    var got_wall_despawn := false
    for _i in 40:
        _pump_tick(server, client)
        if client._projectile_system.projectiles.is_empty():
            got_wall_despawn = true
            break

    assert_true(got_wall_despawn, "projectile should hit the left wall and despawn")

func test_projectile_self_collision_after_grace():
    var server = _bootstrap_headless_server()
    var client = _bootstrap_client_connected_to(server)
    _pump_until(server, client, func(): return client.get_local_player_id() != -1)

    var player = client.get_local_player()
    player.position = Vector2(1200, 800)
    player.aim_direction = Vector2.RIGHT
    var input = _build_fire_input(client)
    client.send_input(input)
    ProjectileSpawnRouter.handle_fire(
        player, input, client._projectile_system,
        {"authoritative": false})

    # Burn past spawn grace, then teleport the player into the projectile path
    await get_tree().create_timer(0.15).timeout
    player.position = Vector2(1260, 800)

    # Pump until the server's SELF despawn event arrives
    var got_self_despawn := false
    for _i in 40:
        _pump_tick(server, client)
        # Check for an authoritative projectile getting removed
        var auth_count := 0
        for id in client._projectile_system.projectiles.keys():
            if id > 0:
                auth_count += 1
        if auth_count == 0:
            got_self_despawn = true
            break

    assert_true(got_self_despawn, "projectile should hit shooter after grace expires")

# Helpers assumed to exist from Task 27.
```

- [ ] **Step 2: Run the tests**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_projectile_collision_integration.gd -gexit
```

- [ ] **Step 3: Commit**

```bash
git add godot/tests/network/test_projectile_collision_integration.gd
git commit -m "Integration test: wall and self-collision despawn end-to-end"
```

---

## Task 29: Integration — determinism and two-clients-agree

**Files:**
- Create: `godot/tests/network/test_projectile_determinism.gd`

- [ ] **Step 1: Write the test**

Create `godot/tests/network/test_projectile_determinism.gd`:

```gdscript
extends GutTest

# Two clients simulate the same spawn event independently and must converge
# to the same end position after N ticks.

func test_two_clients_converge_on_same_spawn_event():
    var server = _bootstrap_headless_server()
    var client_a = _bootstrap_client_connected_to(server)
    var client_b = _bootstrap_client_connected_to(server)
    _pump_until(server, client_a, func(): return client_a.get_local_player_id() != -1)
    _pump_until(server, client_b, func(): return client_b.get_local_player_id() != -1)

    # Client A fires
    client_a.get_local_player().position = Vector2(1000, 800)
    client_a.get_local_player().aim_direction = Vector2.RIGHT
    var input = _build_fire_input(client_a)
    client_a.send_input(input)

    # Let the server spawn it and broadcast to both clients
    for _i in 5:
        _pump_tick_multi(server, [client_a, client_b])

    # Find the authoritative projectile on both clients
    var proj_a: ProjectileEntity = _find_first_authoritative(client_a._projectile_system)
    var proj_b: ProjectileEntity = _find_first_authoritative(client_b._projectile_system)
    assert_not_null(proj_a, "client A should have adopted authoritative projectile")
    assert_not_null(proj_b, "client B should have a fresh-spawned remote projectile")

    # Advance both clients independently for 20 frames, then compare
    for _i in 20:
        client_a._projectile_system.advance(1.0 / 60.0, [], [])
        client_b._projectile_system.advance(1.0 / 60.0, [], [])

    assert_true(proj_a.position.distance_to(proj_b.position) < 1.0,
        "two independent client sims of the same projectile must converge within 1 px")

func _find_first_authoritative(sys: ProjectileSystem) -> ProjectileEntity:
    for id in sys.projectiles.keys():
        if id > 0:
            return sys.projectiles[id]
    return null

# Helpers assumed to exist from Task 27, plus _pump_tick_multi which pumps
# the server plus an array of clients together.
```

- [ ] **Step 2: Run the test**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_projectile_determinism.gd -gexit
```

Expected: test passes, proving the deterministic-sim invariant.

- [ ] **Step 3: Commit**

```bash
git add godot/tests/network/test_projectile_determinism.gd
git commit -m "Integration test: two clients converge on same spawn event"
```

---

## Task 30: Integration — server rewind validation

**Files:**
- Create: `godot/tests/network/test_server_rewind.gd`

- [ ] **Step 1: Write the test**

Create `godot/tests/network/test_server_rewind.gd`:

```gdscript
extends GutTest

# Validate that the server's rewind path actually produces a spawn origin
# closer to the shooter's past position than to the current position.

var PlayerPositionHistory = preload("res://simulation/systems/player_position_history.gd")
var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")

func test_server_rewind_uses_past_shooter_position():
    var sys = ProjectileSystemCls.new()
    add_child_autofree(sys)
    var history = PlayerPositionHistory.new()

    # Shooter at (100, 500) at tick 100, moves to (200, 500) by tick 103 (3 ticks later).
    history.record(42, 100, Vector2(100, 500))
    history.record(42, 101, Vector2(133, 500))
    history.record(42, 102, Vector2(166, 500))
    history.record(42, 103, Vector2(200, 500))

    var player = PlayerEntityScene.instantiate()
    add_child_autofree(player)
    player.player_id = 42
    player.position = Vector2(200, 500)   # current authoritative position
    player.aim_direction = Vector2.RIGHT

    var spawn_events: Array = []
    # 100 ms RTT → 50 ms one-way → round(50/33.3) = ~2 ticks rewind
    # So rewound_tick = 103 - 2 = 101, mapping to (133, 500)
    var context = {
        "authoritative": true,
        "rtt_ms": 100,
        "position_history": history,
        "tick": 103,
        "spawn_events": spawn_events,
    }
    var input = {
        "action_flags": MessageTypes.InputActionFlags.FIRE,
        "input_seq": 1,
    }
    ProjectileSpawnRouter.handle_fire(player, input, sys, context)

    assert_eq(spawn_events.size(), 1)
    var origin: Vector2 = spawn_events[0]["origin"]
    # Expected: rewound pos (133, 500) + spawn_offset (40, 0) + fast-forward (30, 0)
    #         = (203, 500)
    var rewound_based_x := 133.0 + 40.0 + 30.0
    var current_based_x  := 200.0 + 40.0 + 30.0
    var err_rewound := abs(origin.x - rewound_based_x)
    var err_current := abs(origin.x - current_based_x)
    assert_lt(err_rewound, err_current,
        "server must rewind shooter position, not use current")
```

- [ ] **Step 2: Run the test**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_server_rewind.gd -gexit
```

- [ ] **Step 3: Commit**

```bash
git add godot/tests/network/test_server_rewind.gd
git commit -m "Integration test: server rewinds shooter position to fire time"
```

---

## Task 31: Full-suite run + manual visual smoke test

**Files:**
- No code changes

- [ ] **Step 1: Run the entire test suite**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: all tests green. If anything fails, fix in place before continuing.

- [ ] **Step 2: Launch server + two browser clients for manual smoke test**

Start the headless server in one terminal:

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://server.tscn
```

Build and serve the web client (whatever your existing workflow is — likely `godot --export-release "Web"` followed by a local HTTP server). Open two browser tabs connecting to the server.

- [ ] **Step 3: Verify the six smoke checks from the spec**

1. Local shooter click → instant projectile, no input lag
2. Remote shooter's projectile trails slightly behind their moving position (physically correct — not a bug)
3. Fire, wait past spawn grace, walk into own projectile → self-collision destroys it
4. Fire at a wall → destroys at wall edge
5. No projectile ever leaves the arena
6. Both clients fire simultaneously → no id collisions, no ghosts, shots visible on both sides

If any check fails, note it, stop, and debug before moving to the next phase.

- [ ] **Step 4: Update DEVLOG.md**

Add a new session entry to `DEVLOG.md` summarizing what shipped. Follow the existing bullet-point style. This is called out explicitly in `CLAUDE.md` as part of PR creation (not commit).

- [ ] **Step 5: Commit devlog**

```bash
git add DEVLOG.md
git commit -m "DEVLOG: projectile networking phase 4 complete"
```

---

## Self-review summary (post-authoring)

After drafting all tasks above, the author walked the spec once more against the plan. Coverage map:

| Spec section | Tasks |
|---|---|
| §2 Tick rate bump | Task 1 |
| §3 Architecture + File layout | Tasks 8, 9, 11, 20, 21, 23, 24, 25 |
| §4 Data structures | Tasks 5, 6, 8, 9, 11, 14, 18 |
| §5 Collision model | Tasks 3, 4, 6, 9, 10 |
| §6 Prediction + reconciliation | Tasks 2, 11, 12, 13, 20, 22, 24 |
| §6 Server-side RTT tracking | Task 19 |
| §7 Network protocol | Tasks 1, 2, 15, 16, 17 |
| §8 View layer | Tasks 25, 26 |
| §9 Tick loop integration | Tasks 21, 24 |
| §10 Testing | Tasks 3, 4, 6, 9, 10, 11, 12, 13, 14, 16, 17, 18, 20, 27, 28, 29, 30 |

All eleven spec sections have at least one task implementing them. No `TBD`, `TODO`, or "implement later" placeholders remain in task bodies. Method names and field names are consistent across tasks — `get_collision_radius`, `DespawnReason`, `spawn_authoritative`/`spawn_predicted`/`adopt_authoritative`/`on_despawn_event`, `action_flags`, `PROJECTILE_SPAWNED`/`PROJECTILE_DESPAWNED` — all match between their definition task and their use in later tasks.
