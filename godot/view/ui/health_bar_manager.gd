# godot/view/ui/health_bar_manager.gd
extends Node

var HealthBarScene: PackedScene = preload("res://view/ui/enemy_health_bar.tscn")
var _parent: Node2D = null
var _bars: Dictionary = {}  # entity_id -> health bar node
var _enemy_views: Dictionary = {}  # Reference to WorldView's enemy views


func initialize(parent: Node2D, enemy_views: Dictionary) -> void:
	_parent = parent
	_enemy_views = enemy_views
	EventBus.enemy_hit.connect(_on_enemy_hit)
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_died.connect(_on_enemy_died)


func _on_enemy_spawned(event: Dictionary) -> void:
	var entity_id: int = event.get("entity_id", -1)
	if entity_id < 0:
		return
	# Health bar created lazily on first damage


func _on_enemy_hit(event: Dictionary) -> void:
	var entity_id: int = event.get("target_entity_id", -1)
	if entity_id < 0:
		return

	var enemy_view = _enemy_views.get(entity_id)
	if enemy_view == null:
		return

	var max_hp: int = event.get("max_health", 50)
	var current_hp: int = event.get("remaining_health", max_hp)

	# Create bar if doesn't exist
	if not _bars.has(entity_id):
		var bar = HealthBarScene.instantiate()
		_parent.add_child(bar)
		bar.initialize(entity_id, enemy_view, max_hp, current_hp)
		_bars[entity_id] = bar
	else:
		var bar = _bars[entity_id]
		bar.update_health(current_hp, max_hp)


func _on_enemy_died(event: Dictionary) -> void:
	var entity_id: int = event.get("target_entity_id", -1)
	_remove_bar(entity_id)


func _remove_bar(entity_id: int) -> void:
	if _bars.has(entity_id):
		_bars[entity_id].queue_free()
		_bars.erase(entity_id)


func _exit_tree() -> void:
	if EventBus.enemy_hit.is_connected(_on_enemy_hit):
		EventBus.enemy_hit.disconnect(_on_enemy_hit)
	if EventBus.enemy_spawned.is_connected(_on_enemy_spawned):
		EventBus.enemy_spawned.disconnect(_on_enemy_spawned)
	if EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.disconnect(_on_enemy_died)
