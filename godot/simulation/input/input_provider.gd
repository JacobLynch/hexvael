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

## Returns true and CLEARS the latch. Used by the network send layer
## to guarantee exactly one dodge input per real button press.
func consume_dodge_press() -> bool:
	return false

## Returns true and CLEARS the latch. Used by the network send layer
## to guarantee exactly one fire input per real button press.
func consume_fire_press() -> bool:
	return false

## Returns true if the fire button is currently held down.
## Used for hold-to-fire automatic firing.
func is_fire_held() -> bool:
	return false
