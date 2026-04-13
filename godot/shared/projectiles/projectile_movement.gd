class_name ProjectileMovement
extends RefCounted

## Movement strategy types — stored as int in ProjectileParams for serialization
enum Type {
	STRAIGHT = 0,  # Default: constant velocity in direction
	# Future: GRAVITY = 1, HOMING = 2, SINE_WAVE = 3, etc.
}


## Apply movement to a projectile for one timestep.
## Override in subclasses for different movement behaviors.
static func apply(projectile, dt: float, movement_type: int) -> void:
	match movement_type:
		Type.STRAIGHT:
			_apply_straight(projectile, dt)
		_:
			_apply_straight(projectile, dt)  # Fallback


static func _apply_straight(projectile, dt: float) -> void:
	projectile.position += projectile.direction * projectile.params.speed * dt
