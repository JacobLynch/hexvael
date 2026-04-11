extends Node2D

## Spawns a brief flash + particle burst at the death position.
## Self-destructs after the animation completes.

var _flash: ColorRect


func _ready():
	_flash = ColorRect.new()
	_flash.size = Vector2(20, 20)
	_flash.position = Vector2(-10, -10)
	_flash.color = Color(1.0, 1.0, 0.7, 0.9)
	add_child(_flash)

	var tween = create_tween()
	tween.tween_property(_flash, "modulate:a", 0.0, 0.25)
	tween.parallel().tween_property(_flash, "scale", Vector2(2.0, 2.0), 0.15)
	tween.parallel().tween_property(_flash, "scale", Vector2.ZERO, 0.25).set_delay(0.15)
	tween.tween_callback(queue_free)
