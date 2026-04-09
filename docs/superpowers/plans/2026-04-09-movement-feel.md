# Movement Feel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the movement half of build-order step 2 — grounded acceleration/friction, a dedicated dodge with i-frames, deadzone+lookahead camera, full juice pass (dodge trail, footstep dust, wall bump, screen shake, walk pulse, i-frame tint), and a gamepad-ready input abstraction. Client and server run identical dt-independent movement math via a shared `advance(dt)` function.

**Architecture:** Continue the Simulation/View split from step 1. All movement logic flows through one canonical `PlayerEntity.advance(dt)` called identically by the server tick, client-side prediction, and reconciliation replay. Tunable movement knobs live in a `MovementParams` Resource. Dodge is a state on `PlayerEntity`, not a separate system. All juice effects are view-layer listeners subscribed to new `EventBus` signals. Input is routed through an `InputProvider` abstraction so a future `GamepadInputProvider` slots in without refactoring.

**Tech Stack:** Godot 4, GDScript, WebSocket networking, GUT for tests. Headless server and browser clients.

**Reference spec:** `docs/superpowers/specs/2026-04-09-movement-feel-design.md`

---

## File Structure

**New files:**
```
godot/shared/movement/movement_params.gd                # Resource: tunable knobs
godot/shared/movement/default_movement_params.tres      # Baseline values
godot/simulation/entities/player_movement_state.gd      # Enum: WALKING/DODGING
godot/simulation/input/input_provider.gd                # Abstract interface
godot/simulation/input/keyboard_mouse_input_provider.gd # Concrete impl
godot/view/world/camera_rig.gd                          # Deadzone + lookahead camera
godot/view/world/camera_rig.tscn
godot/view/effects/dodge_trail.gd                       # Afterimage effect
godot/view/effects/footstep_dust.gd                     # Walk particles
godot/view/effects/wall_bump.gd                         # Collision particles

godot/tests/entities/test_player_entity_advance.gd      # dt-independence canary + math
godot/tests/entities/test_player_dodge_state_machine.gd # Dodge state tests
godot/tests/network/test_reconciliation.gd              # Shared-sim canary
godot/tests/entities/test_movement_params.gd            # Resource swap test
```

**Modified files:**
```
godot/simulation/entities/player_entity.gd        # advance(dt), accel, friction, dodge state
godot/simulation/systems/movement_system.gd       # advance_all(dt), new input dispatch
godot/simulation/event_bus.gd                     # Add dodge/collided/moved signals
godot/simulation/network/input_buffer.gd          # Accepts new input dict format
godot/simulation/network/snapshot.gd              # New per-entity fields + diff
godot/simulation/network/net_client.gd            # New prediction, reconciliation, send
godot/simulation/network/net_server.gd            # advance_all(dt), new input validation
godot/simulation/network/net_message.gd           # Extended input+snapshot encoding
godot/shared/network/message_types.gd             # Update Layout sizes + DODGING flag
godot/view/world/player_view.gd                   # Facing, tint, walk pulse
godot/view/world/player_view.tscn                 # Possibly a Line2D child for facing
godot/view/world/world_view.gd                    # Attach camera, juice effect nodes
godot/view/world/world_view.tscn                  # Add CameraRig + effect nodes
godot/client_main.gd                              # Use InputProvider abstraction
godot/project.godot                               # Add "dodge" input action
godot/tests/entities/test_player_entity.gd        # Update for new API
godot/tests/entities/test_player_wall_collision.gd # Update for new API
godot/tests/entities/test_player_player_collision.gd # Update for new API
godot/tests/systems/test_movement_system.gd       # Update for new API
godot/tests/network/test_net_message.gd           # New fields in encoding
godot/tests/network/test_snapshot.gd              # New fields in diff
godot/tests/network/test_net_client_movement.gd   # Updated prediction flow
godot/tests/network/test_input_buffer.gd          # New input dict shape
```

---

## Task 1: Scaffold foundations — Resource, enum, EventBus signals

**Rationale:** Pure-scaffolding task that lands the new data types and signals. Zero logic changes, nothing else depends on anything yet. Single commit unblocks every later task.

**Files:**
- Create: `godot/shared/movement/movement_params.gd`
- Create: `godot/shared/movement/default_movement_params.tres`
- Create: `godot/simulation/entities/player_movement_state.gd`
- Create: `godot/tests/entities/test_movement_params.gd`
- Modify: `godot/simulation/event_bus.gd` (add 4 new signals)

- [ ] **Step 1: Create the `MovementParams` Resource**

Create `godot/shared/movement/movement_params.gd`:

```gdscript
class_name MovementParams
extends Resource

@export var top_speed: float = 200.0
@export var accel: float = 1800.0              # px/sec² — reach top_speed in ~0.11s
@export var friction: float = 18.0             # exponential coefficient, framerate-independent decay
@export var dodge_speed: float = 700.0         # px/sec during dodge → 140px over 0.2s
@export var dodge_duration: float = 0.2        # seconds
@export var dodge_cooldown: float = 0.7        # seconds, measured from dodge start
@export var dodge_iframe_duration: float = 0.2 # v1: matches dodge_duration
```

- [ ] **Step 2: Create the default `.tres` file**

Create `godot/shared/movement/default_movement_params.tres`:

```
[gd_resource type="Resource" script_class="MovementParams" load_steps=2 format=3]

[ext_resource type="Script" path="res://shared/movement/movement_params.gd" id="1"]

[resource]
script = ExtResource("1")
top_speed = 200.0
accel = 1800.0
friction = 18.0
dodge_speed = 700.0
dodge_duration = 0.2
dodge_cooldown = 0.7
dodge_iframe_duration = 0.2
```

- [ ] **Step 3: Create the `PlayerMovementState` enum constants**

Create `godot/simulation/entities/player_movement_state.gd`:

```gdscript
class_name PlayerMovementState

const WALKING = 0   # input-driven movement (includes idle)
const DODGING = 1   # locked into dodge, no new input accepted
```

- [ ] **Step 4: Add new signals to `EventBus`**

Modify `godot/simulation/event_bus.gd` to add these signals after the existing Combat section:

```gdscript
# Movement
signal player_dodge_started(event: Dictionary)   # entity_id, position, direction
signal player_dodge_ended(event: Dictionary)     # entity_id
signal player_collided(event: Dictionary)        # entity_id, position, normal, velocity
signal player_moved(event: Dictionary)           # entity_id, position, velocity
```

- [ ] **Step 5: Add the DODGING flag to `MessageTypes.EntityFlags`**

Modify `godot/shared/network/message_types.gd`, change the `EntityFlags` enum to:

```gdscript
enum EntityFlags {
    NONE = 0,
    MOVING = 1,       # Entity is currently moving
    REMOVED = 2,      # Entity was removed (delta only)
    DODGING = 4,      # Entity is in the DODGING state (for view-side trail trigger)
}
```

- [ ] **Step 6: Write the MovementParams test**

Create `godot/tests/entities/test_movement_params.gd`:

```gdscript
extends GutTest

const MovementParams = preload("res://shared/movement/movement_params.gd")

func test_default_values():
    var params = MovementParams.new()
    assert_eq(params.top_speed, 200.0)
    assert_almost_eq(params.accel, 1800.0, 0.01)
    assert_almost_eq(params.friction, 18.0, 0.01)
    assert_almost_eq(params.dodge_speed, 700.0, 0.01)
    assert_almost_eq(params.dodge_duration, 0.2, 0.001)
    assert_almost_eq(params.dodge_cooldown, 0.7, 0.001)

func test_default_tres_loads():
    var params = load("res://shared/movement/default_movement_params.tres")
    assert_not_null(params, "default_movement_params.tres should load")
    assert_eq(params.top_speed, 200.0)
    assert_almost_eq(params.dodge_duration, 0.2, 0.001)

func test_runtime_swap():
    # Proves that swapping params at runtime works — future surface/gear integration
    var base = MovementParams.new()
    var slowed = MovementParams.new()
    slowed.top_speed = 50.0
    assert_eq(base.top_speed, 200.0)
    assert_eq(slowed.top_speed, 50.0)
    # Same class, distinct instances — the runtime-swap pattern is just reassignment
```

- [ ] **Step 7: Run the new test**

Run: `cd godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_movement_params.gd -gexit`
Expected: 3 tests pass, no failures.

- [ ] **Step 8: Commit**

```bash
git add godot/shared/movement godot/simulation/entities/player_movement_state.gd godot/simulation/event_bus.gd godot/shared/network/message_types.gd godot/tests/entities/test_movement_params.gd
git commit -m "Scaffold MovementParams Resource, PlayerMovementState enum, EventBus movement signals"
```

---

## Task 2: PlayerEntity.advance(dt) — WALKING state + dt-independence canary

**Rationale:** This is the biggest and most critical task in the plan. It establishes the canonical `advance(dt)` shared by client and server, with the dt-independence canary as a regression guard against someone accidentally writing `velocity *= 0.9`. Keeps callers (MovementSystem, NetClient, NetServer) happy via a thin renaming pass.

**Files:**
- Modify: `godot/simulation/entities/player_entity.gd` — replace `tick`/`move_delta` with `advance(dt)`, add fields for params/state/move_input/aim_direction
- Modify: `godot/simulation/systems/movement_system.gd` — rename `tick_all` → `advance_all(dt)`
- Modify: `godot/simulation/network/net_server.gd` — call `advance_all(dt)` instead of `tick_all()`
- Modify: `godot/simulation/network/net_client.gd` — call `advance(delta)` instead of `move_delta(delta)`; call `advance(TICK_INTERVAL)` in reconciliation instead of `tick()`
- Create: `godot/tests/entities/test_player_entity_advance.gd` — dt-independence canary + math tests
- Modify: existing tests (`test_player_entity.gd`, `test_player_wall_collision.gd`, `test_player_player_collision.gd`, `test_movement_system.gd`, `test_net_client_movement.gd`) to match the new API

**Note on input signature:** In this task `apply_input(direction: Vector2)` still takes a Vector2 (no dict yet). The dict expansion lands in Task 4. This keeps the refactor scoped.

- [ ] **Step 1: Write the failing dt-independence canary test**

Create `godot/tests/entities/test_player_entity_advance.gd`:

```gdscript
extends GutTest

var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
const MovementParams = preload("res://shared/movement/movement_params.gd")

var _params: MovementParams

func before_each():
    _params = MovementParams.new()

func _make_player() -> PlayerEntity:
    var p = PlayerEntityScene.instantiate()
    add_child_autofree(p)
    p.initialize(1, Vector2(100.0, 100.0))
    p.params = _params
    return p

func test_accel_reaches_top_speed():
    var p = _make_player()
    p.apply_input(Vector2(1.0, 0.0))
    # At accel=1800, top_speed=200, time to top is ~0.111s. Advance 0.2s in small steps.
    for i in range(20):
        p.advance(0.01)
    assert_almost_eq(p.velocity.x, 200.0, 1.0, "Should reach top_speed within 0.2s")

func test_friction_decays_to_near_zero_after_release():
    var p = _make_player()
    p.velocity = Vector2(200.0, 0.0)
    p.apply_input(Vector2.ZERO)
    # Exponential friction at coeff=18 halves in ~38ms. After 0.3s should be < 1.
    for i in range(30):
        p.advance(0.01)
    assert_lt(p.velocity.length(), 1.0, "Velocity should decay to near-zero after release")

func test_dt_independence_canary():
    # THE CANARY: running advance(0.1) once vs advance(0.01) ten times must converge.
    # If this fails, someone wrote framerate-dependent math (velocity *= 0.9 etc).
    var coarse = _make_player()
    coarse.apply_input(Vector2(1.0, 0.0))
    coarse.advance(0.1)

    var fine = _make_player()
    fine.apply_input(Vector2(1.0, 0.0))
    for i in range(10):
        fine.advance(0.01)

    assert_almost_eq(coarse.velocity.x, fine.velocity.x, 0.5,
        "Velocity must be dt-independent — coarse vs fine must converge")
    assert_almost_eq(coarse.position.x, fine.position.x, 0.5,
        "Position must be dt-independent — coarse vs fine must converge")

func test_idle_stays_at_rest():
    var p = _make_player()
    var start = p.position
    for i in range(20):
        p.advance(0.05)
    assert_eq(p.position, start, "Idle player should not drift")
    assert_eq(p.velocity, Vector2.ZERO)

func test_diagonal_input_normalizes():
    var p = _make_player()
    p.apply_input(Vector2(1.0, 1.0))
    # Advance long enough to reach top speed
    for i in range(30):
        p.advance(0.01)
    assert_almost_eq(p.velocity.length(), 200.0, 1.0,
        "Diagonal movement should not exceed top_speed")

func test_advance_moves_position_with_velocity():
    var p = _make_player()
    p.apply_input(Vector2(1.0, 0.0))
    # Pre-set velocity to skip accel ramp
    p.velocity = Vector2(200.0, 0.0)
    var before = p.position.x
    p.advance(0.1)
    # Expect ~20 px over 0.1s at 200px/s (minus sub-frame rounding)
    assert_almost_eq(p.position.x - before, 20.0, 1.0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_player_entity_advance.gd -gexit`
