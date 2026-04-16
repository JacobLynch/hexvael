# godot/view/ui/enemy_health_bar.gd
extends Control

var entity_id: int = -1
var _target_node: Node2D = null
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _max_health: int = 100
var _current_health: int = 100

const BAR_WIDTH: float = 24.0
const BAR_HEIGHT: float = 4.0
const BAR_OFFSET: Vector2 = Vector2(0, -16)


func _ready() -> void:
	# Background (dark)
	_bar_bg = ColorRect.new()
	_bar_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_bg.position = Vector2(-BAR_WIDTH / 2, 0)
	_bar_bg.color = Color(0.2, 0.2, 0.2, 0.8)
	add_child(_bar_bg)

	# Fill (green -> yellow -> red based on health)
	_bar_fill = ColorRect.new()
	_bar_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_fill.position = Vector2(-BAR_WIDTH / 2, 0)
	_bar_fill.color = Color(0.2, 0.8, 0.2)
	add_child(_bar_fill)

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
	_bar_fill.size.x = BAR_WIDTH * ratio

	# Color: green -> yellow -> red
	if ratio > 0.5:
		_bar_fill.color = Color(0.2, 0.8, 0.2)
	elif ratio > 0.25:
		_bar_fill.color = Color(0.9, 0.8, 0.1)
	else:
		_bar_fill.color = Color(0.9, 0.2, 0.1)

	# Hide at full health
	visible = _current_health < _max_health


func _process(_delta: float) -> void:
	if _target_node != null and is_instance_valid(_target_node):
		global_position = _target_node.global_position + BAR_OFFSET
	else:
		queue_free()
