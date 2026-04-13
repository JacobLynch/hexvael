class_name PlayerEntity
extends CharacterBody2D

var player_id: int = -1
var last_processed_input_seq: int = 0

# Movement state
var params: MovementParams = preload("res://shared/movement/default_movement_params.tres")
var move_input: Vector2 = Vector2.ZERO       # latest WASD direction (raw, not normalized)
var aim_direction: Vector2 = Vector2.RIGHT   # latest aim unit vector (used later)
var state: int = PlayerMovementState.WALKING

# Dodge state
var dodge_direction: Vector2 = Vector2.ZERO
var dodge_time_remaining: float = 0.0
var dodge_cooldown_remaining: float = 0.0

# Collision tracking (for remote-player wall bump synthesis)
# Increments on every wall collision and wraps at 256 (u8).
# Clients detect counter changes in the snapshot to fire synthetic player_collided events.
var collision_count: int = 0
var last_collision_normal: Vector2 = Vector2.ZERO

# When true, advance() and start_dodge() skip EventBus emissions.
# Used by NetClient reconciliation replay so view-side juice doesn't
# re-fire for every replayed input.
var _suppress_events: bool = false

var _cached_collision_radius: float = -1.0


func initialize(id: int, spawn_position: Vector2) -> void:
	player_id = id
	position = spawn_position


# Ingest: called by MovementSystem when dequeuing inputs.
# Takes a Dictionary with keys: move_direction, aim_direction (optional), input_seq (optional).
func apply_input(input: Dictionary) -> void:
	move_input = input.get("move_direction", Vector2.ZERO)
	# aim_direction is always stored as a unit vector — normalize at ingest so every
	# downstream consumer (facing indicator, dodge fallback) sees a valid unit vector.
	# If the incoming aim is zero-length (e.g., no data yet), preserve the existing value.
	var incoming_aim: Vector2 = input.get("aim_direction", aim_direction)
	if incoming_aim.length_squared() > 0.001:
		aim_direction = incoming_aim.normalized()
	var flags: int = input.get("action_flags", 0)
	if (flags & MessageTypes.InputActionFlags.DODGE) != 0 and can_dodge():
		start_dodge()
	if input.has("input_seq") and input["input_seq"] > last_processed_input_seq:
		last_processed_input_seq = input["input_seq"]


# Public — NetClient prediction calls this to gate its own dodge starts
func can_dodge() -> bool:
	return state == PlayerMovementState.WALKING and dodge_cooldown_remaining <= 0.0


## Returns true while the dodge is in its i-frame window. For v1, dodge_iframe_duration
## matches dodge_duration so this is equivalent to "is currently dodging" — but the
## indirection lets future combat code reduce iframe_duration to a slice of the dodge
## without changing callers.
func is_iframe_active() -> bool:
	if state != PlayerMovementState.DODGING:
		return false
	var elapsed: float = params.dodge_duration - dodge_time_remaining
	return elapsed < params.dodge_iframe_duration


func start_dodge() -> void:
	# Defensive guard — silently no-op if already dodging. All current callers
	# gate on can_dodge() first, but this prevents subtle state resets if that
	# contract is ever broken.
	if state == PlayerMovementState.DODGING:
		return
	var dir: Vector2
	if move_input.length_squared() > 0.001:
		dir = move_input.normalized()
	else:
		dir = aim_direction
	state = PlayerMovementState.DODGING
	dodge_direction = dir
	dodge_time_remaining = params.dodge_duration
	dodge_cooldown_remaining = params.dodge_cooldown
	# Hard-set velocity — impulse semantics. The dodge instantly commits to its
	# direction, bypassing prior walking velocity. Without this, midpoint integration
	# in advance() would blend pre-dodge velocity with dodge velocity on the first tick.
	velocity = dir * params.dodge_speed
	if not _suppress_events:
		EventBus.player_dodge_started.emit({
			"entity_id": player_id,
			"position": position,
			"direction": dir,
		})


# Canonical movement step. Called by:
#   - Server tick  -> advance(TICK_INTERVAL)
#   - Client prediction (per display frame) -> advance(frame_delta)
#   - Client reconciliation replay -> advance(TICK_INTERVAL) once per pending input
# MUST be dt-independent — same result regardless of how dt is chunked.
func advance(dt: float) -> void:
	# Capture pre-step velocity for midpoint position integration (dt-independent).
	var v_old: Vector2 = velocity

	# Tick cooldown regardless of state
	if dodge_cooldown_remaining > 0.0:
		dodge_cooldown_remaining = max(0.0, dodge_cooldown_remaining - dt)

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

		PlayerMovementState.DODGING:
			velocity = dodge_direction * params.dodge_speed
			dodge_time_remaining -= dt
			if dodge_time_remaining <= 0.0:
				state = PlayerMovementState.WALKING
				if not _suppress_events:
					EventBus.player_dodge_ended.emit({
						"entity_id": player_id,
						"position": position,
						"direction": dodge_direction,
					})

	# Midpoint integration: average pre- and post-step velocity for position.
	# This ensures position is dt-independent during the accel ramp, not just at
	# steady state. Using velocity * dt (Euler forward) diverges between coarse
	# and fine steps because the velocity changes over the interval.
	var motion: Vector2 = (v_old + velocity) / 2.0 * dt
	var collision = move_and_collide(motion)
	if collision:
		var remainder = collision.get_remainder()
		move_and_collide(remainder.slide(collision.get_normal()))
		# Always update counter and normal — even during reconciliation replay
		# (_suppress_events true) — so client and server stay in sync on the counter.
		collision_count = (collision_count + 1) % 256
		last_collision_normal = collision.get_normal()
		if not _suppress_events:
			EventBus.player_collided.emit({
				"entity_id": player_id,
				"position": position,
				"normal": last_collision_normal,
				"velocity": velocity,
			})

	# Movement event (gated to avoid idle spam)
	if velocity.length_squared() > 1.0:
		if not _suppress_events:
			EventBus.player_moved.emit({
				"entity_id": player_id,
				"position": position,
				"velocity": velocity,
			})


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


## Returns the entity's world-space AABB based on its CollisionShape2D.
## Preferred over get_collision_radius for rectangular shapes — avoids
## the inscribed-circle under-approximation that misses corners.
func get_collision_rect() -> Rect2:
	var shape_node := $CollisionShape2D as CollisionShape2D
	var shape := shape_node.shape
	var half: Vector2
	if shape is RectangleShape2D:
		half = (shape as RectangleShape2D).size / 2.0
	elif shape is CircleShape2D:
		var r := (shape as CircleShape2D).radius
		half = Vector2(r, r)
	else:
		push_warning("PlayerEntity: unknown collision shape, using 16 px fallback")
		half = Vector2(16, 16)
	return Rect2(position - half, half * 2.0)


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
		"collision_count": collision_count,
		"last_collision_normal": last_collision_normal,
	}