Expected: Tests fail because `advance()` and `params` don't exist yet on PlayerEntity.

- [ ] **Step 3: Rewrite `PlayerEntity` to use `advance(dt)`**

Replace the contents of `godot/simulation/entities/player_entity.gd`:

```gdscript
class_name PlayerEntity
extends CharacterBody2D

var player_id: int = -1
var last_processed_input_seq: int = 0

# Movement state
var params: MovementParams = preload("res://shared/movement/default_movement_params.tres")
var move_input: Vector2 = Vector2.ZERO       # latest WASD direction (raw, not normalized)
var aim_direction: Vector2 = Vector2.RIGHT   # latest aim unit vector (used later)
var state: int = PlayerMovementState.WALKING


func initialize(id: int, spawn_position: Vector2) -> void:
    player_id = id
    position = spawn_position


# Ingest: called by MovementSystem when dequeuing inputs.
# In Task 4 this signature expands to apply_input(Dictionary). For this task
# it still takes a Vector2 to keep the refactor scoped.
func apply_input(direction: Vector2) -> void:
    move_input = direction


# Canonical movement step. Called by:
#   - Server tick  → advance(TICK_INTERVAL)
#   - Client prediction (per display frame) → advance(frame_delta)
#   - Client reconciliation replay → advance(TICK_INTERVAL) once per pending input
# MUST be dt-independent — same result regardless of how dt is chunked.
func advance(dt: float) -> void:
    # Compute target velocity from input + state
    match state:
        PlayerMovementState.WALKING:
            if move_input.length_squared() > 0.001:
                var target = move_input.normalized() * params.top_speed
                velocity = velocity.move_toward(target, params.accel * dt)
            else:
                # Exponential decay — dt-independent, framerate-independent
                velocity *= exp(-params.friction * dt)
                if velocity.length_squared() < 0.01:
                    velocity = Vector2.ZERO
        # DODGING state handled in Task 5

    # Integrate position with collision
    var motion: Vector2 = velocity * dt
    var collision = move_and_collide(motion)
    if collision:
        var remainder = collision.get_remainder()
        move_and_collide(remainder.slide(collision.get_normal()))
        EventBus.player_collided.emit({
            "entity_id": player_id,
            "position": position,
            "normal": collision.get_normal(),
            "velocity": velocity,
        })

    # Movement event (gated to avoid idle spam)
    if velocity.length_squared() > 1.0:
        EventBus.player_moved.emit({
            "entity_id": player_id,
            "position": position,
            "velocity": velocity,
        })


func to_snapshot_data() -> Dictionary:
    # NOTE: Task 6 extends this with velocity, aim_direction, state, dodge_time_remaining.
    # This task only renames fields; the snapshot binary format is unchanged.
    var flags = MessageTypes.EntityFlags.NONE
    if velocity.length_squared() > 0.0:
        flags = MessageTypes.EntityFlags.MOVING
    return {
        "entity_id": player_id,
        "position": position,
        "flags": flags,
        "last_input_seq": last_processed_input_seq,
    }
```

- [ ] **Step 4: Rename `MovementSystem.tick_all()` to `advance_all(dt)`**

Modify `godot/simulation/systems/movement_system.gd`. Replace `tick_all` with:

```gdscript
func advance_all(dt: float) -> void:
    for player_id in _players:
        _players[player_id].advance(dt)
```

Delete the old `tick_all()` function. `process_inputs_for_player()` stays unchanged for this task (it still iterates `input["direction"]`).

- [ ] **Step 5: Update `NetServer` to call `advance_all(dt)`**

In `godot/simulation/network/net_server.gd`, find `_server_tick()` (around line 250). Change:

```gdscript
# OLD:
_movement_system.tick_all()

# NEW:
var tick_dt = MessageTypes.TICK_INTERVAL_MS / 1000.0
_movement_system.advance_all(tick_dt)
```

- [ ] **Step 6: Update `NetClient` to call `advance(dt)` instead of `move_delta`/`tick`**

In `godot/simulation/network/net_client.gd`:

1. Replace the frame-rate prediction block (around line 67) with:
```gdscript
# Frame-rate prediction: run canonical advance() at display framerate.
# dt-independent math means client and server produce the same result.
if _local_player != null:
    _local_player.apply_input(input_direction)
    _local_player.advance(delta)
```

2. Replace the reconciliation replay loop (around line 210) with:
```gdscript
# Replay unacknowledged inputs through the canonical advance function,
# using tick interval as dt to match how the server processed them.
var tick_dt: float = MessageTypes.TICK_INTERVAL_MS / 1000.0
for pending in _pending_inputs:
    _local_player.apply_input(pending["direction"])
    _local_player.advance(tick_dt)
```

- [ ] **Step 7: Update existing tests to match the new API**

The following existing tests reference `tick()`, `move_delta()`, or `PlayerEntity.SPEED` directly and must be updated. Each file needs minor edits — the assertions mostly still work, just the method calls change.

**`godot/tests/entities/test_player_entity.gd`:**
- Remove `test_apply_input_sets_velocity` and `test_apply_input_normalizes_diagonal` (these tested the old instant-velocity behavior; equivalent coverage now lives in `test_player_entity_advance.gd`)
- Remove `test_apply_zero_input_stops` (friction decay is now tested in advance tests)
- Remove `test_move_delta_moves_by_frame_delta` — replaced by the new advance test
- Keep `test_initial_state`, `test_initialize_sets_id_and_position`, `test_to_snapshot_data*` (these still work)

**`godot/tests/entities/test_player_wall_collision.gd`:**
- Replace every `_player.tick()` with `_player.advance(TICK_S)`
- The tests work identically because the player still reaches and holds against the wall

**`godot/tests/entities/test_player_player_collision.gd`:**
- Same treatment: any `tick()` → `advance(TICK_S)`. (If file uses `move_delta`, replace with `advance(delta)`.)

**`godot/tests/systems/test_movement_system.gd`:**
- Replace `test_tick_all_calls_move_and_slide` body:
```gdscript
func test_advance_all_moves_players():
    _player.apply_input(Vector2(1.0, 0.0))
    var pos_before = _player.position
    var tick_dt = MessageTypes.TICK_INTERVAL_MS / 1000.0
    # Accel needs a few ticks to build up movement
    for i in range(3):
        _system.advance_all(tick_dt)
    assert_ne(_player.position, pos_before, "Position should change after advance_all")
```
- Update `test_process_inputs_applies_direction`: `apply_input` no longer sets velocity directly. Replace assertion with: `assert_eq(_player.move_input, Vector2(1.0, 0.0))`
- Update `test_process_multiple_inputs_applies_last`: assertion becomes `assert_eq(_player.move_input, Vector2(0.0, -1.0))`
- Update `test_process_empty_inputs_keeps_last_velocity`: change assertion to `assert_eq(_player.move_input, Vector2(1.0, 0.0))` (we now track input, not velocity, at the apply step)

**`godot/tests/network/test_net_client_movement.gd`:**
- Any direct reference to `move_delta` or `tick` on a player becomes `advance(dt)`.

- [ ] **Step 8: Run the full test suite**

Run: `cd godot && godot --headless -s addons/gut/gut_cmdln.gd -gexit`
Expected: All tests pass, including the new `test_player_entity_advance.gd`. If the dt-independence canary fails, inspect the `velocity *= exp(...)` line — it must be exactly `exp(-params.friction * dt)`, not a constant multiplier.

- [ ] **Step 9: Commit**

```bash
git add godot/simulation/entities/player_entity.gd godot/simulation/systems/movement_system.gd godot/simulation/network/net_server.gd godot/simulation/network/net_client.gd godot/tests/
git commit -m "Introduce PlayerEntity.advance(dt) shared by client and server

- Single canonical movement step replaces separate tick()/move_delta()
- Framerate-independent accel + exponential friction (dt-independent math)
- MovementSystem.tick_all → advance_all(dt)
- NetServer and NetClient both call advance(dt) — same code path
- Adds dt-independence canary test as regression guard"
```

---

## Task 3: Extend input contract — aim_direction field, dict-based apply_input

**Rationale:** Expands `apply_input` from `Vector2` to `Dictionary` and plumbs `aim_direction` through the whole network stack. This is the prerequisite for dodge (Task 5) and the facing indicator (Task 11). Input message size grows from 17 bytes to 25 bytes (dodge_pressed lands in Task 6, not this task, to keep the scope focused).

**Files:**
- Modify: `godot/simulation/entities/player_entity.gd` — `apply_input(Dictionary)`, store `aim_direction`
- Modify: `godot/simulation/systems/movement_system.gd` — dispatch new dict to `apply_input`
- Modify: `godot/simulation/network/net_message.gd` — encode/decode aim_direction
- Modify: `godot/shared/network/message_types.gd` — update `INPUT_SIZE`
- Modify: `godot/simulation/network/net_server.gd` — validate aim_direction, pass through input_buffer
- Modify: `godot/simulation/network/net_client.gd` — build new input dict in `_send_input` and pending queue
- Modify: `godot/tests/network/test_net_message.gd`, `godot/tests/network/test_input_buffer.gd`, `godot/tests/systems/test_movement_system.gd` — new dict shape

- [ ] **Step 1: Update `INPUT_SIZE` in `MessageTypes.Layout`**

Modify `godot/shared/network/message_types.gd`:

```gdscript
class Layout:
    const SNAPSHOT_HEADER_SIZE = 7
    const ENTITY_SIZE = 15    # unchanged this task (Task 6 grows it)
    # Player input: [msg_type:u8][tick:u32][move_x:f32][move_y:f32]
    #               [aim_x:f32][aim_y:f32][input_seq:u32]
    const INPUT_SIZE = 25
    const ACK_SIZE = 5
```

- [ ] **Step 2: Update `NetMessage` player-input encoding**

Modify `godot/simulation/network/net_message.gd`. Replace `_encode_player_input` and `_decode_player_input`:

```gdscript
static func _encode_player_input(msg: Dictionary) -> PackedByteArray:
    var buf = PackedByteArray()
    buf.resize(MessageTypes.Layout.INPUT_SIZE)
    var move_dir: Vector2 = msg["move_direction"]
    var aim_dir: Vector2 = msg["aim_direction"]
    buf.encode_u8(0, MessageTypes.Binary.PLAYER_INPUT)
    buf.encode_u32(1, msg["tick"])
    buf.encode_float(5, move_dir.x)
    buf.encode_float(9, move_dir.y)
    buf.encode_float(13, aim_dir.x)
    buf.encode_float(17, aim_dir.y)
    buf.encode_u32(21, msg["input_seq"])
    return buf


static func _decode_player_input(bytes: PackedByteArray) -> Variant:
    if bytes.size() < MessageTypes.Layout.INPUT_SIZE:
        return null
    return {
        "type": MessageTypes.Binary.PLAYER_INPUT,
        "tick": bytes.decode_u32(1),
        "move_direction": Vector2(bytes.decode_float(5), bytes.decode_float(9)),
        "aim_direction": Vector2(bytes.decode_float(13), bytes.decode_float(17)),
        "input_seq": bytes.decode_u32(21),
    }
```

