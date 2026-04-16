# godot/view/effects/damage_number.gd
extends Label

var velocity: Vector2 = Vector2(0, -60)
var lifetime: float = 0.8
var _age: float = 0.0


func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 16)
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 2)
	z_index = 100


func _process(delta: float) -> void:
	_age += delta
	position += velocity * delta
	velocity.y += 80 * delta  # Slight gravity

	# Fade out
	var progress = _age / lifetime
	modulate.a = 1.0 - progress

	if _age >= lifetime:
		queue_free()
