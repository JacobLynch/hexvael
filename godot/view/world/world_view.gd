extends Node2D

var PlayerViewScene: PackedScene = preload("res://view/world/player_view.tscn")
var CameraRigScene: PackedScene = preload("res://view/world/camera_rig.tscn")

var _player_views: Dictionary = {}  # player_id -> PlayerView node
var _net_client: NetClient = null
var _camera_rig: CameraRig


func initialize(net_client: NetClient) -> void:
	_net_client = net_client
	_net_client.connected.connect(_on_connected)
	_net_client.disconnected.connect(_on_disconnected)
	_net_client.player_joined.connect(_on_player_joined)
	_net_client.player_left.connect(_on_player_left)
	_net_client.snapshot_received.connect(_on_snapshot)
	_camera_rig = CameraRigScene.instantiate()
	add_child(_camera_rig)
	_camera_rig.initialize(_net_client)
	var dodge_trail = preload("res://view/effects/dodge_trail.gd").new()
	add_child(dodge_trail)
	dodge_trail.initialize(self)
	var footstep_dust = preload("res://view/effects/footstep_dust.gd").new()
	add_child(footstep_dust)
	var wall_bump = preload("res://view/effects/wall_bump.gd").new()
	add_child(wall_bump)
	wall_bump.initialize(_camera_rig, _net_client)
	EventBus.player_dodge_started.connect(_on_any_dodge_started)


func get_camera_rig() -> CameraRig:
	return _camera_rig


func get_player_view_position(player_id: int) -> Variant:
	if _player_views.has(player_id):
		return _player_views[player_id].position
	return null


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
		var aim: Vector2 = Vector2.RIGHT
		var state: int = 0
		var vel_mag: float = 0.0

		if view.is_local:
			var local_pos = _net_client.get_local_player_position()
			if local_pos != null:
				var offset = _net_client.get_visual_offset()
				view.update_position(local_pos + offset)
				_net_client.blend_visual_offset(delta)
			# Pull visual state from local predicted player via public accessors
			var local_aim = _net_client.get_local_player_aim_direction()
			if local_aim != null:
				aim = local_aim
			var local_state = _net_client.get_local_player_state()
			if local_state != null:
				state = local_state
			var local_vel = _net_client.get_local_player_velocity()
			if local_vel != null:
				vel_mag = local_vel.length()
		else:
			var interp_pos = _net_client.get_interpolated_position(player_id)
			if interp_pos != null:
				view.update_position(interp_pos)
			# Pull visual state from latest snapshot via public accessor
			var ent = _net_client.get_remote_entity_snapshot(player_id)
			if ent != null:
				aim = ent.get("aim_direction", Vector2.RIGHT)
				state = ent.get("state", 0)
				vel_mag = ent.get("velocity", Vector2.ZERO).length()

		view.update_visual_state(aim, state, vel_mag, delta)


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


func _on_any_dodge_started(event: Dictionary):
	# Only shake for the local player — remote dodges don't shake your camera
	if _net_client == null:
		return
	if event["entity_id"] == _net_client.get_local_player_id():
		if _camera_rig != null:
			_camera_rig.add_shake(1.0, 0.05)


func _exit_tree():
	if EventBus.player_dodge_started.is_connected(_on_any_dodge_started):
		EventBus.player_dodge_started.disconnect(_on_any_dodge_started)
