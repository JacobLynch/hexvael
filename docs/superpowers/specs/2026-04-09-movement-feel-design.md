# Movement Feel Design

Build order step 2, movement half. Make the ritualist feel genuinely good to walk around as, with weight, responsiveness, a dodge, and enough juice to sell that the character exists in the world. Combat (frost bolt, enemies, hit feedback) is a separate effort and explicitly out of scope for this spec.

---

## Scope

"Done" means:

1. Walking around in a browser tab feels good — responsive, grounded, not slippery
2. A dedicated dodge button exists with i-frames, cooldown, and visible feedback
3. The camera follows the player with a deadzone and leads toward the mouse cursor
4. Visual juice — dodge trail, footstep dust, wall bump particles, screen shake, walk state pulse, i-frame tint — is wired up and reads clearly
5. Input is routed through an abstraction layer so gamepad support slots in later without refactoring
6. Client and server run identical movement math via a shared `advance(dt)` function, no rubber-banding under normal latency
7. Two browsers can watch each other walk and dodge with smooth remote rendering
8. GUT tests pass for the new movement math, dodge state machine, reconciliation, and input encoding

Explicitly **not** done: combat, spells, enemies, health/damage, sprites beyond shapes, sound effects, real gamepad implementation (stub only).

---

## Design Decisions

| Decision | Choice | Notes |
|---|---|---|
| Aim paradigm | WASD move + mouse aim | Decoupled movement/aim, ritualist can backpedal while aiming |
| Input abstraction | `InputProvider` interface, keyboard+mouse impl now, gamepad stubbed | Controller support later is a constructor swap |
| Movement character | Light acceleration/friction ("light B") | Grounded ritualist feel, surface modifiers (ice) extend the same math |
| Dodge | Yes, dedicated button with i-frames | Table stakes for "feels great" |
| Dodge direction | Input direction if held, else aim direction | Hades pattern |
| Dodge params | 140px range, 200ms duration, 700ms cooldown, full-duration i-frames | Tunable via `MovementParams` resource |
| Visual representation | Colored shapes + facing indicator | No sprite work this round |
| Camera | Deadzone + soft mouse lookahead | Hotline Miami / Nuclear Throne pattern |
| Facing direction | Instant snap to mouse | Smoothing feels like input lag |
| Juice in scope | Dodge trail, footstep dust, dodge shake, wall bump, walk pulse, i-frame tint | All six |
| State structure | `MovementParams` Resource + state on `PlayerEntity` + state machine in `advance()` | Matches "data-driven" philosophy, future-proofs for surface/status/gear |

---

## Architecture Rules This Spec Establishes

Two new hard rules added to `CLAUDE.md` during this brainstorm:

1. **Simulation math is dt-independent.** Every `advance(dt)` function produces the same result regardless of how `dt` is chunked. Use `velocity *= exp(-friction * dt)` not `velocity *= 0.9`. Use `timer -= dt` not `timer -= 1`.
2. **Client and server share simulation code.** Prediction and authoritative simulation call the same function, not reimplementations. Never fork "client prediction logic" from "server logic."

These rules are load-bearing for this design. Violating either causes the local player to rubber-band.

---

## File Layout

**New files:**

```
/shared/movement/movement_params.gd              # Resource: tunable movement knobs
/shared/movement/default_movement_params.tres    # Baseline values
/simulation/entities/player_movement_state.gd    # Enum: WALKING, DODGING
/simulation/input/input_provider.gd              # Abstract interface
/simulation/input/keyboard_mouse_input_provider.gd
/view/world/camera_rig.gd                        # Deadzone + lookahead camera
/view/world/camera_rig.tscn
/view/effects/dodge_trail.gd                     # Afterimage effect
/view/effects/footstep_dust.gd                   # Walk particles
/view/effects/wall_bump.gd                       # Collision particles
/view/effects/screen_shake.gd                    # Camera shake helper
```

**Modified files:**