- [ ] **Step 3: Change `PlayerEntity.apply_input` signature to take a Dictionary**

Modify `godot/simulation/entities/player_entity.gd`:

```gdscript
func apply_input(input: Dictionary) -> void:
    move_input = input.get("move_direction", Vector2.ZERO)
    aim_direction = input.get("aim_direction", aim_direction)  # keep old if missing
    if input.has("input_seq") and input["input_seq"] > last_processed_input_seq:
        last_processed_input_seq = input["input_seq"]
```

- [ ] **Step 4: Update `MovementSystem.process_inputs_for_player` to dispatch the dict**

Modify `godot/simulation/systems/movement_system.gd`:

```gdscript
func process_inputs_for_player(player_id: int, inputs: Array) -> void:
    if not _players.has(player_id):
        return
    var player: PlayerEntity = _players[player_id]
    for input in inputs:
        player.apply_input(input)
```

The key change: we no longer unwrap `input["direction"]` — we pass the whole dict through. `apply_input` handles extraction.

- [ ] **Step 5: Update `NetServer._handle_binary_message` to validate both vectors**

In `godot/simulation/network/net_server.gd`, find `_handle_binary_message` (around line 209). Replace the `PLAYER_INPUT` case body:

```gdscript
MessageTypes.Binary.PLAYER_INPUT:
    var move_dir: Vector2 = msg["move_direction"]
    var aim_dir: Vector2 = msg["aim_direction"]
    if not (is_finite(move_dir.x) and is_finite(move_dir.y) and is_finite(aim_dir.x) and is_finite(aim_dir.y)):
        return  # Reject non-finite input
    if move_dir.length_squared() > 2.0 or aim_dir.length_squared() > 2.0:
        return  # Reject absurd values (aim is expected to be a unit vector)
    _input_buffer.add_input(player_id, msg)
```

- [ ] **Step 6: Update `NetClient._send_input` to produce the new dict**

In `godot/simulation/network/net_client.gd`:

1. Add a new field near the other state fields:
```gdscript
var aim_direction: Vector2 = Vector2.RIGHT  # set by caller each frame
```

2. Replace `_send_input`:
```gdscript
func _send_input():
    if _local_player == null or _local_player_id == -1:
        return

    _input_seq += 1

    var input = {
        "seq": _input_seq,
        "move_direction": input_direction,
        "aim_direction": aim_direction,
    }
    _pending_inputs.append(input)
    if _pending_inputs.size() > MAX_PENDING_INPUTS:
        _pending_inputs = _pending_inputs.slice(-MAX_PENDING_INPUTS)

    var msg = {
        "type": MessageTypes.Binary.PLAYER_INPUT,
        "tick": _server_tick,
        "move_direction": input_direction,
        "aim_direction": aim_direction,
        "input_seq": _input_seq,
    }
    _ws.send(NetMessage.encode(msg))
```

3. In `_process`, where the local player is updated each frame, pass both fields into the player. Replace:
```gdscript
if _local_player != null:
    _local_player.apply_input(input_direction)
    _local_player.advance(delta)
```
with:
```gdscript
if _local_player != null:
    _local_player.apply_input({
        "move_direction": input_direction,
        "aim_direction": aim_direction,
    })
    _local_player.advance(delta)
```

4. In `_reconcile_local_player`, the replay loop passes pending inputs as dicts — just pass the pending dict directly:
```gdscript
for pending in _pending_inputs:
    _local_player.apply_input({
        "move_direction": pending["move_direction"],
        "aim_direction": pending["aim_direction"],
    })
    _local_player.advance(tick_dt)
```

- [ ] **Step 7: Update `test_net_message.gd` for new encoding**

In `godot/tests/network/test_net_message.gd`, find tests that encode/decode `PLAYER_INPUT`. Replace the test that round-trips the old format with:

```gdscript
func test_player_input_round_trip():
    var msg = {
        "type": MessageTypes.Binary.PLAYER_INPUT,
        "tick": 42,
        "move_direction": Vector2(0.6, -0.8),
        "aim_direction": Vector2(1.0, 0.0),
        "input_seq": 1234,
    }
    var bytes = NetMessage.encode(msg)
    assert_eq(bytes.size(), MessageTypes.Layout.INPUT_SIZE)
    var decoded = NetMessage.decode_binary(bytes)
    assert_eq(decoded["tick"], 42)
    assert_almost_eq(decoded["move_direction"].x, 0.6, 0.001)
    assert_almost_eq(decoded["move_direction"].y, -0.8, 0.001)
    assert_almost_eq(decoded["aim_direction"].x, 1.0, 0.001)
    assert_almost_eq(decoded["aim_direction"].y, 0.0, 0.001)
    assert_eq(decoded["input_seq"], 1234)
```

- [ ] **Step 8: Update `test_movement_system.gd` for dict inputs**

In `godot/tests/systems/test_movement_system.gd`, update the input setup in each test from the old shape to the new one. For example:

```gdscript
func test_process_inputs_applies_direction():
    var inputs = [
        {"input_seq": 1, "move_direction": Vector2(1.0, 0.0), "aim_direction": Vector2.RIGHT, "tick": 10},
    ]
    _system.process_inputs_for_player(1, inputs)
    assert_eq(_player.move_input, Vector2(1.0, 0.0))
    assert_eq(_player.aim_direction, Vector2.RIGHT)
```

Update the other test functions similarly — any dict with `"direction"` becomes a dict with `"move_direction"` and `"aim_direction"`.

- [ ] **Step 9: Update `test_input_buffer.gd` for dict inputs**

In `godot/tests/network/test_input_buffer.gd`, update any input dicts to the new shape (replace `"direction"` with `"move_direction"`, add `"aim_direction"`). The buffer itself doesn't care about the shape — it just stores and drains arrays — so only the test data needs updating.

- [ ] **Step 10: Update `test_net_client_movement.gd` if present**

Any reference to `{"direction": ...}` in pending_inputs arrays becomes `{"move_direction": ..., "aim_direction": ...}`. The test's intent is the same.

- [ ] **Step 11: Run the full test suite**

Run: `cd godot && godot --headless -s addons/gut/gut_cmdln.gd -gexit`
Expected: All tests pass. If `test_player_input_round_trip` fails on size, check the `INPUT_SIZE` constant. If decode asserts fail, verify offsets 5/9/13/17/21 in `_decode_player_input`.

- [ ] **Step 12: Commit**

```bash
git add godot/simulation/entities/player_entity.gd godot/simulation/systems/movement_system.gd godot/simulation/network/ godot/shared/network/message_types.gd godot/tests/
git commit -m "Extend input contract with aim_direction, dict-based apply_input

- apply_input now takes Dictionary {move_direction, aim_direction, input_seq}
- NetMessage encoding extends INPUT_SIZE from 17 to 25 bytes
- Server validates both vectors; client sends both per tick"
```

---

## Task 4: Dodge state machine on PlayerEntity

**Rationale:** Adds the dodge state, transitions, and integration into `advance()`. Pure simulation — no networking changes yet. Covered by a dedicated state-machine test file.

**Files:**
- Modify: `godot/simulation/entities/player_entity.gd` — dodge fields, `can_dodge`, `start_dodge`, DODGING branch in `advance`
- Create: `godot/tests/entities/test_player_dodge_state_machine.gd`

- [ ] **Step 1: Write the failing dodge state machine tests**

Create `godot/tests/entities/test_player_dodge_state_machine.gd`:

```gdscript
extends GutTest

var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
const MovementParams = preload("res://shared/movement/movement_params.gd")
const PlayerMovementState = preload("res://simulation/entities/player_movement_state.gd")

var _params: MovementParams

func before_each():
    _params = MovementParams.new()

func _make_player() -> PlayerEntity:
    var p = PlayerEntityScene.instantiate()
    add_child_autofree(p)
    p.initialize(1, Vector2(240.0, 160.0))  # arena center, away from walls
    p.params = _params
    return p

func test_default_state_is_walking():
    var p = _make_player()
    assert_eq(p.state, PlayerMovementState.WALKING)
    assert_true(p.can_dodge())

func test_dodge_from_walking_with_move_direction():
    var p = _make_player()
    p.move_input = Vector2(1.0, 0.0)
    p.start_dodge()
    assert_eq(p.state, PlayerMovementState.DODGING)
    assert_eq(p.dodge_direction, Vector2(1.0, 0.0))
    assert_almost_eq(p.dodge_time_remaining, _params.dodge_duration, 0.001)
    assert_almost_eq(p.dodge_cooldown_remaining, _params.dodge_cooldown, 0.001)

func test_dodge_falls_back_to_aim_when_no_move_input():
    var p = _make_player()
    p.move_input = Vector2.ZERO
    p.aim_direction = Vector2(0.0, 1.0)  # aiming down
    p.start_dodge()
    assert_eq(p.dodge_direction, Vector2(0.0, 1.0))

func test_cannot_dodge_while_dodging():
    var p = _make_player()
    p.move_input = Vector2(1.0, 0.0)
    p.start_dodge()
    assert_false(p.can_dodge(), "Should not be able to dodge while DODGING")

func test_cannot_dodge_while_cooldown_remains():
    var p = _make_player()
    p.move_input = Vector2(1.0, 0.0)
    p.start_dodge()
    # Advance past dodge duration but not past cooldown
    for i in range(3):
        p.advance(_params.dodge_duration * 0.5)
    assert_eq(p.state, PlayerMovementState.WALKING, "Dodge should have ended")
    assert_gt(p.dodge_cooldown_remaining, 0.0, "Cooldown should still be active")
    assert_false(p.can_dodge())

func test_dodge_ends_after_duration():
    var p = _make_player()
    p.move_input = Vector2(1.0, 0.0)
    p.start_dodge()
    # Advance just past the dodge duration
    p.advance(_params.dodge_duration + 0.001)
    assert_eq(p.state, PlayerMovementState.WALKING)

func test_can_dodge_again_after_cooldown():
    var p = _make_player()
    p.move_input = Vector2(1.0, 0.0)
    p.start_dodge()
    # Advance past full cooldown
    p.advance(_params.dodge_cooldown + 0.01)
    assert_true(p.can_dodge())

func test_cooldown_ticks_down_during_dodge():
    var p = _make_player()
    p.move_input = Vector2(1.0, 0.0)
    p.start_dodge()
    var cd_before = p.dodge_cooldown_remaining
    p.advance(0.05)
    assert_lt(p.dodge_cooldown_remaining, cd_before,
        "Cooldown should tick down during DODGING state")

func test_dodge_emits_event():
    var p = _make_player()
    p.move_input = Vector2(1.0, 0.0)
    watch_signals(EventBus)
    p.start_dodge()
    assert_signal_emitted(EventBus, "player_dodge_started")

func test_dodge_respects_walls():
    # Requires the arena to be present so the wall is actually there
    var arena = preload("res://shared/world/arena.tscn").instantiate()
    add_child_autofree(arena)
    var p = _make_player()
    p.position = Vector2(470.0, 160.0)  # near right wall
    p.move_input = Vector2(1.0, 0.0)
    p.start_dodge()
    # Dodge a full duration of motion
    for i in range(10):
        p.advance(_params.dodge_duration / 10.0)
    assert_lt(p.position.x, 480.0, "Dodge must not phase through walls")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_player_dodge_state_machine.gd -gexit`
Expected: All 10 tests fail because `can_dodge`, `start_dodge`, and dodge fields don't exist yet.

- [ ] **Step 3: Add dodge state and methods to `PlayerEntity`**

Modify `godot/simulation/entities/player_entity.gd`. Add these fields after the existing movement state block:

```gdscript
# Dodge state
var dodge_direction: Vector2 = Vector2.ZERO
var dodge_time_remaining: float = 0.0
var dodge_cooldown_remaining: float = 0.0
```

