class_name FrostBoltImpact
extends Node2D
## Impact shatter effect for frost bolt. Spawns angular fragments that scatter.

const DURATION: float = 0.5
const FRAGMENT_COUNT: int = 12

@onready var flash: Polygon2D = $Flash
@onready var light: PointLight2D = $Light

var _fragments: Array[Node2D] = []


func _ready() -> void:
	_spawn_fragments()
	_animate()


func _spawn_fragments() -> void:
	for i in FRAGMENT_COUNT:
		var angle = (float(i) / FRAGMENT_COUNT) * TAU + randf() * 0.3
		var speed = 150.0 + randf() * 200.0
		var frag = _create_fragment()
		frag.set_meta("velocity", Vector2.from_angle(angle) * speed)
		frag.set_meta("rot_speed", (randf() - 0.5) * 10.0)
		frag.rotation = randf() * TAU
		add_child(frag)
		_fragments.append(frag)


func _create_fragment() -> Polygon2D:
	var frag = Polygon2D.new()
	var size = 4.0 + randf() * 6.0
	# Angular shard shape
	frag.polygon = PackedVector2Array([
		Vector2(-size, 0),
		Vector2(-size * 0.3, -size * 0.5),
		Vector2(size, -size * 0.2),
		Vector2(size * 0.6, size * 0.4),
		Vector2(-size * 0.3, size * 0.5),
	])
	frag.color = Color(0.75, 0.9, 1.0, 0.9)
	return frag


func _animate() -> void:
	var tween = create_tween()

	# Flash burst
	if flash:
		flash.scale = Vector2(0.3, 0.3)
		flash.modulate.a = 1.0
		var flash_tween = create_tween()
		flash_tween.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.1)
		flash_tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.1)

	# Light fade
	if light:
		var light_tween = create_tween()
		light_tween.tween_property(light, "energy", 0.0, 0.15)

	# Self-destruct after duration
	tween.tween_interval(DURATION)
	tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	for frag in _fragments:
		if not is_instance_valid(frag):
			continue
		var vel: Vector2 = frag.get_meta("velocity", Vector2.ZERO)
		var rot_speed: float = frag.get_meta("rot_speed", 0.0)

		frag.position += vel * delta
		frag.rotation += rot_speed * delta

		# Slow down and shrink
		vel *= 0.95
		frag.set_meta("velocity", vel)
		frag.scale *= (1.0 - delta * 2.0)
		frag.modulate.a -= delta * 2.0
