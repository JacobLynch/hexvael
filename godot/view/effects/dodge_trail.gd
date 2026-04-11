class_name DodgeTrail
extends Node2D
## Listens for player_dodge_started events and renders a Line2D afterimage
## that follows the dodging player, fading out when the dodge ends.

const TRAIL_LIFETIME_AFTER_END: float = 0.15

var _active_trails: Dictionary = {}  # entity_id -> { line: Line2D, fade_time: float }
var _world_view: Node2D


func _ready():
	EventBus.player_dodge_started.connect(_on_dodge_started)
	EventBus.player_dodge_ended.connect(_on_dodge_ended)


func initialize(world_view: Node2D) -> void:
	_world_view = world_view


func _on_dodge_started(event: Dictionary):
	var entity_id: int = event["entity_id"]
	if _active_trails.has(entity_id):
		return
	var line = Line2D.new()
	line.width = 14.0
	line.default_color = Color(0.6, 0.8, 1.0, 0.7)
	var grad = Gradient.new()
	grad.add_point(0.0, Color(0.6, 0.8, 1.0, 0.0))  # tail end fades out
	grad.add_point(1.0, Color(0.6, 0.8, 1.0, 0.8))  # head is full alpha
	line.gradient = grad
	add_child(line)
	_active_trails[entity_id] = {"line": line, "fade_time": -1.0}


func _on_dodge_ended(event: Dictionary):
	var entity_id: int = event["entity_id"]
	if _active_trails.has(entity_id):
		_active_trails[entity_id]["fade_time"] = TRAIL_LIFETIME_AFTER_END


func _process(delta: float):
	if _world_view == null:
		return
	var finished: Array = []
	for entity_id in _active_trails:
		var trail = _active_trails[entity_id]
		var line: Line2D = trail["line"]
		var player_pos = _get_player_position(entity_id)
		if player_pos == null:
			finished.append(entity_id)
			continue
		line.add_point(player_pos)
		if line.get_point_count() > 8:
			line.remove_point(0)
		if trail["fade_time"] >= 0.0:
			trail["fade_time"] -= delta
			line.modulate.a = clampf(trail["fade_time"] / TRAIL_LIFETIME_AFTER_END, 0.0, 1.0)
			if trail["fade_time"] <= 0.0:
				finished.append(entity_id)
	for entity_id in finished:
		_active_trails[entity_id]["line"].queue_free()
		_active_trails.erase(entity_id)


func _get_player_position(entity_id: int) -> Variant:
	if _world_view.has_method("get_player_view_position"):
		return _world_view.get_player_view_position(entity_id)
	return null


func _exit_tree():
	if EventBus.player_dodge_started.is_connected(_on_dodge_started):
		EventBus.player_dodge_started.disconnect(_on_dodge_started)
	if EventBus.player_dodge_ended.is_connected(_on_dodge_ended):
		EventBus.player_dodge_ended.disconnect(_on_dodge_ended)