Add these methods after `apply_input`:

```gdscript
# Public — NetClient prediction calls this to gate its own dodge starts
func can_dodge() -> bool:
    return state == PlayerMovementState.WALKING and dodge_cooldown_remaining <= 0.0


func start_dodge() -> void:
    var dir: Vector2
    if move_input.length_squared() > 0.01:
        dir = move_input.normalized()
    else:
        dir = aim_direction
    state = PlayerMovementState.DODGING
    dodge_direction = dir
    dodge_time_remaining = params.dodge_duration
    dodge_cooldown_remaining = params.dodge_cooldown
    EventBus.player_dodge_started.emit({
        "entity_id": player_id,
        "position": position,
        "direction": dir,
    })
```

Update `apply_input` to honor dodge requests in the dict:

```gdscript
func apply_input(input: Dictionary) -> void:
    move_input = input.get("move_direction", Vector2.ZERO)
    aim_direction = input.get("aim_direction", aim_direction)
    if input.get("dodge_pressed", false) and can_dodge():
        start_dodge()
    if input.has("input_seq") and input["input_seq"] > last_processed_input_seq:
        last_processed_input_seq = input["input_seq"]
```

Update `advance(dt)` to handle the DODGING state and tick cooldowns:

```gdscript
func advance(dt: float) -> void:
    # Tick cooldown regardless of state
    if dodge_cooldown_remaining > 0.0:
        dodge_cooldown_remaining = max(0.0, dodge_cooldown_remaining - dt)

    # State-specific velocity computation
    match state:
        PlayerMovementState.WALKING:
            if move_input.length_squared() > 0.001:
                var target = move_input.normalized() * params.top_speed
                velocity = velocity.move_toward(target, params.accel * dt)
            else:
                velocity *= exp(-params.friction * dt)
                if velocity.length_squared() < 0.01:
                    velocity = Vector2.ZERO

        PlayerMovementState.DODGING:
            velocity = dodge_direction * params.dodge_speed
            dodge_time_remaining -= dt
            if dodge_time_remaining <= 0.0:
                state = PlayerMovementState.WALKING
                EventBus.player_dodge_ended.emit({"entity_id": player_id})

    # Integrate position with collision
    var motion: Vector2 = velocity * dt
    var collision = move_and_collide(motion)
    if collision:
        var remainder = collision.get_remainder()
        move_and_collide(remainder.slide(collision.get_normal()))
        EventBus.player_collided.emit({
            "entity_id": player_id,
            "position": position,
            "normal": collision.get_normal(),
            "velocity": velocity,
        })

    if velocity.length_squared() > 1.0:
        EventBus.player_moved.emit({
            "entity_id": player_id,
            "position": position,
            "velocity": velocity,
        })
```

- [ ] **Step 4: Run the dodge tests and confirm they pass**

Run: `cd godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_player_dodge_state_machine.gd -gexit`
Expected: All 10 tests pass.

- [ ] **Step 5: Run the full test suite to confirm no regressions**

Run: `cd godot && godot --headless -s addons/gut/gut_cmdln.gd -gexit`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add godot/simulation/entities/player_entity.gd godot/tests/entities/test_player_dodge_state_machine.gd
git commit -m "Add dodge state machine to PlayerEntity

- DODGING state with direction, time remaining, cooldown
- Dodge direction: move_input if held, else aim_direction (Hades pattern)
- can_dodge() gate, start_dodge() commit, advance() branch
- Emits player_dodge_started/ended events with full context"
```

---

## Task 5: Wire dodge through the network — input + snapshot + reconciliation

**Rationale:** Lands all dodge-related network plumbing in one coherent commit. Without this task, the dodge works client-side but the server never hears about it, so the server snapshot overwrites the predicted dodge on every tick.

**Files:**
- Modify: `godot/shared/network/message_types.gd` — `INPUT_SIZE` grows by 1 (dodge_pressed byte); `ENTITY_SIZE` grows for new snapshot fields
- Modify: `godot/simulation/network/net_message.gd` — encode/decode dodge_pressed + new snapshot fields
- Modify: `godot/simulation/network/snapshot.gd` — diff includes new fields
- Modify: `godot/simulation/entities/player_entity.gd` — `to_snapshot_data()` emits new fields
- Modify: `godot/simulation/network/net_client.gd` — send `dodge_pressed`, predict dodge, reconcile full dodge state
- Modify: `godot/tests/network/test_net_message.gd`, `godot/tests/network/test_snapshot.gd`

- [ ] **Step 1: Update Layout sizes in MessageTypes**

Modify `godot/shared/network/message_types.gd`:

```gdscript
class Layout:
    const SNAPSHOT_HEADER_SIZE = 7
    # Per-entity: [entity_id:u16][x:f32][y:f32][flags:u8][last_input_seq:u32]
    #             [vx:f32][vy:f32][aim_x:f32][aim_y:f32][state:u8]
    #             [dodge_time_remaining:f32]
    const ENTITY_SIZE = 36
    # Player input: [msg_type:u8][tick:u32][move_x:f32][move_y:f32]
    #               [aim_x:f32][aim_y:f32][dodge_pressed:u8][input_seq:u32]
    const INPUT_SIZE = 26
    const ACK_SIZE = 5
```

- [ ] **Step 2: Extend player input encoding with dodge_pressed**

Modify `_encode_player_input` and `_decode_player_input` in `godot/simulation/network/net_message.gd`:

```gdscript
static func _encode_player_input(msg: Dictionary) -> PackedByteArray:
    var buf = PackedByteArray()
    buf.resize(MessageTypes.Layout.INPUT_SIZE)
    var move_dir: Vector2 = msg["move_direction"]
    var aim_dir: Vector2 = msg["aim_direction"]
    buf.encode_u8(0, MessageTypes.Binary.PLAYER_INPUT)
    buf.encode_u32(1, msg["tick"])
    buf.encode_float(5, move_dir.x)
    buf.encode_float(9, move_dir.y)
    buf.encode_float(13, aim_dir.x)
    buf.encode_float(17, aim_dir.y)
    buf.encode_u8(21, 1 if msg.get("dodge_pressed", false) else 0)
    buf.encode_u32(22, msg["input_seq"])
    return buf


static func _decode_player_input(bytes: PackedByteArray) -> Variant:
    if bytes.size() < MessageTypes.Layout.INPUT_SIZE:
        return null
    return {
        "type": MessageTypes.Binary.PLAYER_INPUT,
        "tick": bytes.decode_u32(1),
        "move_direction": Vector2(bytes.decode_float(5), bytes.decode_float(9)),
        "aim_direction": Vector2(bytes.decode_float(13), bytes.decode_float(17)),
        "dodge_pressed": bytes.decode_u8(21) != 0,
        "input_seq": bytes.decode_u32(22),
    }
```

- [ ] **Step 3: Extend snapshot entity encoding**

In the same file, replace `_encode_snapshot` and `_decode_snapshot` with versions that handle the new per-entity layout:

```gdscript
static func _encode_snapshot(msg: Dictionary) -> PackedByteArray:
    var entities: Array = msg["entities"]
    var header_size = MessageTypes.Layout.SNAPSHOT_HEADER_SIZE
    var entity_size = MessageTypes.Layout.ENTITY_SIZE
    var buf = PackedByteArray()
    buf.resize(header_size + entities.size() * entity_size)
    buf.encode_u8(0, msg["type"])
    buf.encode_u32(1, msg["tick"])
    buf.encode_u16(5, entities.size())
    for i in range(entities.size()):
        var offset = header_size + i * entity_size
        var ent = entities[i]
        var pos: Vector2 = ent["position"]
        var vel: Vector2 = ent.get("velocity", Vector2.ZERO)
        var aim: Vector2 = ent.get("aim_direction", Vector2.RIGHT)
        buf.encode_u16(offset, ent["entity_id"])
        buf.encode_float(offset + 2, pos.x)
        buf.encode_float(offset + 6, pos.y)
        buf.encode_u8(offset + 10, ent["flags"])
        buf.encode_u32(offset + 11, ent.get("last_input_seq", 0))
        buf.encode_float(offset + 15, vel.x)
        buf.encode_float(offset + 19, vel.y)
        buf.encode_float(offset + 23, aim.x)
        buf.encode_float(offset + 27, aim.y)
        buf.encode_u8(offset + 31, ent.get("state", 0))
        buf.encode_float(offset + 32, ent.get("dodge_time_remaining", 0.0))
    return buf


static func _decode_snapshot(bytes: PackedByteArray, type: int) -> Variant:
    var header_size = MessageTypes.Layout.SNAPSHOT_HEADER_SIZE
    var entity_size = MessageTypes.Layout.ENTITY_SIZE
    if bytes.size() < header_size:
        return null
    var entity_count = bytes.decode_u16(5)
    if bytes.size() < header_size + entity_count * entity_size:
        return null
    var entities: Array = []
    for i in range(entity_count):
        var offset = header_size + i * entity_size
        entities.append({
            "entity_id": bytes.decode_u16(offset),
            "position": Vector2(bytes.decode_float(offset + 2), bytes.decode_float(offset + 6)),
            "flags": bytes.decode_u8(offset + 10),
            "last_input_seq": bytes.decode_u32(offset + 11),
            "velocity": Vector2(bytes.decode_float(offset + 15), bytes.decode_float(offset + 19)),
            "aim_direction": Vector2(bytes.decode_float(offset + 23), bytes.decode_float(offset + 27)),
            "state": bytes.decode_u8(offset + 31),
            "dodge_time_remaining": bytes.decode_float(offset + 32),
        })
    return {
        "type": type,
        "tick": bytes.decode_u32(1),
        "entities": entities,
    }
```

- [ ] **Step 4: Update `PlayerEntity.to_snapshot_data`**

Modify `godot/simulation/entities/player_entity.gd`:

```gdscript
func to_snapshot_data() -> Dictionary:
    var flags = MessageTypes.EntityFlags.NONE
    if velocity.length_squared() > 0.0:
        flags |= MessageTypes.EntityFlags.MOVING
    if state == PlayerMovementState.DODGING:
        flags |= MessageTypes.EntityFlags.DODGING
    return {
        "entity_id": player_id,
        "position": position,
        "flags": flags,
        "last_input_seq": last_processed_input_seq,
        "velocity": velocity,
        "aim_direction": aim_direction,
        "state": state,
        "dodge_time_remaining": dodge_time_remaining,
    }
```

- [ ] **Step 5: Update `Snapshot.diff` to compare new fields**

Modify `godot/simulation/network/snapshot.gd`, updating the comparison block in `diff`:

```gdscript
static func diff(baseline: Snapshot, current: Snapshot) -> Array:
    var changes: Array = []

    for eid in current.entities:
        if not baseline.entities.has(eid):
            changes.append(current.entities[eid].duplicate())
        else:
            var base_ent = baseline.entities[eid]
            var curr_ent = current.entities[eid]
            var changed = false
            if not base_ent["position"].is_equal_approx(curr_ent["position"]):
                changed = true
            elif base_ent["flags"] != curr_ent["flags"]:
                changed = true
            elif base_ent.get("last_input_seq", 0) != curr_ent.get("last_input_seq", 0):
                changed = true
            elif not base_ent.get("velocity", Vector2.ZERO).is_equal_approx(curr_ent.get("velocity", Vector2.ZERO)):
                changed = true
            elif not base_ent.get("aim_direction", Vector2.RIGHT).is_equal_approx(curr_ent.get("aim_direction", Vector2.RIGHT)):
                changed = true
            elif base_ent.get("state", 0) != curr_ent.get("state", 0):
                changed = true
            elif abs(base_ent.get("dodge_time_remaining", 0.0) - curr_ent.get("dodge_time_remaining", 0.0)) > 0.001:
                changed = true
            if changed:
                changes.append(curr_ent.duplicate())

    for eid in baseline.entities:
        if not current.entities.has(eid):
            changes.append({
                "entity_id": eid,
                "position": Vector2.ZERO,
                "flags": MessageTypes.EntityFlags.REMOVED,
                "last_input_seq": 0,
                "velocity": Vector2.ZERO,
                "aim_direction": Vector2.RIGHT,
                "state": 0,
                "dodge_time_remaining": 0.0,
            })

    return changes
