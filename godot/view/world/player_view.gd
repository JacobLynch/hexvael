extends Node2D

var player_id: int = -1
var is_local: bool = false
var _target_position: Vector2 = Vector2.ZERO


func _ready():
	var rect = ColorRect.new()
	rect.size = Vector2(16, 16)
	rect.position = Vector2(-8, -8)
	rect.name = "Visual"
	add_child(rect)


func initialize(id: int, spawn_pos: Vector2, local: bool) -> void:
	player_id = id
	is_local = local
	position = spawn_pos
	_target_position = spawn_pos
	var rect = $Visual
	if local:
		rect.color = Color(0.3, 0.8, 1.0)
	else:
		rect.color = Color(1.0, 0.4, 0.3)


func update_position(new_pos: Vector2) -> void:
	_target_position = new_pos


func _process(_delta: float):
	position = _target_position
