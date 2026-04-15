class_name FrostCling
extends Node2D
## Ice crystals that cling to an enemy after being hit by frost bolt.
## Follows the target entity and fades out.

const LIFETIME: float = 0.3
const CRYSTAL_COUNT: int = 4
const DRIFT_SPEED: float = 15.0

var target_node: Node2D = null
var _crystals: Array[Polygon2D] = []
var _crystal_velocities: Array[Vector2] = []


func _ready() -> void:
	_spawn_crystals()
	_start_fade()


func _spawn_crystals() -> void:
	for i in CRYSTAL_COUNT:
		var crystal := Polygon2D.new()
		var size: float = 3.0 + randf() * 4.0
		# Small angular shard shape
		crystal.polygon = PackedVector2Array([
			Vector2(-size, 0),
			Vector2(0, -size * 0.6),
			Vector2(size * 0.8, 0),
			Vector2(0, size * 0.5),
		])
		crystal.color = Color(0.85, 0.95, 1.0, 0.9)
		crystal.rotation = randf() * TAU
		# Random offset from center
		var offset_angle: float = randf() * TAU
		var offset_dist: float = 8.0 + randf() * 12.0
		crystal.position = Vector2.from_angle(offset_angle) * offset_dist
		add_child(crystal)
		_crystals.append(crystal)
		# Drift outward slowly
		_crystal_velocities.append(Vector2.from_angle(offset_angle) * DRIFT_SPEED)


func _start_fade() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, LIFETIME)
	tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	# Follow target if valid
	if is_instance_valid(target_node):
		global_position = target_node.global_position

	# Drift crystals outward
	for i in _crystals.size():
		if i < _crystal_velocities.size():
			_crystals[i].position += _crystal_velocities[i] * delta
			_crystals[i].rotation += (randf() - 0.5) * 3.0 * delta
