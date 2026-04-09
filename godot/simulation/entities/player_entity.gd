class_name PlayerEntity
extends CharacterBody2D

const SPEED: float = 200.0

var player_id: int = -1
var last_processed_input_seq: int = 0


func initialize(id: int, spawn_position: Vector2) -> void:
	player_id = id
	position = spawn_position


func apply_input(direction: Vector2) -> void:
	if direction.length_squared() > 0.0:
		velocity = direction.normalized() * SPEED
	else:
		velocity = Vector2.ZERO


func tick() -> void:
	var delta: float = MessageTypes.TICK_INTERVAL_MS / 1000.0
	var motion: Vector2 = velocity * delta
	var collision = move_and_collide(motion)
	if collision:
		# Slide along the wall with remaining motion
		var remainder = collision.get_remainder()
		move_and_collide(remainder.slide(collision.get_normal()))


func to_snapshot_data() -> Dictionary:
	var flags = MessageTypes.EntityFlags.NONE
	if velocity.length_squared() > 0.0:
		flags = MessageTypes.EntityFlags.MOVING
	return {
		"entity_id": player_id,
		"position": position,
		"flags": flags,
		"last_input_seq": last_processed_input_seq,
	}
