extends Node2D

const PlayerMovementState = preload("res://simulation/entities/player_movement_state.gd")

var player_id: int = -1
var is_local: bool = false
var _target_position: Vector2 = Vector2.ZERO

var _visual: ColorRect
var _facing_line: Line2D
var _base_color: Color


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

	# Walk pulse — subtle stretch while moving, rest at 1.0 while idle
	var target_scale = Vector2(1.03, 0.97) if velocity_magnitude > 1.0 else Vector2.ONE
	_visual.scale = _visual.scale.lerp(target_scale, 1.0 - exp(-10.0 * delta))


func _process(_delta: float):
	position = _target_position
