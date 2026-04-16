extends Node2D

const PlayerMovementState = preload("res://simulation/entities/player_movement_state.gd")

var player_id: int = -1
var is_local: bool = false
var _target_position: Vector2 = Vector2.ZERO

var _visual: ColorRect
var _facing_line: Line2D
var _base_color: Color

const RECOIL_ENABLED: bool = true  ## Easy toggle to disable sprite recoil
const RECOIL_DECAY: float = 20.0

var _recoil_offset: Vector2 = Vector2.ZERO


func _ready():
	_visual = ColorRect.new()
	_visual.size = Vector2(16, 16)
	_visual.position = Vector2(-8, -8)
	_visual.name = "Visual"
	add_child(_visual)

	_facing_line = Line2D.new()
	_facing_line.width = 2.0
	_facing_line.default_color = Color(1.0, 1.0, 1.0, 0.9)
	_facing_line.points = PackedVector2Array([Vector2.ZERO, Vector2(6.0, 0.0)])
	_facing_line.name = "FacingLine"
	add_child(_facing_line)


func initialize(id: int, spawn_pos: Vector2, local: bool) -> void:
	player_id = id
	is_local = local
	position = spawn_pos
	_target_position = spawn_pos
	if local:
		_base_color = Color(0.3, 0.8, 1.0)
	else:
		_base_color = Color(1.0, 0.4, 0.3)
	_visual.color = _base_color


func update_position(new_pos: Vector2) -> void:
	_target_position = new_pos


## Called by WorldView each frame with the authoritative aim direction,
## the movement state, and current velocity (for walk pulse).
func update_visual_state(aim_dir: Vector2, state: int, velocity_magnitude: float, delta: float) -> void:
	# Facing line — rotate to match aim direction
	if aim_dir.length_squared() > 0.01:
		_facing_line.rotation = aim_dir.angle()

	# i-frame tint while dodging
	if state == PlayerMovementState.DODGING:
		_visual.color = Color(1.4, 1.4, 1.8)
	else:
		_visual.color = _base_color

	# Walk pulse — stretch the whole player node while moving, rest at 1.0 while idle.
	# Scale self (the Node2D) rather than _visual (the ColorRect) so the facing line
	# also breathes with the body, and because ColorRect.scale is less reliable than
	# Node2D.scale for visual transforms.
	var target_scale = Vector2(1.12, 0.92) if velocity_magnitude > 1.0 else Vector2.ONE
	self.scale = self.scale.lerp(target_scale, 1.0 - exp(-10.0 * delta))


## Apply visual recoil nudge opposite to shot direction.
## Called by WorldView on projectile_spawned for this player.
func apply_recoil(direction: Vector2, distance: float) -> void:
	if not RECOIL_ENABLED or distance <= 0.0:
		return
	_recoil_offset = -direction.normalized() * distance


func set_ghost_visual(is_ghost: bool) -> void:
	if is_ghost:
		modulate = Color(0.5, 0.5, 0.8, 0.5)  # Translucent blue
	else:
		modulate = Color.WHITE


func _process(delta: float) -> void:
	# Decay recoil
	if _recoil_offset.length_squared() > 0.001:
		_recoil_offset *= exp(-RECOIL_DECAY * delta)
	else:
		_recoil_offset = Vector2.ZERO

	position = _target_position + _recoil_offset