```

- [ ] **Step 6: Update `NetClient._send_input` to latch `dodge_pressed`**

In `godot/simulation/network/net_client.gd`, add a dodge latch field:

```gdscript
var dodge_pressed_latch: bool = false  # set by caller; consumed by _send_input
```

Update `_send_input` to include and clear the latch:

```gdscript
func _send_input():
    if _local_player == null or _local_player_id == -1:
        return

    _input_seq += 1

    var dodge = dodge_pressed_latch
    dodge_pressed_latch = false  # consume once per tick send

    var input = {
        "seq": _input_seq,
        "move_direction": input_direction,
        "aim_direction": aim_direction,
        "dodge_pressed": dodge,
    }
    _pending_inputs.append(input)
    if _pending_inputs.size() > MAX_PENDING_INPUTS:
        _pending_inputs = _pending_inputs.slice(-MAX_PENDING_INPUTS)

    var msg = {
        "type": MessageTypes.Binary.PLAYER_INPUT,
        "tick": _server_tick,
        "move_direction": input_direction,
        "aim_direction": aim_direction,
        "dodge_pressed": dodge,
        "input_seq": _input_seq,
    }
    _ws.send(NetMessage.encode(msg))
```

- [ ] **Step 7: Update per-frame prediction to predict dodge immediately**

In `_process` in the same file, update the local player update block. The client-facing public API for requesting a dodge is the latch; prediction reads it without clearing:

```gdscript
# Update local player for prediction
if _local_player != null:
    _local_player.apply_input({
        "move_direction": input_direction,
        "aim_direction": aim_direction,
        # Don't pass dodge_pressed here — it would trigger on every frame the latch is set.
        # Prediction kicks off the dodge below, once, and _send_input clears the latch later.
    })
    if dodge_pressed_latch and _local_player.can_dodge():
        _local_player.start_dodge()  # client predicts dodge immediately
    _local_player.advance(delta)
```

- [ ] **Step 8: Update reconciliation to restore full dodge state**

In `_reconcile_local_player`, extract and apply all dodge-related state from the server snapshot:

```gdscript
func _reconcile_local_player(snap: Snapshot):
    if _local_player == null or _local_player_id == -1:
        return
    if not snap.entities.has(_local_player_id):
        return

    var server_data = snap.entities[_local_player_id]
    var server_pos: Vector2 = server_data["position"]
    var server_seq: int = server_data.get("last_input_seq", 0)

    var visual_before: Vector2 = _local_player.position + _visual_offset

    while _pending_inputs.size() > 0 and _pending_inputs[0]["seq"] <= server_seq:
        _pending_inputs.pop_front()

    # Restore authoritative state before replay
    _local_player.position = server_pos
    _local_player.velocity = server_data.get("velocity", Vector2.ZERO)
    _local_player.aim_direction = server_data.get("aim_direction", Vector2.RIGHT)
    _local_player.state = server_data.get("state", 0)
    _local_player.dodge_time_remaining = server_data.get("dodge_time_remaining", 0.0)
    # dodge_cooldown_remaining is not in the snapshot; if the server says we're
    # past a dodge, cooldown is implicit in server state. Leave local cooldown.

    var tick_dt: float = MessageTypes.TICK_INTERVAL_MS / 1000.0
    for pending in _pending_inputs:
        _local_player.apply_input(pending)
        _local_player.advance(tick_dt)

    var correction: Vector2 = visual_before - _local_player.position
    var correction_dist: float = correction.length()

    if correction_dist < 0.01:
        _visual_offset = Vector2.ZERO
    elif correction_dist < SNAP_THRESHOLD:
        _visual_offset = correction
    else:
        _visual_offset = Vector2.ZERO
```

- [ ] **Step 9: Update `test_net_message.gd` for dodge_pressed + new snapshot fields**

In `godot/tests/network/test_net_message.gd`, update the input round-trip test to include `dodge_pressed`, and add a snapshot round-trip test for the new fields:

```gdscript
func test_player_input_round_trip_with_dodge():
    var msg = {
        "type": MessageTypes.Binary.PLAYER_INPUT,
        "tick": 42,
        "move_direction": Vector2(0.6, -0.8),
        "aim_direction": Vector2(1.0, 0.0),
        "dodge_pressed": true,
        "input_seq": 1234,
    }
    var bytes = NetMessage.encode(msg)
    assert_eq(bytes.size(), MessageTypes.Layout.INPUT_SIZE)
    var decoded = NetMessage.decode_binary(bytes)
    assert_eq(decoded["dodge_pressed"], true)
    assert_eq(decoded["input_seq"], 1234)

func test_snapshot_round_trip_with_dodge_state():
    var msg = {
        "type": MessageTypes.Binary.FULL_SNAPSHOT,
        "tick": 100,
        "entities": [{
            "entity_id": 1,
            "position": Vector2(240.0, 160.0),
            "flags": MessageTypes.EntityFlags.MOVING | MessageTypes.EntityFlags.DODGING,
            "last_input_seq": 55,
            "velocity": Vector2(700.0, 0.0),
            "aim_direction": Vector2(1.0, 0.0),
            "state": 1,  # DODGING
            "dodge_time_remaining": 0.15,
        }],
    }
    var bytes = NetMessage.encode(msg)
    var decoded = NetMessage.decode_binary(bytes)
    var ent = decoded["entities"][0]
    assert_eq(ent["entity_id"], 1)
    assert_almost_eq(ent["velocity"].x, 700.0, 0.01)
    assert_eq(ent["state"], 1)
    assert_almost_eq(ent["dodge_time_remaining"], 0.15, 0.001)
    assert_eq(ent["flags"] & MessageTypes.EntityFlags.DODGING, MessageTypes.EntityFlags.DODGING)
```

- [ ] **Step 10: Update `test_snapshot.gd` for new diff fields**

In `godot/tests/network/test_snapshot.gd`, add a test that verifies the diff reports changes in the new fields:

```gdscript
func test_diff_detects_velocity_change():
    var baseline = Snapshot.new()
    baseline.entities[1] = {
        "entity_id": 1,
        "position": Vector2(100.0, 100.0),
        "flags": 0,
        "last_input_seq": 1,
        "velocity": Vector2.ZERO,
        "aim_direction": Vector2.RIGHT,
        "state": 0,
        "dodge_time_remaining": 0.0,
    }
    var current = Snapshot.new()
    current.entities[1] = baseline.entities[1].duplicate()
    current.entities[1]["velocity"] = Vector2(200.0, 0.0)
    var delta = Snapshot.diff(baseline, current)
    assert_eq(delta.size(), 1)

func test_diff_detects_dodge_state_change():
    var baseline = Snapshot.new()
    baseline.entities[1] = {
        "entity_id": 1,
        "position": Vector2(100.0, 100.0),
        "flags": 0,
        "last_input_seq": 1,
        "velocity": Vector2.ZERO,
        "aim_direction": Vector2.RIGHT,
        "state": 0,
        "dodge_time_remaining": 0.0,
    }
    var current = Snapshot.new()
    current.entities[1] = baseline.entities[1].duplicate()
    current.entities[1]["state"] = 1  # DODGING
    current.entities[1]["dodge_time_remaining"] = 0.2
    var delta = Snapshot.diff(baseline, current)
    assert_eq(delta.size(), 1)
```

Update any existing `test_snapshot.gd` tests that construct entity dicts to include the new fields (or rely on `get(...)` defaults in the diff — the new code handles missing fields).

- [ ] **Step 11: Run the full test suite**

Run: `cd godot && godot --headless -s addons/gut/gut_cmdln.gd -gexit`
Expected: All tests pass.

- [ ] **Step 12: Commit**

```bash
git add godot/simulation/ godot/shared/network/message_types.gd godot/tests/network/
git commit -m "Wire dodge through network: input + snapshot + reconciliation

- Input message grows to 26 bytes (adds dodge_pressed)
- Per-entity snapshot grows to 36 bytes (velocity, aim_direction, state, dodge_time_remaining)
- DODGING flag added to entity flags bitfield
- Snapshot diff detects changes in all new fields
- Client predicts dodge on latch, reconciliation restores full dodge state"
```

---

## Task 6: New reconciliation test — shared-simulation canary

**Rationale:** Adds the second non-negotiable canary: proves client-side prediction and server-side authoritative simulation converge after reconciliation. This is the regression guard against any future change that accidentally forks client and server movement code.

**Files:**
- Create: `godot/tests/network/test_reconciliation.gd`

- [ ] **Step 1: Write the reconciliation convergence test**

Create `godot/tests/network/test_reconciliation.gd`:

```gdscript
extends GutTest
## Canary: client and server simulation must converge when reconciling.
## If these tests fail, someone forked prediction from authority — the
## "client and server share simulation code" rule is broken.

var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
var ArenaScene = preload("res://shared/world/arena.tscn")
const MovementParams = preload("res://shared/movement/movement_params.gd")

const TICK_S: float = MessageTypes.TICK_INTERVAL_MS / 1000.0


func _make_player(pos: Vector2) -> PlayerEntity:
    var p = PlayerEntityScene.instantiate()
    add_child_autofree(p)
    p.initialize(1, pos)
    p.params = MovementParams.new()
    return p


func test_replay_matches_server_for_walking():
    # Spawn arena so collision shapes exist for both players
    add_child_autofree(ArenaScene.instantiate())
    var server = _make_player(Vector2(240.0, 160.0))
    var client = _make_player(Vector2(240.0, 160.0))

    var inputs: Array = []
    for seq in range(10):
        inputs.append({
            "seq": seq + 1,
            "move_direction": Vector2(1.0, 0.0),
            "aim_direction": Vector2.RIGHT,
            "dodge_pressed": false,
            "input_seq": seq + 1,
        })

    # Server processes inputs one per tick
    for input in inputs:
        server.apply_input(input)
        server.advance(TICK_S)

    # Client "reconciles" by resetting to initial state then replaying identical inputs
    client.position = Vector2(240.0, 160.0)
    client.velocity = Vector2.ZERO
    for input in inputs:
        client.apply_input(input)
        client.advance(TICK_S)

    assert_almost_eq(client.position.x, server.position.x, 0.5,
        "Client replay must converge to server position")
    assert_almost_eq(client.velocity.x, server.velocity.x, 0.5,
        "Client replay must converge to server velocity")


func test_replay_matches_server_mid_dodge():
    add_child_autofree(ArenaScene.instantiate())
    var server = _make_player(Vector2(240.0, 160.0))
    var client = _make_player(Vector2(240.0, 160.0))

    # Input sequence: walk right for 3 ticks, then dodge, then continue
    var inputs: Array = []
    for i in range(3):
        inputs.append({
            "seq": i + 1, "move_direction": Vector2(1.0, 0.0),
            "aim_direction": Vector2.RIGHT, "dodge_pressed": false, "input_seq": i + 1,
        })
    inputs.append({
        "seq": 4, "move_direction": Vector2(1.0, 0.0),
        "aim_direction": Vector2.RIGHT, "dodge_pressed": true, "input_seq": 4,
    })
    for i in range(3):
        inputs.append({
            "seq": 5 + i, "move_direction": Vector2(1.0, 0.0),
            "aim_direction": Vector2.RIGHT, "dodge_pressed": false, "input_seq": 5 + i,
        })

    for input in inputs:
        server.apply_input(input)
        server.advance(TICK_S)

    for input in inputs:
        client.apply_input(input)
        client.advance(TICK_S)

    assert_almost_eq(client.position.x, server.position.x, 0.5,
        "Client replay through dodge must converge with server")