```
/simulation/entities/player_entity.gd            # advance(dt), accel, friction, dodge state
/simulation/systems/movement_system.gd           # advance_all(dt), richer input dispatch
/simulation/event_bus.gd                         # New signals: dodge_started, dodge_ended, collided, moved
/simulation/network/input_buffer.gd              # New input fields
/simulation/network/snapshot.gd                  # New per-entity fields
/simulation/network/net_client.gd                # New prediction flow, richer reconciliation
/simulation/network/net_server.gd                # Dodge cooldown validation
/view/world/player_view.gd                       # Facing indicator, i-frame tint, walk pulse
/view/world/world_view.gd                        # Attach camera, subscribe to juice events
/client_main.gd                                  # Use InputProvider abstraction
```

---

## Simulation Layer

### MovementParams Resource

Tunable knobs live in a `Resource` so they can be edited in the Godot inspector, saved to `.tres`, swapped at runtime, and later overridden by surfaces/statuses/gear without touching any code.

```gdscript
class_name MovementParams extends Resource

@export var top_speed: float = 200.0
@export var accel: float = 1800.0              # px/sec² — reach top_speed in ~0.11s
@export var friction: float = 18.0             # exp coeff — halt in ~0.08s after release
@export var dodge_speed: float = 700.0         # px/sec during dodge
@export var dodge_duration: float = 0.2        # seconds
@export var dodge_cooldown: float = 0.7        # seconds, measured from dodge start
@export var dodge_iframe_duration: float = 0.2 # matches dodge_duration for v1
```

A `default_movement_params.tres` sits alongside as the baseline every player spawns with.

### PlayerMovementState enum

```gdscript
class_name PlayerMovementState
const WALKING = 0   # input-driven movement (includes idle)
const DODGING = 1   # locked into dodge, no new input accepted
```

Two states for v1. Shape supports adding more (KNOCKBACK, STUNNED, CHANNELING) later without rewriting `advance()`.

### PlayerEntity — new state fields

```gdscript
var params: MovementParams                 # ref to tunable knobs
var move_input: Vector2 = Vector2.ZERO     # latest WASD input (normalized)
var aim_direction: Vector2 = Vector2.RIGHT # latest aim (unit vector)
var state: int = PlayerMovementState.WALKING
var dodge_direction: Vector2 = Vector2.ZERO
var dodge_time_remaining: float = 0.0
var dodge_cooldown_remaining: float = 0.0
```

`facing_angle` derives from `aim_direction` on demand; no separate field needed.

### PlayerEntity.advance(dt) — the canonical step

This is the single source of movement truth. Called identically by the server tick, client prediction, and client reconciliation replay.

```gdscript
func advance(dt: float) -> void:
    # 1. Tick cooldowns (always, regardless of state)
    if dodge_cooldown_remaining > 0.0:
        dodge_cooldown_remaining = max(0.0, dodge_cooldown_remaining - dt)

    # 2. State-specific velocity computation
    match state:
        PlayerMovementState.WALKING:
            var target = move_input * params.top_speed
            velocity = velocity.move_toward(target, params.accel * dt)
            if move_input.length_squared() < 0.001:
                velocity *= exp(-params.friction * dt)  # dt-independent decay

        PlayerMovementState.DODGING:
            velocity = dodge_direction * params.dodge_speed
            dodge_time_remaining -= dt
            if dodge_time_remaining <= 0.0:
                state = PlayerMovementState.WALKING
                EventBus.player_dodge_ended.emit({"entity_id": player_id})

    # 3. Integrate position with collision
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

    # 4. Movement event for footstep dust (gated to avoid spam)
    if velocity.length_squared() > 1.0:
        EventBus.player_moved.emit({
            "entity_id": player_id,
            "position": position,
            "velocity": velocity,
        })
```

### PlayerEntity.apply_input — ingest, not integrate

