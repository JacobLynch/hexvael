class_name FrostBoltVisual
extends Node2D
## Visual representation of the frost bolt projectile.
## Handles light pulsing synchronized with the glow shader.

@onready var light: PointLight2D = $Light
@onready var motes: CPUParticles2D = $Motes

const PULSE_SPEED: float = 12.0
const MIN_ENERGY: float = 0.8
const MAX_ENERGY: float = 1.2

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	if light:
		var pulse = MIN_ENERGY + (MAX_ENERGY - MIN_ENERGY) * (0.5 + 0.5 * sin(_time * PULSE_SPEED))
		light.energy = pulse
