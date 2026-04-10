class_name CameraRig
extends Camera2D

@export var zoom_factor: float = 3.0  # higher = more zoomed in (Godot 4 convention)
@export var min_zoom: float = 1.0
@export var max_zoom: float = 6.0
@export var zoom_step: float = 0.25  # how much each scroll wheel tick changes zoom
@export var deadzone_size: Vector2 = Vector2(40.0, 30.0)
@export var lookahead_max: float = 50.0   # max world-pixel offset toward mouse cursor
@export var lookahead_ramp: float = 180.0 # mouse-player world distance at which lookahead reaches max
@export var follow_smoothing: float = 8.0
@export var shake_decay: float = 20.0  # exp coeff for shake decay

var _net_client: NetClient
var _target_position: Vector2 = Vector2.ZERO
var _shake_amplitude: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	zoom = Vector2(zoom_factor, zoom_factor)
	# Force this camera to be the active one. Without this, any other Camera2D
	# already added to the scene tree (e.g. an editor placeholder) keeps current.
	make_current()


func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel and macOS two-finger trackpad scroll both fire as MouseButton wheel events
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_zoom(zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_zoom(-zoom_step)
	# macOS trackpad pinch-to-zoom gesture (also Magic Mouse)
	elif event is InputEventMagnifyGesture:
		# event.factor > 1.0 means pinching out (zoom in), < 1.0 means pinching in
		_set_zoom_multiplicative(event.factor)


func _adjust_zoom(delta: float) -> void:
	zoom_factor = clampf(zoom_factor + delta, min_zoom, max_zoom)
	zoom = Vector2(zoom_factor, zoom_factor)


func _set_zoom_multiplicative(factor: float) -> void:
	# Multiplicative zoom feels natural for pinch — small gestures = small change,
	# large pinch = larger change. clampf prevents flying out of bounds.
	zoom_factor = clampf(zoom_factor * factor, min_zoom, max_zoom)
	zoom = Vector2(zoom_factor, zoom_factor)


func initialize(net_client: NetClient) -> void:
	_net_client = net_client


func add_shake(amplitude: float, _duration: float) -> void:
	# Amplitude replaces prior if larger; decays exponentially regardless of duration
	_shake_amplitude = max(_shake_amplitude, amplitude)


func _process(delta: float):
	if _net_client == null:
		return
	var local_pos = _net_client.get_local_player_position()
	if local_pos == null:
		return

	# Deadzone: target stays put unless player exits the box
	var diff = local_pos - _target_position
	if abs(diff.x) > deadzone_size.x * 0.5:
		_target_position.x = local_pos.x - sign(diff.x) * deadzone_size.x * 0.5
	if abs(diff.y) > deadzone_size.y * 0.5:
		_target_position.y = local_pos.y - sign(diff.y) * deadzone_size.y * 0.5

	# Mouse lookahead: offset toward mouse proportional to mouse-player distance
	var mouse_offset = get_local_mouse_position()
	var lookahead = Vector2.ZERO
	if mouse_offset.length_squared() > 0.01:
		var amt = clampf(mouse_offset.length() / lookahead_ramp, 0.0, 1.0)
		lookahead = mouse_offset.normalized() * lookahead_max * amt

	# Shake: random offset, exponential decay.
	# View-only randomness — uses Godot's built-in RNG so we don't drain
	# the deterministic simulation RNG stream (see CLAUDE.md "One RNG instance only").
	if _shake_amplitude > 0.001:
		var rx = randf() * 2.0 - 1.0
		var ry = randf() * 2.0 - 1.0
		_shake_offset = Vector2(rx, ry) * _shake_amplitude
		_shake_amplitude *= exp(-shake_decay * delta)
	else:
		_shake_offset = Vector2.ZERO
		_shake_amplitude = 0.0

	var target = _target_position + lookahead + _shake_offset
	position = position.lerp(target, 1.0 - exp(-follow_smoothing * delta))