```gdscript
func apply_input(input: Dictionary) -> void:
    move_input = input["move_direction"]
    aim_direction = input["aim_direction"]
    if input["dodge_pressed"] and can_dodge():
        start_dodge()
    if input["input_seq"] > last_processed_input_seq:
        last_processed_input_seq = input["input_seq"]

# Public so client prediction in NetClient can gate its own dodge predictions
func can_dodge() -> bool:
    return state == PlayerMovementState.WALKING and dodge_cooldown_remaining <= 0.0

func start_dodge() -> void:
    var dir: Vector2 = move_input.normalized() if move_input.length_squared() > 0.01 else aim_direction
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

### MovementSystem changes

- Remains the player registry.
- `tick_all()` renamed to `advance_all(dt)` — iterates players, calls `player.advance(dt)`.
- `process_inputs_for_player()` still dequeues inputs from the buffer and calls `player.apply_input(input)`, but now inputs carry the richer dictionary.
- **No dodge logic lives in MovementSystem.** Dodge is a state on PlayerEntity. MovementSystem just drives the tick.

### New EventBus signals

```gdscript
signal player_dodge_started(event: Dictionary)  # entity_id, position, direction
signal player_dodge_ended(event: Dictionary)    # entity_id
signal player_collided(event: Dictionary)       # entity_id, position, normal, velocity
signal player_moved(event: Dictionary)          # entity_id, position, velocity
```

All event payloads follow the "events carry full context" rule — view listeners filter on what they care about.

---

## Network Protocol

### Input message — new fields

```gdscript
{
    "type": PLAYER_INPUT,
    "tick": int,                    # existing
    "input_seq": u32,               # existing
    "move_direction": Vector2,      # renamed from "direction" for clarity
    "aim_direction": Vector2,       # NEW — unit vector toward mouse
    "dodge_pressed": bool,          # NEW — edge-triggered
}
```

**Binary layout:** `dodge_pressed` = 1 byte, `aim_direction` = 8 bytes (two float32s). Growth: 9 bytes per input, 180 B/sec/player at 20Hz. Negligible.

### Edge-trigger semantics for dodge_pressed

The `KeyboardMouseInputProvider` latches `Input.is_action_just_pressed("dodge")` into the outgoing input for exactly one tick. `consume_dodge_press()` returns-and-clears. This guarantees one `dodge_pressed = true` per real button press, even if display-frame cadence and input-send cadence don't match up.

### Server dodge validation

When `NetServer` dispatches a dequeued input, `apply_input()` checks `_can_dodge()` before starting a dodge. If the player is already dodging or on cooldown, the bit is silently ignored. Server is authoritative; client may predict wrong and reconciliation snaps it back.

### Snapshot format — new per-entity fields

```gdscript
{
    "entity_id": int,              # existing
    "position": Vector2,            # existing
    "flags": u8,                    # existing (NONE/MOVING/REMOVED, + new DODGING=4)
    "last_input_seq": u32,          # existing
    "velocity": Vector2,            # NEW
    "aim_direction": Vector2,       # NEW
    "state": u8,                    # NEW
    "dodge_time_remaining": float,  # NEW
}
```

Per-entity payload grows from ~20 bytes to ~37 bytes. Within budget at 8 players × 20Hz with delta compression.

`velocity` in the snapshot powers two things:
- Remote client rendering of the current visual speed (walk pulse amplitude, footstep dust rate)
- Better remote interpolation — extrapolation during the post-snapshot gap uses real velocity instead of pure time-lerp, which naturally handles mid-dodge state

`DODGING` flag lets remote clients detect "remote player started dodging" by diffing the flag across snapshots, kicking off the trail effect at the right moment.

### Client prediction — per-frame loop

```gdscript
func _process(delta):
    if _local_player != null:
        _local_player.move_input = _input_provider.move_direction
        _local_player.aim_direction = _input_provider.aim_direction
        if _input_provider.dodge_pressed_this_frame() and _local_player.can_dodge():
            _local_player.start_dodge()        # client predicts dodge immediately
        _local_player.advance(delta)           # dt-independent
```

Note: the prediction path calls `_start_dodge()` directly when the display-frame input says so. The dodge flag is *also* latched into the next outgoing input for the server to validate. Both sides converge on the same outcome if the client was right.

### Reconciliation — restores full dodge state

```gdscript
func _reconcile_local_player(snap):
    # ... unpack snapshot, capture visual_before ...
    _local_player.position = server_pos
    _local_player.velocity = server_data["velocity"]
    _local_player.state = server_data["state"]
    _local_player.dodge_time_remaining = server_data["dodge_time_remaining"]
    # Discard already-acked inputs, replay unacked via shared advance function
    for pending in _pending_inputs:
        _local_player.apply_input(pending)
        _local_player.advance(MessageTypes.TICK_INTERVAL_MS / 1000.0)
    # ... visual offset blending ...
