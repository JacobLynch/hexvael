class_name KeyboardMouseInputProvider
extends InputProvider
## Keyboard + mouse input for PC. Reads WASD for movement and the mouse
## cursor's world position for aim. Latches "dodge" edge press so it
## survives the gap between display-frame polling and tick-rate send.

var _dodge_latched: bool = false
var _fire_latch: bool = false
var _viewport: Viewport


func _init(viewport: Viewport) -> void:
	_viewport = viewport


func poll(player_world_position: Vector2) -> void:
	move_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var cam = _viewport.get_camera_2d()
	if cam == null:
		# No camera — can't compute world-space mouse. Keep prior aim_direction.
		# This should only happen briefly during startup; warn if it persists.
		push_warning("KeyboardMouseInputProvider.poll: no Camera2D in viewport, aim_direction frozen")
	else:
		var mouse_world = cam.get_global_mouse_position()
		var diff = mouse_world - player_world_position
		if diff.length_squared() > 0.01:
			aim_direction = diff.normalized()

	if Input.is_action_just_pressed("dodge"):
		_dodge_latched = true
	# Fire latch — polled here rather than via _unhandled_input because
	# InputProvider extends RefCounted and is not in the scene tree, so it
	# does not receive input events. Input.is_action_just_pressed is global
	# and gives us the edge-triggered semantics we need.
	if Input.is_action_just_pressed("fire"):
		_fire_latch = true


func consume_dodge_press() -> bool:
	var v = _dodge_latched
	_dodge_latched = false
	return v


func consume_fire_press() -> bool:
	var v = _fire_latch
	_fire_latch = false
	return v


func is_fire_held() -> bool:
	return Input.is_action_pressed("fire")
