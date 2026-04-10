class_name CameraRig
extends Camera2D

@export var deadzone_size: Vector2 = Vector2(40.0, 30.0)
@export var lookahead_max: float = 80.0
@export var lookahead_ramp: float = 140.0
@export var follow_smoothing: float = 8.0
@export var shake_decay: float = 20.0  # exp coeff for shake decay

var _net_client: NetClient
var _target_position: Vector2 = Vector2.ZERO
var _shake_amplitude: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO


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