```

Critical: all dodge-related state is restored from the server snapshot, not just position. A mid-dodge snapshot that only restored position would leave stale dodge timers and diverge on replay.

---

## View Layer

### Camera rig

A `Camera2D`-derived node owned by `WorldView`, tracking the local player.

```gdscript
class_name CameraRig extends Camera2D

@export var deadzone_size: Vector2 = Vector2(40, 30)
@export var lookahead_max: float = 80.0
@export var lookahead_ramp: float = 140.0
@export var follow_smoothing: float = 8.0

var _net_client: NetClient  # injected via initialize()
var _target_position: Vector2 = Vector2.ZERO
var _shake_offset: Vector2 = Vector2.ZERO

func initialize(net_client: NetClient) -> void:
    _net_client = net_client

func _process(delta: float):
    if _net_client == null: return
    var local_pos = _net_client.get_local_player_position()
    if local_pos == null: return

    # Deadzone
    var diff = local_pos - _target_position
    if abs(diff.x) > deadzone_size.x * 0.5:
        _target_position.x = local_pos.x - sign(diff.x) * deadzone_size.x * 0.5
    if abs(diff.y) > deadzone_size.y * 0.5:
        _target_position.y = local_pos.y - sign(diff.y) * deadzone_size.y * 0.5

    # Mouse lookahead, capped
    var mouse_offset = get_local_mouse_position()
    var amt = clampf(mouse_offset.length() / lookahead_ramp, 0.0, 1.0)
    var lookahead = mouse_offset.normalized() * lookahead_max * amt

    var target = _target_position + lookahead + _shake_offset
    position = position.lerp(target, 1.0 - exp(-follow_smoothing * delta))
```

Camera owns the shake offset. Every juice effect that wants a shake calls `camera_rig.add_shake(amplitude, duration)`. Single source of truth, no system fighting over the camera.

### PlayerView — facing indicator, tint, walk pulse

- **Facing indicator:** a 6px line drawn from the square center in the direction of `aim_direction` (from simulation state, authoritative even for "which way am I pointing").
- **i-frame tint:** `modulate = Color(1.4, 1.4, 1.8)` while `state == DODGING`, else `Color.WHITE`.
- **Walk pulse:** subtle `Vector2(1.03, 0.97)` target scale while moving, `Vector2.ONE` while idle, lerped at framerate-independent rate.

### Juice effect nodes

All four live under `WorldView` and subscribe to `EventBus` in `_ready()`, unsubscribe in `_exit_tree()`. Zero simulation knowledge, zero state mutation back into sim.

| Node | Subscribes to | Behavior |
|---|---|---|
| `DodgeTrail` | `player_dodge_started`, `player_dodge_ended` | Spawns a per-dodge trail (Line2D afterimage), despawns after `duration + 150ms` fade |
| `FootstepDust` | `player_moved` | Per-entity distance accumulator; every ~24px, spawns a small `CPUParticles2D` burst at foot position |
| `WallBump` | `player_collided` | If `velocity.length() > threshold`, spawns particle burst along normal + calls `camera_rig.add_shake(1.5, 0.08)` |
| `ScreenShakeOnDodge` | `player_dodge_started` | Local player only; calls `camera_rig.add_shake(1.0, 0.05)` — 1px, 50ms |

### Visual representation

Player = 16x16 colored square (existing), plus a 6px facing line, plus modulate-based dodge tint. No sprites this round. Sprite work is step 2 combat, or step 3, or its own dedicated pass.

---

## Input Abstraction

```gdscript
class_name InputProvider extends RefCounted

