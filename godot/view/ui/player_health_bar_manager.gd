# godot/view/ui/player_health_bar_manager.gd
extends Node

var HealthBarScene: PackedScene = preload("res://view/ui/enemy_health_bar.tscn")
var _parent: Node2D = null
var _bars: Dictionary = {}  # player_id -> health bar node
var _player_views: Dictionary = {}  # Reference to WorldView's player views


func initialize(parent: Node2D, player_views: Dictionary) -> void:
	_parent = parent
	_player_views = player_views
	EventBus.player_hit.connect(_on_player_hit)
	EventBus.player_ghost_started.connect(_on_player_ghost_started)
	EventBus.player_respawned.connect(_on_player_respawned)


func _on_player_hit(event: Dictionary) -> void:
	var entity_id: int = event.get("target_entity_id", event.get("entity_id", -1))
	if entity_id < 0:
		return

	var player_view = _player_views.get(entity_id)
	if player_view == null:
		return

	var max_hp: int = event.get("max_health", 100)
	var current_hp: int = event.get("remaining_health", max_hp)

	# Create bar if doesn't exist
	if not _bars.has(entity_id):
		var bar = HealthBarScene.instantiate()
		_parent.add_child(bar)
		bar.initialize(entity_id, player_view, max_hp, current_hp)
		_bars[entity_id] = bar
	else:
		var bar = _bars[entity_id]
		bar.update_health(current_hp, max_hp)


func _on_player_ghost_started(event: Dictionary) -> void:
	var entity_id: int = event.get("entity_id", -1)
	# Remove bar when player becomes ghost
	_remove_bar(entity_id)


func _on_player_respawned(event: Dictionary) -> void:
	var entity_id: int = event.get("entity_id", -1)
	# Remove bar on respawn since health is restored to full
	_remove_bar(entity_id)


func _remove_bar(entity_id: int) -> void:
	if _bars.has(entity_id):
		_bars[entity_id].queue_free()
		_bars.erase(entity_id)


func _exit_tree() -> void:
	if EventBus.player_hit.is_connected(_on_player_hit):
		EventBus.player_hit.disconnect(_on_player_hit)
	if EventBus.player_ghost_started.is_connected(_on_player_ghost_started):
		EventBus.player_ghost_started.disconnect(_on_player_ghost_started)
	if EventBus.player_respawned.is_connected(_on_player_respawned):
		EventBus.player_respawned.disconnect(_on_player_respawned)