func test_replay_rejects_server_rejected_dodge():
    # Simulate: client predicted a dodge, but server had cooldown and rejected it.
    # After the reconcile, replay with the actual inputs the server saw (which
    # include the "attempted dodge" — but server rejected it because of cooldown
    # state restored from snapshot).
    add_child_autofree(ArenaScene.instantiate())
    var server = _make_player(Vector2(240.0, 160.0))
    var client = _make_player(Vector2(240.0, 160.0))

    # Put both in cooldown by forcing a prior dodge
    server.move_input = Vector2(1.0, 0.0)
    server.start_dodge()
    for i in range(10):
        server.advance(TICK_S)  # finish dodge, still on cooldown

    client.move_input = Vector2(1.0, 0.0)
    client.start_dodge()
    for i in range(10):
        client.advance(TICK_S)

    # Now try another dodge — should be rejected on both sides equally
    var dodge_input = {
        "seq": 1, "move_direction": Vector2(1.0, 0.0),
        "aim_direction": Vector2.RIGHT, "dodge_pressed": true, "input_seq": 100,
    }
    server.apply_input(dodge_input)
    client.apply_input(dodge_input)
    assert_eq(server.state, client.state,
        "Both sides must agree on state after rejected dodge")
    assert_eq(server.state, 0,  # WALKING
        "Dodge on cooldown must not transition to DODGING")
```

- [ ] **Step 2: Run the test and confirm it passes**

Run: `cd godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_reconciliation.gd -gexit`
Expected: 3 tests pass. If any fail, the client and server are not running the same code path and the "shared simulation code" rule is broken — investigate before proceeding.

- [ ] **Step 3: Commit**

```bash
git add godot/tests/network/test_reconciliation.gd
git commit -m "Add reconciliation convergence tests (shared-sim canary)"
```

---

## Task 7: Remote interpolation — velocity-aware extrapolation

**Rationale:** With `velocity` in the snapshot, remote player rendering can extrapolate forward during the post-snapshot gap instead of only time-lerping between last two positions. Smoother remote rendering, especially for dodges.

**Files:**
- Modify: `godot/simulation/network/net_client.gd` — extend `get_interpolated_position`

- [ ] **Step 1: Update remote interpolation to use velocity**

In `godot/simulation/network/net_client.gd`, replace `get_interpolated_position`:

```gdscript
func get_interpolated_position(entity_id: int) -> Variant:
    if entity_id == _local_player_id:
        return null

    if _snapshot_prev == null or _snapshot_curr == null:
        return null

    if not _snapshot_curr.entities.has(entity_id):
        return null

    var curr = _snapshot_curr.entities[entity_id]
    var curr_pos: Vector2 = curr["position"]

    if not _snapshot_prev.entities.has(entity_id):
        return curr_pos

    var prev = _snapshot_prev.entities[entity_id]
    var prev_pos: Vector2 = prev["position"]

    var tick_interval = MessageTypes.TICK_INTERVAL_MS / 1000.0
    var t = clampf(_snapshot_time / tick_interval, 0.0, MAX_REMOTE_INTERP)

    if t <= 1.0:
        # Within interpolation window — lerp between snapshots
        return prev_pos.lerp(curr_pos, t)
    else:
        # Extrapolate forward using current snapshot velocity
        var vel: Vector2 = curr.get("velocity", Vector2.ZERO)
        var extra_time = (t - 1.0) * tick_interval
        return curr_pos + vel * extra_time
```

- [ ] **Step 2: Run the full test suite**

Run: `cd godot && godot --headless -s addons/gut/gut_cmdln.gd -gexit`
Expected: All tests pass (this is a view-side smoothing change; no sim tests touch it, but don't break anything).

- [ ] **Step 3: Commit**

```bash
git add godot/simulation/network/net_client.gd
git commit -m "Remote player extrapolation uses snapshot velocity when past interpolation window"
```

---

## Task 8: Input abstraction layer — InputProvider + KeyboardMouseInputProvider

**Rationale:** Land the abstraction the user asked for. Gamepad support later is a constructor swap. Also latches edge-triggered dodge detection cleanly.

**Files:**
- Create: `godot/simulation/input/input_provider.gd`
- Create: `godot/simulation/input/keyboard_mouse_input_provider.gd`
- Modify: `godot/project.godot` — add "dodge" input action bound to Space/Shift

- [ ] **Step 1: Add the "dodge" input action**

Modify `godot/project.godot`. Find the `[input]` section and add (if not present):

```
dodge={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":32,"key_label":0,"unicode":32,"location":0,"echo":false,"script":null)
]
}
```

(Key 32 = Space. Add a second event for Shift or a mouse button if desired later.)

Verify in-editor if you have GUI access by opening Project Settings → Input Map; otherwise the raw InputEventKey line above adds it directly.

- [ ] **Step 2: Create the abstract `InputProvider` interface**

Create `godot/simulation/input/input_provider.gd`:

```gdscript
class_name InputProvider
extends RefCounted
## Abstract input provider — produces simulation-layer input data
## (Vector2 direction, bool flags) from whatever source. Concrete
## implementations handle hardware specifics (keyboard+mouse, gamepad).

## Latest raw movement direction (WASD vector, not normalized).
var move_direction: Vector2 = Vector2.ZERO

## Latest aim direction (unit vector from player toward aim target).
var aim_direction: Vector2 = Vector2.RIGHT

## Call once per frame to refresh internal state from hardware.
## Subclasses override this.
func poll(player_world_position: Vector2) -> void:
    pass

## Returns true if dodge was pressed this frame (non-consuming read).
## Subclasses override.
func dodge_pressed_this_frame() -> bool:
    return false

## Returns true and CLEARS the latch. Used by the network send layer
## to guarantee exactly one dodge input per real button press.
func consume_dodge_press() -> bool:
    return false
```

- [ ] **Step 3: Create the `KeyboardMouseInputProvider`**

Create `godot/simulation/input/keyboard_mouse_input_provider.gd`:

```gdscript
class_name KeyboardMouseInputProvider
extends InputProvider
## Keyboard + mouse input for PC. Reads WASD for movement and the mouse
## cursor's world position for aim. Latches "dodge" edge press so it
## survives the gap between display-frame polling and tick-rate send.

var _dodge_latched: bool = false
var _viewport: Viewport


func _init(viewport: Viewport) -> void:
    _viewport = viewport


func poll(player_world_position: Vector2) -> void:
    move_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")

    # Aim direction: unit vector from player to mouse (in world coords)
    var mouse_world = _viewport.get_camera_2d().get_global_mouse_position() if _viewport.get_camera_2d() else _viewport.get_mouse_position()
    var diff = mouse_world - player_world_position
    if diff.length_squared() > 0.01:
        aim_direction = diff.normalized()
    # else keep prior aim_direction

    if Input.is_action_just_pressed("dodge"):
        _dodge_latched = true


func dodge_pressed_this_frame() -> bool:
    return _dodge_latched


func consume_dodge_press() -> bool:
    var v = _dodge_latched
    _dodge_latched = false
    return v
```

- [ ] **Step 4: Commit**

```bash
git add godot/simulation/input/ godot/project.godot
git commit -m "Add InputProvider abstraction + KeyboardMouseInputProvider

- Abstract interface in /simulation/input/
- Keyboard+mouse concrete impl reads WASD + camera-relative mouse
- Edge-triggered dodge latch survives display-to-tick cadence gap
- Dodge input action added to project.godot"
```

---

## Task 9: Wire `client_main.gd` to use InputProvider and push dodge latch

**Rationale:** Replaces the direct `Input.get_vector(...)` call in `client_main.gd` with the new abstraction and connects the dodge latch to NetClient.

**Files:**
- Modify: `godot/client_main.gd`

- [ ] **Step 1: Instantiate the InputProvider in `_ready`**

In `godot/client_main.gd`, add near the top of the file (after the existing `var _net_client: NetClient`):

```gdscript
var _input_provider: InputProvider
```

In `_ready()`, after the existing node assignments, add:

```gdscript
_input_provider = KeyboardMouseInputProvider.new(get_viewport())
```

- [ ] **Step 2: Replace the per-frame input block**

In `_process`, replace the existing block:

```gdscript
func _process(_delta: float):
    if _net_client.is_server_connected():
        _net_client.input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
        _update_remote_proxies()
```

with:

```gdscript
func _process(_delta: float):
    if _net_client.is_server_connected():
        var player_pos = _net_client.get_local_player_position()
        if player_pos == null:
            player_pos = Vector2.ZERO
        _input_provider.poll(player_pos)
        _net_client.input_direction = _input_provider.move_direction
        _net_client.aim_direction = _input_provider.aim_direction
        if _input_provider.consume_dodge_press():
            _net_client.dodge_pressed_latch = true
        _update_remote_proxies()
```

Note: `consume_dodge_press()` clears the provider latch, and we set NetClient's latch. NetClient's latch survives until `_send_input` consumes it at tick rate. This double-latch is intentional — it bridges display-rate input polling to tick-rate send without dropping presses.

- [ ] **Step 3: Manual smoke check — headless can't test this, so compile-check it**

Run: `cd godot && godot --headless --check-only client_main.gd 2>&1 | head -50`
Expected: No script errors. (Or launch the client briefly — we don't have a dedicated smoke for this layer.)

- [ ] **Step 4: Commit**

```bash
git add godot/client_main.gd
git commit -m "Wire client_main to use InputProvider abstraction"
```

---

## Task 10: Camera rig — deadzone + mouse lookahead + shake

**Rationale:** Non-negotiable for the milestone — you can't evaluate movement feel without a camera. Pure view layer.

**Files:**
- Create: `godot/view/world/camera_rig.gd`
- Create: `godot/view/world/camera_rig.tscn`
- Modify: `godot/view/world/world_view.gd` — instantiate + init the rig, hand it a NetClient ref
- Modify: `godot/view/world/world_view.tscn` — add a `CameraRig` child (or instantiate in code)

- [ ] **Step 1: Create the camera rig script**

Create `godot/view/world/camera_rig.gd`:

```gdscript
class_name CameraRig
extends Camera2D

@export var deadzone_size: Vector2 = Vector2(40.0, 30.0)
@export var lookahead_max: float = 80.0
@export var lookahead_ramp: float = 140.0
@export var follow_smoothing: float = 8.0
@export var shake_decay: float = 20.0  # exp coeff for shake decay

var _net_client: NetClient
var _target_position: Vector2 = Vector2.ZERO
var _shake_amplitude: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO


func initialize(net_client: NetClient) -> void:
    _net_client = net_client


func add_shake(amplitude: float, _duration: float) -> void:
    # Amplitude replaces prior if larger; decays exponentially regardless of duration
    _shake_amplitude = max(_shake_amplitude, amplitude)


func _process(delta: float):
    if _net_client == null:
        return
    var local_pos = _net_client.get_local_player_position()
    if local_pos == null:
        return

    # Deadzone: target stays put unless player exits the box
    var diff = local_pos - _target_position
    if abs(diff.x) > deadzone_size.x * 0.5:
        _target_position.x = local_pos.x - sign(diff.x) * deadzone_size.x * 0.5
    if abs(diff.y) > deadzone_size.y * 0.5:
        _target_position.y = local_pos.y - sign(diff.y) * deadzone_size.y * 0.5

    # Mouse lookahead: offset toward mouse proportional to mouse-player distance
    var mouse_offset = get_local_mouse_position()
    var amt = clampf(mouse_offset.length() / lookahead_ramp, 0.0, 1.0)
    var lookahead = mouse_offset.normalized() * lookahead_max * amt if mouse_offset.length_squared() > 0.01 else Vector2.ZERO

    # Shake: random offset, exponential decay
    if _shake_amplitude > 0.001:
        _shake_offset = Vector2(
            RNG.next_float_range(-_shake_amplitude, _shake_amplitude),
            RNG.next_float_range(-_shake_amplitude, _shake_amplitude)
        )
        _shake_amplitude *= exp(-shake_decay * delta)
    else:
        _shake_offset = Vector2.ZERO
        _shake_amplitude = 0.0

    var target = _target_position + lookahead + _shake_offset
    position = position.lerp(target, 1.0 - exp(-follow_smoothing * delta))