var move_direction: Vector2  # read each frame
var aim_direction: Vector2   # read each frame (unit vector from player toward cursor)
func dodge_pressed_this_frame() -> bool: pass
func consume_dodge_press() -> bool: pass  # returns true once, then clears latch
```

```gdscript
class_name KeyboardMouseInputProvider extends InputProvider
# Uses Input.get_vector("move_left", "move_right", "move_up", "move_down")
# Uses get_viewport().get_mouse_position() + player world position for aim_direction
# Uses Input.is_action_just_pressed("dodge") for edge-triggered dodge
# Latches dodge into _dodge_latched; consume_dodge_press returns and clears
```

`client_main.gd` holds one `InputProvider` and reads from it. `_input_provider = KeyboardMouseInputProvider.new()` today; a `GamepadInputProvider` can slot in later with zero other changes.

The concrete `KeyboardMouseInputProvider` lives in `/simulation/input/` and reads view-side APIs (`get_viewport()`, `Input`). This is a deliberate exception to the strict "sim has no view awareness" rule: input originates at the hardware, which is a view-side concept, but the output of the provider is pure simulation data (`Vector2`, `bool`). The provider is the translation boundary.

---

## Testing Strategy

### Headless unit tests

1. **`test_player_entity_advance.gd`** — `PlayerEntity.advance(dt)` math
   - Accel reaches top speed in expected time
   - Friction decays velocity to near-zero after input release
   - **dt-independence canary:** `advance(0.1)` once vs `advance(0.01)` ten times converge within 1e-4 tolerance
   - Idle tick stays at rest
   - Diagonal input normalizes (no speed advantage)

2. **`test_player_dodge_state_machine.gd`** — state transitions
   - Dodge from WALKING with valid cooldown transitions to DODGING
   - Dodge uses `move_input` direction if held
   - Dodge falls back to `aim_direction` if no move input
   - Dodge while already DODGING is a no-op
   - Dodge with cooldown remaining is a no-op
   - After `dodge_duration` elapsing via `advance()`, state returns to WALKING
   - Cooldown ticks down during both WALKING and DODGING
   - Dodge respects collision (wall doesn't phase)

3. **`test_player_collision.gd`** — extend existing wall/player tests
   - Wall bump during DODGING emits `player_collided` event with correct payload
   - Regression guard for phasing through walls during dodge

4. **`test_movement_system_inputs.gd`** — extend existing
   - New input dict format is dequeued and dispatched correctly
   - `advance_all(dt)` iterates all registered players

5. **`test_reconciliation.gd`** — new, the critical sync-path test
   - Replaying N pending inputs after reconciliation produces the same position as pure server simulation
   - Reconciling mid-dodge correctly restores all dodge state
   - Reconciling a client-predicted dodge the server rejected correctly rolls back to WALKING
   - **Shared-simulation-code canary:** this test runs both client and server paths and asserts convergence

6. **`test_input_encoding.gd`** — extend existing `test_net_message.gd`
   - New input fields round-trip through binary encode/decode
   - Edge-triggered dodge latching behavior
   - Snapshot encoding/decoding round-trips all new per-entity fields

7. **`test_movement_params.gd`** — new, small
   - Default params load with expected values
   - Swapping params at runtime affects the next `advance()` call (proves runtime-swap for future gear/surface integration)

### What we do not unit-test

Camera feel, particle visuals, dodge trail rendering, screen shake, real mouse input — all manually playtested. GUT can't meaningfully simulate hardware or evaluate feel.

### Manual playtest checklist

- Walk in all 8 directions, feels responsive and grounded
- Dodge works from standing still (aim direction)
- Dodge works while walking (move direction)
- Dodge cooldown enforced (can't spam)
- Dodge i-frame visual distinct and readable
- Camera follows with deadzone, leads toward mouse
- Footstep dust spawns at reasonable rate, not spammy
- Wall bumps have particle + micro-shake
- Screen shake on dodge is felt subconsciously, not visually distracting
- Two browsers: remote player dodge is smooth and readable
- No rubber-banding on local player during normal latency

### Verification

1. `godot --headless -s addons/gut/gut_cmdln.gd` — all GUT tests pass
2. Full manual playtest checklist passes with two browser clients

---

## Out of Scope / Deferred

- **Combat** — frost bolt, enemies, damage, health, hit feedback. Separate brainstorm and spec.
- **Sprites** — ritualist art comes later (probably alongside combat or as its own pass)
- **Gamepad implementation** — only the abstraction layer ships; real gamepad handling is a later `GamepadInputProvider` class
- **Sound effects** — footstep audio, dodge whoosh, wall bump thud. Audio pass is its own scope.
- **Surface effects** (ice, fire, slow) — step 3 of the build order. This spec only ensures `MovementParams` can be swapped cleanly later.
- **Dodge upgrades / charges / gear mods** — step 3+. Dodge is one fixed ability for now.
- **Multiple movement states beyond WALKING/DODGING** — KNOCKBACK, STUNNED, CHANNELING will land when their driving systems do.
