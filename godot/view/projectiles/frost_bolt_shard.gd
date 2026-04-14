class_name FrostBoltShard
extends Node2D
## Single trailing ice shard that drifts and fades.

const LIFETIME: float = 0.4

var velocity: Vector2 = Vector2.ZERO
var rot_speed: float = 0.0


func _ready() -> void:
	# Randomize initial rotation
	rotation = randf() * TAU
	rot_speed = (randf() - 0.5) * 8.0

	# Tween fade and shrink
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, LIFETIME)
	tween.tween_property(self, "scale", Vector2(0.3, 0.3), LIFETIME)
	tween.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	position += velocity * delta
	rotation += rot_speed * delta
	velocity *= 0.95  # Drag
