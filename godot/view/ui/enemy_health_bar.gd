# godot/view/ui/enemy_health_bar.gd
# Extends Node2D instead of Control to use world coordinates properly.
extends Node2D

var entity_id: int = -1
var _target_node: Node2D = null
var _max_health: int = 100
var _current_health: int = 100
var _fill_color: Color = Color(0.2, 0.8, 0.2)

const BAR_WIDTH: float = 24.0
const BAR_HEIGHT: float = 4.0
const BAR_OFFSET: Vector2 = Vector2(0, -16)


func _ready() -> void:
	z_index = 50


func initialize(id: int, target: Node2D, max_hp: int, current_hp: int) -> void:
	entity_id = id
	_target_node = target
	_max_health = max_hp
	_current_health = current_hp
	_update_bar()


func update_health(current_hp: int, max_hp: int) -> void:
	_current_health = current_hp
	_max_health = max_hp
	_update_bar()


func _update_bar() -> void:
	var ratio = float(_current_health) / float(_max_health) if _max_health > 0 else 0.0

	# Color: green -> yellow -> red
	if ratio > 0.5:
		_fill_color = Color(0.2, 0.8, 0.2)
	elif ratio > 0.25:
		_fill_color = Color(0.9, 0.8, 0.1)
	else:
		_fill_color = Color(0.9, 0.2, 0.1)

	# Hide at full health
	visible = _current_health < _max_health
	queue_redraw()


func _draw() -> void:
	# Background (dark)
	draw_rect(Rect2(-BAR_WIDTH / 2, 0, BAR_WIDTH, BAR_HEIGHT), Color(0.2, 0.2, 0.2, 0.8))

	# Fill based on health ratio
	var ratio = float(_current_health) / float(_max_health) if _max_health > 0 else 0.0
	var fill_width = BAR_WIDTH * ratio
	draw_rect(Rect2(-BAR_WIDTH / 2, 0, fill_width, BAR_HEIGHT), _fill_color)


func _process(_delta: float) -> void:
	if _target_node != null and is_instance_valid(_target_node):
		global_position = _target_node.global_position + BAR_OFFSET
	else:
		queue_free()
