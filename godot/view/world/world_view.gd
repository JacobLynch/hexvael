extends Node2D

var PlayerViewScene: PackedScene = preload("res://view/world/player_view.tscn")

var _player_views: Dictionary = {}  # player_id -> PlayerView node
var _net_client: NetClient = null


# Arena dimensions (must match server collision walls)
const ARENA_WIDTH: float = 480.0
const ARENA_HEIGHT: float = 320.0
const WALL_THICKNESS: float = 4.0


func _ready():
	_build_arena_visual()


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


func _build_arena_visual():
	var floor_color = Color(0.12, 0.11, 0.14)  # Dark stone floor
	var wall_color = Color(0.25, 0.22, 0.28)    # Slightly lighter walls

	# Floor
	var floor_rect = ColorRect.new()
	floor_rect.color = floor_color
	floor_rect.position = Vector2.ZERO
	floor_rect.size = Vector2(ARENA_WIDTH, ARENA_HEIGHT)
	floor_rect.z_index = -10
	add_child(floor_rect)

	# Walls (visual only — collision is on the server)
	var w = WALL_THICKNESS
	_add_wall(wall_color, Vector2(0, -w), Vector2(ARENA_WIDTH, w))          # Top
	_add_wall(wall_color, Vector2(0, ARENA_HEIGHT), Vector2(ARENA_WIDTH, w)) # Bottom
	_add_wall(wall_color, Vector2(-w, -w), Vector2(w, ARENA_HEIGHT + w * 2)) # Left
	_add_wall(wall_color, Vector2(ARENA_WIDTH, -w), Vector2(w, ARENA_HEIGHT + w * 2)) # Right


func _add_wall(color: Color, pos: Vector2, size: Vector2):
	var wall = ColorRect.new()
	wall.color = color
	wall.position = pos
	wall.size = size
	wall.z_index = -9
	add_child(wall)
