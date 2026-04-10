class_name KeyboardMouseInputProvider
extends InputProvider
## Keyboard + mouse input for PC. Reads WASD for movement and the mouse
## cursor's world position for aim. Latches "dodge" edge press so it
## survives the gap between display-frame polling and tick-rate send.

var _dodge_latched: bool = false
var _viewport: Viewport


func _init(viewport: Viewport) -> void:
	_viewport = viewport


func poll(player_world_position: Vector2) -> void:
	move_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# Aim direction: unit vector from player to mouse (in world coords)
	# Use camera's global mouse position if a camera exists; otherwise fall back
	# to viewport mouse position (which is in screen coords, not world).
	var mouse_world: Vector2
	var cam = _viewport.get_camera_2d()
	if cam != null:
		mouse_world = cam.get_global_mouse_position()
	else:
		mouse_world = _viewport.get_mouse_position()
	var diff = mouse_world - player_world_position
	if diff.length_squared() > 0.01:
		aim_direction = diff.normalized()
	# else keep prior aim_direction

	if Input.is_action_just_pressed("dodge"):
		_dodge_latched = true


func dodge_pressed_this_frame() -> bool:
	return _dodge_latched


func consume_dodge_press() -> bool:
	var v = _dodge_latched
	_dodge_latched = false
	return v