```

**Note on `RNG.next_float_range`:** check `godot/autoloads/rng.gd` for the actual method name. If it's different (e.g., `RNG.next_float()` returning 0-1), adapt: `(_shake_amplitude * (RNG.next_float() * 2.0 - 1.0))`.

- [ ] **Step 2: Create the camera rig scene**

Create `godot/view/world/camera_rig.tscn` as a minimal scene: one `CameraRig` node as root, with `enabled = true`. You can create it in-editor or write it by hand. Minimal .tscn content:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://view/world/camera_rig.gd" id="1"]

[node name="CameraRig" type="Camera2D"]
script = ExtResource("1")
enabled = true
```

- [ ] **Step 3: Instantiate the rig in `WorldView`**

In `godot/view/world/world_view.gd`:

Add at the top with other preloads:
```gdscript
var CameraRigScene: PackedScene = preload("res://view/world/camera_rig.tscn")
```

Add a field:
```gdscript
var _camera_rig: CameraRig
```

In `initialize()`, after existing signal connections, instantiate and attach:
```gdscript
_camera_rig = CameraRigScene.instantiate()
add_child(_camera_rig)
_camera_rig.initialize(_net_client)
```

Expose the rig so juice effects can call `add_shake`:
```gdscript
func get_camera_rig() -> CameraRig:
    return _camera_rig
```

Also expose the local player position (needed by the rig):
```gdscript
# If not already present in world_view.gd — NetClient exposes this already,
# so the rig can just call _net_client.get_local_player_position(). No changes
# to world_view for this particular needed.
```

- [ ] **Step 4: Launch the server and a browser client to eyeball-verify**

Manual check — not unit-testable:

1. `cd godot && godot --headless -- --server (in one terminal)`
2. Open client in browser
3. Walk around — camera should hold still within a small box, then follow when you exit. Mouse movement should drift the camera toward the cursor. No jitter, no lag, no snap.

Tune `deadzone_size`, `lookahead_max`, `follow_smoothing` in the `.tres` or inspector to taste.

- [ ] **Step 5: Commit**

```bash
git add godot/view/world/camera_rig.gd godot/view/world/camera_rig.tscn godot/view/world/world_view.gd
git commit -m "Add camera rig with deadzone, mouse lookahead, shake"
```

---

## Task 11: PlayerView visuals — facing indicator, i-frame tint, walk pulse

**Rationale:** Ship the "local player visibly alive" pass. Uses `aim_direction` and `state` from the predicted local player (for self) or from snapshot data (for remotes).

**Files:**
- Modify: `godot/view/world/player_view.gd`

- [ ] **Step 1: Extend `PlayerView` with facing line, tint, pulse**

Replace `godot/view/world/player_view.gd`:

```gdscript
extends Node2D

var player_id: int = -1
var is_local: bool = false
var _target_position: Vector2 = Vector2.ZERO

var _visual: ColorRect
var _facing_line: Line2D
var _base_color: Color


func _ready():
    _visual = ColorRect.new()
    _visual.size = Vector2(16, 16)
    _visual.position = Vector2(-8, -8)
    _visual.name = "Visual"
    add_child(_visual)

    _facing_line = Line2D.new()
    _facing_line.width = 2.0
    _facing_line.default_color = Color(1.0, 1.0, 1.0, 0.9)
    _facing_line.points = PackedVector2Array([Vector2.ZERO, Vector2(6.0, 0.0)])
    _facing_line.name = "FacingLine"
    add_child(_facing_line)


func initialize(id: int, spawn_pos: Vector2, local: bool) -> void:
    player_id = id
    is_local = local
    position = spawn_pos
    _target_position = spawn_pos
    if local:
        _base_color = Color(0.3, 0.8, 1.0)
    else:
        _base_color = Color(1.0, 0.4, 0.3)
    _visual.color = _base_color


func update_position(new_pos: Vector2) -> void:
    _target_position = new_pos


## Called by WorldView each frame with the authoritative aim direction,
## the movement state, and current velocity (for walk pulse).
func update_visual_state(aim_dir: Vector2, state: int, velocity_magnitude: float, delta: float) -> void:
    # Facing line
    if aim_dir.length_squared() > 0.01:
        _facing_line.rotation = aim_dir.angle()

    # i-frame tint while dodging
    const DODGING = 1  # keep local enum ref to avoid preload cost
    if state == DODGING:
        _visual.color = _base_color.lerp(Color(1.4, 1.4, 1.8), 1.0)
    else:
        _visual.color = _base_color

    # Walk pulse — subtle stretch while moving, rest at 1.0 while idle
    var target_scale = Vector2(1.03, 0.97) if velocity_magnitude > 1.0 else Vector2.ONE
    _visual.scale = _visual.scale.lerp(target_scale, 1.0 - exp(-10.0 * delta))


func _process(_delta: float):
    position = _target_position
```

- [ ] **Step 2: Update `WorldView._process` to feed visual state**

In `godot/view/world/world_view.gd`, update `_process` to call `update_visual_state` on each player view:

```gdscript
func _process(delta: float):
    if _net_client == null:
        return

    for player_id in _player_views:
        var view = _player_views[player_id]
        var aim: Vector2 = Vector2.RIGHT
        var state: int = 0
        var vel_mag: float = 0.0

        if view.is_local:
            var local_pos = _net_client.get_local_player_position()
            if local_pos != null:
                var offset = _net_client.get_visual_offset()
                view.update_position(local_pos + offset)
                _net_client.blend_visual_offset(delta)
            # Pull visual state from local predicted player
            var local_player = _net_client._local_player  # view reads sim state, doesn't mutate
            if local_player != null:
                aim = local_player.aim_direction
                state = local_player.state
                vel_mag = local_player.velocity.length()
        else:
            var interp_pos = _net_client.get_interpolated_position(player_id)
            if interp_pos != null:
                view.update_position(interp_pos)
            # Pull visual state from latest snapshot
            if _net_client._snapshot_curr != null and _net_client._snapshot_curr.entities.has(player_id):
                var ent = _net_client._snapshot_curr.entities[player_id]
                aim = ent.get("aim_direction", Vector2.RIGHT)
                state = ent.get("state", 0)
                vel_mag = ent.get("velocity", Vector2.ZERO).length()

        view.update_visual_state(aim, state, vel_mag, delta)
```

Note: WorldView reaching into `_net_client._local_player` and `_net_client._snapshot_curr` is a minor encapsulation break. If you prefer, add public accessors on NetClient: `get_local_player_aim_direction()`, `get_local_player_state()`, `get_local_player_velocity()`, `get_remote_player_snapshot_data(id)`. For a v1 ship, direct access is acceptable; add the accessors if/when the friction shows up.

- [ ] **Step 3: Manual verification**

Manual check:
- Local player has a small line pointing toward the mouse cursor
- Line rotates as you move the mouse
- Brief dodge press brightens the local player's color for ~200ms
- Player shape pulses subtly while walking, returns to normal when stopped

- [ ] **Step 4: Commit**

```bash
git add godot/view/world/player_view.gd godot/view/world/world_view.gd
git commit -m "PlayerView: facing indicator, dodge i-frame tint, walk pulse"
```

---

## Task 12: DodgeTrail effect

**Rationale:** First of four juice listeners. Subscribes to `player_dodge_started` and spawns a fading afterimage behind the dodging player.

**Files:**
- Create: `godot/view/effects/dodge_trail.gd`
- Modify: `godot/view/world/world_view.gd` — instantiate DodgeTrail

- [ ] **Step 1: Create the DodgeTrail node**

Create `godot/view/effects/dodge_trail.gd`:

```gdscript
class_name DodgeTrail
extends Node2D
## Listens for player_dodge_started events and renders a Line2D afterimage
## that follows the dodging player, fading out when the dodge ends.

const TRAIL_LIFETIME_AFTER_END: float = 0.15

var _active_trails: Dictionary = {}  # entity_id -> { line: Line2D, fade_time: float, source: Callable }
var _world_view: Node2D  # reference for resolving player view positions


func _ready():
    EventBus.player_dodge_started.connect(_on_dodge_started)
    EventBus.player_dodge_ended.connect(_on_dodge_ended)


func initialize(world_view: Node2D) -> void:
    _world_view = world_view


func _on_dodge_started(event: Dictionary):
    var entity_id: int = event["entity_id"]
    if _active_trails.has(entity_id):
        return  # Trail already exists (shouldn't happen, but be safe)
    var line = Line2D.new()
    line.width = 14.0
    line.default_color = Color(0.6, 0.8, 1.0, 0.7)  # pale blue
    var grad = Gradient.new()
    grad.add_point(0.0, Color(0.6, 0.8, 1.0, 0.0))  # tail end fades out
    grad.add_point(1.0, Color(0.6, 0.8, 1.0, 0.8))  # head is full alpha
    line.gradient = grad
    add_child(line)
    _active_trails[entity_id] = {"line": line, "fade_time": -1.0}


func _on_dodge_ended(event: Dictionary):
    var entity_id: int = event["entity_id"]
    if _active_trails.has(entity_id):
        _active_trails[entity_id]["fade_time"] = TRAIL_LIFETIME_AFTER_END


func _process(delta: float):
    if _world_view == null:
        return
    var finished: Array = []
    for entity_id in _active_trails:
        var trail = _active_trails[entity_id]
        var line: Line2D = trail["line"]
        # Get current player position from the view
        var player_pos = _get_player_position(entity_id)
        if player_pos == null:
            finished.append(entity_id)
            continue
        # Append new point and trim old ones
        line.add_point(player_pos)
        if line.get_point_count() > 8:
            line.remove_point(0)
        # Handle fade-out after dodge ends
        if trail["fade_time"] >= 0.0:
            trail["fade_time"] -= delta
            line.modulate.a = clampf(trail["fade_time"] / TRAIL_LIFETIME_AFTER_END, 0.0, 1.0)
            if trail["fade_time"] <= 0.0:
                finished.append(entity_id)
    for entity_id in finished:
        _active_trails[entity_id]["line"].queue_free()
        _active_trails.erase(entity_id)


func _get_player_position(entity_id: int) -> Variant:
    # World view exposes player views keyed by id
    if _world_view.has_method("get_player_view_position"):
        return _world_view.get_player_view_position(entity_id)
    return null


func _exit_tree():
    if EventBus.player_dodge_started.is_connected(_on_dodge_started):
        EventBus.player_dodge_started.disconnect(_on_dodge_started)
    if EventBus.player_dodge_ended.is_connected(_on_dodge_ended):
        EventBus.player_dodge_ended.disconnect(_on_dodge_ended)
```

- [ ] **Step 2: Add position accessor to `WorldView`**

In `godot/view/world/world_view.gd`:

```gdscript
func get_player_view_position(player_id: int) -> Variant:
    if _player_views.has(player_id):
        return _player_views[player_id].position
    return null
```

- [ ] **Step 3: Instantiate DodgeTrail in `WorldView.initialize`**

In `godot/view/world/world_view.gd` `initialize()`, after the camera rig instantiation:

```gdscript
var dodge_trail = preload("res://view/effects/dodge_trail.gd").new()
add_child(dodge_trail)
dodge_trail.initialize(self)
```

- [ ] **Step 4: Manual verification**

Launch server + one client. Press dodge. A pale blue trail should briefly appear behind the player and fade out.

- [ ] **Step 5: Commit**

```bash
git add godot/view/effects/dodge_trail.gd godot/view/world/world_view.gd
git commit -m "DodgeTrail: afterimage on player_dodge_started, fades on dodge_ended"
```

---

## Task 13: FootstepDust effect

**Rationale:** Second juice listener. Subscribes to `player_moved` and spawns small dust puffs at a distance threshold.

**Files:**
- Create: `godot/view/effects/footstep_dust.gd`
- Modify: `godot/view/world/world_view.gd` — instantiate

- [ ] **Step 1: Create the FootstepDust node**

Create `godot/view/effects/footstep_dust.gd`:

