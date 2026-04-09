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
# Takes a Dictionary with keys: move_direction, aim_direction (optional), input_seq (optional).
func apply_input(input: Dictionary) -> void:
	move_input = input.get("move_direction", Vector2.ZERO)
	# aim_direction is always stored as a unit vector — normalize at ingest so every
	# downstream consumer (facing indicator, dodge fallback) sees a valid unit vector.
	# If the incoming aim is zero-length (e.g., no data yet), preserve the existing value.
	var incoming_aim: Vector2 = input.get("aim_direction", aim_direction)
	if incoming_aim.length_squared() > 0.001:
		aim_direction = incoming_aim.normalized()
	if input.has("input_seq") and input["input_seq"] > last_processed_input_seq:
		last_processed_input_seq = input["input_seq"]


# Canonical movement step. Called by:
#   - Server tick  -> advance(TICK_INTERVAL)
#   - Client prediction (per display frame) -> advance(frame_delta)
#   - Client reconciliation replay -> advance(TICK_INTERVAL) once per pending input
# MUST be dt-independent — same result regardless of how dt is chunked.
func advance(dt: float) -> void:
	# Capture pre-step velocity for midpoint position integration (dt-independent).
	var v_old: Vector2 = velocity

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
		# DODGING state handled in Task 4

	# Midpoint integration: average pre- and post-step velocity for position.
	# This ensures position is dt-independent during the accel ramp, not just at
	# steady state. Using velocity * dt (Euler forward) diverges between coarse
	# and fine steps because the velocity changes over the interval.
	var motion: Vector2 = (v_old + velocity) / 2.0 * dt
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
	# NOTE: Task 5 extends this with velocity, aim_direction, state, dodge_time_remaining.
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
