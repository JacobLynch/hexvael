class_name FrostBoltMuzzle
extends Node2D
## Muzzle flash effect for frost bolt. Self-destructs after animation.

const DURATION: float = 0.15

var direction: Vector2 = Vector2.RIGHT

@onready var flash: Polygon2D = $Flash
@onready var particles: CPUParticles2D = $Particles
@onready var light: PointLight2D = $Light
@onready var vapor: CPUParticles2D = $Vapor


func _ready() -> void:
	rotation = direction.angle()
	if particles:
		particles.emitting = true
	if vapor:
		vapor.emitting = true
	_animate()


func _animate() -> void:
	var tween = create_tween()
	tween.set_parallel(true)

	# Flash expands and fades
	if flash:
		flash.scale = Vector2(0.5, 0.5)
		tween.tween_property(flash, "scale", Vector2(1.5, 1.5), DURATION)
		tween.tween_property(flash, "modulate:a", 0.0, DURATION)

	# Light fades
	if light:
		tween.tween_property(light, "energy", 0.0, DURATION * 0.7)

	tween.chain().tween_callback(queue_free)