```gdscript
class_name FootstepDust
extends Node2D

const STEP_DISTANCE: float = 24.0

var _distance_accum: Dictionary = {}  # entity_id -> accumulated px


func _ready():
    EventBus.player_moved.connect(_on_player_moved)


func _on_player_moved(event: Dictionary):
    var entity_id: int = event["entity_id"]
    var vel: Vector2 = event["velocity"]
    var step = vel.length() * get_process_delta_time()
    _distance_accum[entity_id] = _distance_accum.get(entity_id, 0.0) + step
    if _distance_accum[entity_id] >= STEP_DISTANCE:
        _distance_accum[entity_id] = 0.0
        _spawn_puff(event["position"])


func _spawn_puff(pos: Vector2) -> void:
    var particles = CPUParticles2D.new()
    particles.position = pos
    particles.emitting = true
    particles.one_shot = true
    particles.amount = 4
    particles.lifetime = 0.3
    particles.explosiveness = 1.0
    particles.initial_velocity_min = 8.0
    particles.initial_velocity_max = 16.0
    particles.direction = Vector2.UP
    particles.spread = 40.0
    particles.gravity = Vector2(0, 0)
    particles.scale_amount_min = 1.5
    particles.scale_amount_max = 2.5
    particles.color = Color(0.7, 0.7, 0.65, 0.5)
    add_child(particles)
    # Clean up after lifetime elapses
    await get_tree().create_timer(particles.lifetime + 0.1).timeout
    particles.queue_free()


func _exit_tree():
    if EventBus.player_moved.is_connected(_on_player_moved):
        EventBus.player_moved.disconnect(_on_player_moved)
```

- [ ] **Step 2: Instantiate in `WorldView.initialize`**

Add after the DodgeTrail instantiation:

```gdscript
var footstep_dust = preload("res://view/effects/footstep_dust.gd").new()
add_child(footstep_dust)
```

- [ ] **Step 3: Manual verification**

Launch server + client. Walk around — small dust puffs should appear at the player's feet at a steady rate while moving.

- [ ] **Step 4: Commit**

```bash
git add godot/view/effects/footstep_dust.gd godot/view/world/world_view.gd
git commit -m "FootstepDust: periodic puffs on player_moved distance threshold"
```

---

## Task 14: WallBump effect

**Rationale:** Third juice listener. Subscribes to `player_collided` and spawns a particle burst plus tiny screen shake when collision velocity is meaningful.

**Files:**
- Create: `godot/view/effects/wall_bump.gd`
- Modify: `godot/view/world/world_view.gd` — instantiate + inject camera rig reference

- [ ] **Step 1: Create the WallBump node**

Create `godot/view/effects/wall_bump.gd`:

```gdscript
class_name WallBump
extends Node2D

const VELOCITY_THRESHOLD: float = 40.0  # ignore sub-threshold touches

var _camera_rig: CameraRig


func _ready():
    EventBus.player_collided.connect(_on_collided)


func initialize(camera_rig: CameraRig) -> void:
    _camera_rig = camera_rig


func _on_collided(event: Dictionary):
    var vel: Vector2 = event["velocity"]
    if vel.length() < VELOCITY_THRESHOLD:
        return
    _spawn_burst(event["position"], event["normal"])
    if _camera_rig != null:
        _camera_rig.add_shake(1.5, 0.08)


func _spawn_burst(pos: Vector2, normal: Vector2) -> void:
    var particles = CPUParticles2D.new()
    particles.position = pos
    particles.emitting = true
    particles.one_shot = true
    particles.amount = 5
    particles.lifetime = 0.25
    particles.explosiveness = 1.0
    particles.initial_velocity_min = 30.0
    particles.initial_velocity_max = 60.0
    particles.direction = normal
    particles.spread = 30.0
    particles.gravity = Vector2(0, 0)
    particles.scale_amount_min = 1.5
    particles.scale_amount_max = 3.0
    particles.color = Color(0.8, 0.75, 0.6, 0.7)
    add_child(particles)
    await get_tree().create_timer(particles.lifetime + 0.1).timeout
    particles.queue_free()


func _exit_tree():
    if EventBus.player_collided.is_connected(_on_collided):
        EventBus.player_collided.disconnect(_on_collided)
```

- [ ] **Step 2: Instantiate and inject camera rig**

In `godot/view/world/world_view.gd`, after the camera rig and other effects:

```gdscript
var wall_bump = preload("res://view/effects/wall_bump.gd").new()
add_child(wall_bump)
wall_bump.initialize(_camera_rig)
```

- [ ] **Step 3: Manual verification**

Walk hard into a wall — small particle burst + barely-perceptible screen shake.

- [ ] **Step 4: Commit**

```bash
git add godot/view/effects/wall_bump.gd godot/view/world/world_view.gd
git commit -m "WallBump: particle burst + screen shake on player_collided"
```

---

## Task 15: Screen shake on dodge wiring

**Rationale:** Final juice wire. Connects `player_dodge_started` to `camera_rig.add_shake` for the local player only. No new file — lives inside the existing DodgeTrail or WorldView depending on preference. Here it's in `WorldView` for clarity.

**Files:**
- Modify: `godot/view/world/world_view.gd`

- [ ] **Step 1: Connect to the signal in `WorldView.initialize`**

At the end of `initialize()`:

```gdscript
EventBus.player_dodge_started.connect(_on_any_dodge_started)
```

Add the handler:

```gdscript
func _on_any_dodge_started(event: Dictionary):
    # Only shake for the local player — remote dodges don't shake your camera
    if _net_client == null:
        return
    if event["entity_id"] == _net_client.get_local_player_id():
        if _camera_rig != null:
            _camera_rig.add_shake(1.0, 0.05)
```

Add cleanup in `_on_disconnected` or `_exit_tree`:

```gdscript
func _exit_tree():
    if EventBus.player_dodge_started.is_connected(_on_any_dodge_started):
        EventBus.player_dodge_started.disconnect(_on_any_dodge_started)
```

- [ ] **Step 2: Manual verification**

Dodge — barely-perceptible screen shake (1px, 50ms). If you notice it consciously, reduce amplitude to 0.5.

- [ ] **Step 3: Commit**

```bash
git add godot/view/world/world_view.gd
git commit -m "Screen shake on local player dodge_started"
```

---

## Task 16: Full playtest, tuning pass, and DEVLOG entry

**Rationale:** Close the milestone. Run all tests headless, do the full manual playtest, tune any values that feel off, update DEVLOG per the project rule ("Update the DEVLOG.md with the appropriate info every time you are about to make a PR").

**Files:**
- Modify: `godot/shared/movement/default_movement_params.tres` — tuning
- Modify: `DEVLOG.md`

- [ ] **Step 1: Run the full headless test suite**

Run: `cd godot && godot --headless -s addons/gut/gut_cmdln.gd -gexit`
Expected: All tests pass. If any fail, fix before proceeding.

- [ ] **Step 2: Full manual playtest — single client**

Launch server in one terminal, client in another (or browser):
```bash
cd godot && godot --headless -- --server   # terminal 1
cd godot && godot                           # terminal 2 (or browser)
```

Walk through this checklist, tune until each is "feels good":

- [ ] Walk in all 8 directions — responsive, grounded, not slippery
- [ ] Stop button feels like a stop, not a skid (tune `friction`)
- [ ] Dodge from standing still works (uses aim direction)
- [ ] Dodge while walking uses move direction
- [ ] Dodge cooldown enforced — can't spam
- [ ] Dodge i-frame tint is clearly visible but not jarring
- [ ] Camera follows with deadzone — micro-movements don't jitter the world
- [ ] Camera leads toward mouse cursor
- [ ] Footstep dust spawns at a readable rate while walking
- [ ] Hitting a wall produces particles + micro-shake
- [ ] Dodge screen shake is felt, not seen (tune down if distracting)
- [ ] Dodge trail is visible but doesn't obscure the player

Tune `godot/shared/movement/default_movement_params.tres` values as needed — especially `accel`, `friction`, `dodge_speed`, `dodge_duration`. If you change them, re-verify the `test_player_entity_advance.gd` assertions still pass (they use default param values).

- [ ] **Step 3: Full manual playtest — two clients**

Launch two clients connected to the same server:

- [ ] Other player's dodge trail is visible on your screen
- [ ] Other player's position is smooth during remote dodge (thanks to velocity extrapolation)
- [ ] Your dodge prediction never rubber-bands on normal latency
- [ ] Walking smoothly syncs both ways

- [ ] **Step 4: Update DEVLOG.md**

Modify `DEVLOG.md`. Add a new dated entry at the top (under existing top entry):

```markdown
## 2026-04-09
- Step 2 movement feel complete
- PlayerEntity.advance(dt) as single canonical movement step shared by client prediction and server authority
- MovementParams Resource for runtime-swappable tuning (future-proof for surfaces/gear)
- Light accel/friction baseline + dedicated dodge with i-frames, cooldown, Hades-pattern direction
- Deadzone + mouse lookahead camera with exponential smoothing
- Juice pass: dodge trail afterimage, footstep dust, wall bump particles + shake, walk pulse, i-frame tint
- InputProvider abstraction — keyboard+mouse now, gamepad slots in later without refactoring
- Two new hard rules added to CLAUDE.md: dt-independent simulation math, shared client/server sim code
- New canary tests: dt-independence regression guard, shared-simulation convergence guard
- Next session: step 2 combat half — frost bolt + one enemy type + hit feedback
```

- [ ] **Step 5: Final full test run before PR**

Run: `cd godot && godot --headless -s addons/gut/gut_cmdln.gd -gexit`
Expected: All tests pass.

- [ ] **Step 6: Commit tuning and devlog**

```bash
git add godot/shared/movement/default_movement_params.tres DEVLOG.md
git commit -m "Tune movement params + devlog update for step 2 movement half"
```

---

## Self-Review

Checking plan against the spec (`docs/superpowers/specs/2026-04-09-movement-feel-design.md`):

**Spec coverage:**
- ✅ WASD + mouse aim with input abstraction → Tasks 8, 9
- ✅ Light accel/friction with dt-independent math → Task 2
- ✅ Dodge with i-frames, 140px/200ms/700ms, Hades-pattern direction → Task 4
- ✅ MovementParams Resource with runtime swap → Task 1
- ✅ PlayerMovementState enum → Task 1
- ✅ EventBus new signals → Task 1
- ✅ apply_input dict signature → Task 3
- ✅ Input message protocol extension → Tasks 3, 5
- ✅ Snapshot per-entity extension → Task 5
- ✅ Server dodge validation (via apply_input gating) → Task 4
- ✅ Client prediction + reconciliation restoring full dodge state → Task 5
- ✅ Remote velocity-aware extrapolation → Task 7
- ✅ Camera rig deadzone + lookahead + shake → Task 10
- ✅ PlayerView facing indicator, i-frame tint, walk pulse → Task 11
- ✅ DodgeTrail, FootstepDust, WallBump, screen shake — Tasks 12-15
- ✅ dt-independence canary test → Task 2
- ✅ Dodge state machine tests → Task 4
- ✅ Reconciliation convergence canary → Task 6
- ✅ Input encoding round-trip tests → Tasks 3, 5
- ✅ Manual playtest checklist → Task 16
- ✅ DEVLOG update → Task 16

**Placeholder scan:** No "TBD", "TODO", "implement later", or vague instructions found. Every code step shows the actual code. Every test step shows the actual test. Every command shows the exact invocation.

**Type consistency:** `advance(dt)`, `apply_input(Dictionary)`, `can_dodge()`, `start_dodge()`, `MovementParams`, `PlayerMovementState`, `CameraRig.add_shake(amplitude, duration)`, `InputProvider.consume_dodge_press()` — all referenced names are consistent across tasks. The `dodge_pressed_latch` field on NetClient is consistently named in Tasks 5 and 9.

**Spec gaps:** None identified.

**Known implementation note left to the engineer:** The `RNG.next_float_range` call in Task 10 Step 1 depends on the actual API of `autoloads/rng.gd`. If the method is named differently, adapt using `RNG.next_float()` (returning 0-1) mapped into the amplitude range. This is flagged inline in the task.

---

Plan complete.
