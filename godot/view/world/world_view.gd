extends Node2D

var PlayerViewScene: PackedScene = preload("res://view/world/player_view.tscn")

var _player_views: Dictionary = {}  # player_id -> PlayerView node
var _net_client: NetClient = null


func initialize(net_client: NetClient) -> void:
	_net_client = net_client
	_net_client.connected.connect(_on_connected)
	_net_client.disconnected.connect(_on_disconnected)
	_net_client.player_joined.connect(_on_player_joined)
	_net_client.player_left.connect(_on_player_left)
	_net_client.snapshot_received.connect(_on_snapshot)


func _on_connected(_player_id: int):
	pass  # Local player view created when first snapshot arrives


func _on_disconnected():
	for view in _player_views.values():
		view.queue_free()
	_player_views.clear()


func _on_player_joined(player_id: int, spawn_position: Vector2):
	_add_player_view(player_id, spawn_position, false)


func _on_player_left(player_id: int):
	_remove_player_view(player_id)


func _on_snapshot(_tick: int, entities: Array):
	for ent in entities:
		var eid: int = ent["entity_id"]

		if ent.get("flags", 0) & MessageTypes.EntityFlags.REMOVED:
			_remove_player_view(eid)
			continue

		# Create view if it doesn't exist yet
		if not _player_views.has(eid):
			var is_local = (eid == _net_client.get_local_player_id())
			_add_player_view(eid, ent["position"], is_local)


func _process(delta: float):
	if _net_client == null:
		return

	for player_id in _player_views:
		var view = _player_views[player_id]
		if view.is_local:
			# Local player: follow entity position + visual offset
			var local_pos = _net_client.get_local_player_position()
			if local_pos != null:
				var offset = _net_client.get_visual_offset()
				view.update_position(local_pos + offset)
				_net_client.blend_visual_offset(delta)
		else:
			var interp_pos = _net_client.get_interpolated_position(player_id)
			if interp_pos != null:
				view.update_position(interp_pos)


func _add_player_view(player_id: int, pos: Vector2, is_local: bool):
	if _player_views.has(player_id):
		return
	var view = PlayerViewScene.instantiate()
	add_child(view)
	view.initialize(player_id, pos, is_local)
	_player_views[player_id] = view


func _remove_player_view(player_id: int):
	if _player_views.has(player_id):
		_player_views[player_id].queue_free()
		_player_views.erase(player_id)
