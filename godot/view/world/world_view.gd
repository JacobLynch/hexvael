extends Node2D

var PlayerViewScene: PackedScene = preload("res://view/world/player_view.tscn")
var CameraRigScene: PackedScene = preload("res://view/world/camera_rig.tscn")
var EnemyViewScene: PackedScene = preload("res://view/world/enemy_view.tscn")
var EnemyDeathEffect = preload("res://view/effects/enemy_death_effect.gd")

var _player_views: Dictionary = {}  # player_id -> PlayerView node
var _enemy_views: Dictionary = {}  # entity_id -> EnemyView node
var _net_client: NetClient = null
var _camera_rig: CameraRig
# Tracks whether each remote entity was dodging last frame so we can emit
# player_dodge_started / player_dodge_ended only on state *transitions*.
var _prev_remote_dodge_state: Dictionary = {}  # entity_id -> bool
# Tracks the last seen collision_count per remote entity so we can detect
# momentary wall-collision events and emit synthetic player_collided signals.
var _prev_remote_collision_count: Dictionary = {}  # entity_id -> int
var _effect_params_cache: Dictionary = {}  ## type_id -> ProjectileEffectParams


func initialize(net_client: NetClient) -> void:
	_net_client = net_client
	_net_client.connected.connect(_on_connected)
	_net_client.disconnected.connect(_on_disconnected)
	_net_client.player_joined.connect(_on_player_joined)
	_net_client.player_left.connect(_on_player_left)
	_net_client.snapshot_received.connect(_on_snapshot)
	_net_client.enemy_died_received.connect(_on_enemy_died)
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
	EventBus.enemy_hit.connect(_on_enemy_hit)
	EventBus.projectile_spawned.connect(_on_projectile_spawned_for_recoil)


func get_player_view_position(player_id: int) -> Variant:
	if _player_views.has(player_id):
		return _player_views[player_id].position
	return null


## Register effect params for a projectile type (called during setup).
func register_effect_params(type_id: int, params: ProjectileEffectParams) -> void:
	_effect_params_cache[type_id] = params


func _on_connected(_player_id: int):
	pass  # Local player view created when first snapshot arrives


func _on_disconnected():
	for view in _player_views.values():
		view.queue_free()
	_player_views.clear()
	for view in _enemy_views.values():
		view.queue_free()
	_enemy_views.clear()


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
				var vel: Vector2 = ent.get("velocity", Vector2.ZERO)
				vel_mag = vel.length()
				# Synthesize player_moved so FootstepDust fires for remote players.
				# The local player's player_moved comes from PlayerEntity.advance().
				if vel_mag > 1.0:
					EventBus.player_moved.emit({
						"entity_id": player_id,
						"position": view.position,
						"velocity": vel,
					})
				# Synthesize player_dodge_started/ended on state transitions only,
				# not every frame, so DodgeTrail doesn't get duplicate spawns.
				const DODGING = 1  # PlayerMovementState.DODGING
				var was_dodging: bool = _prev_remote_dodge_state.get(player_id, false)
				var is_dodging: bool = (state == DODGING)
				if is_dodging and not was_dodging:
					EventBus.player_dodge_started.emit({
						"entity_id": player_id,
						"position": view.position,
						"direction": aim,
					})
				elif was_dodging and not is_dodging:
					EventBus.player_dodge_ended.emit({
						"entity_id": player_id,
						"position": view.position,
						"direction": aim,
					})
				_prev_remote_dodge_state[player_id] = is_dodging

				# Synthesize player_collided for remote wall bumps.
				# collision_count is a u8 that increments on every collision — detect
				# any change (not just > to handle wrap-around at 256).
				var collision_count: int = ent.get("collision_count", 0)
				# Default to current count on first sight so we don't fire on the
				# very first snapshot for a newly joined remote player.
				var prev_count: int = _prev_remote_collision_count.get(player_id, collision_count)
				if collision_count != prev_count:
					var collision_normal: Vector2 = ent.get("last_collision_normal", Vector2.ZERO)
					EventBus.player_collided.emit({
						"entity_id": player_id,
						"position": view.position,
						"normal": collision_normal,
						"velocity": vel,
					})
				_prev_remote_collision_count[player_id] = collision_count

		view.update_visual_state(aim, state, vel_mag, delta)

	# Enemy views
	var current_enemy_ids = _net_client.get_enemy_ids()

	# Create views for new enemies
	for eid in current_enemy_ids:
		if not _enemy_views.has(eid):
			var data = _net_client.get_interpolated_enemy(eid)
			if data != null:
				_add_enemy_view(eid, data["position"])

	# Update existing views and remove stale ones
	for eid in _enemy_views.keys():
		if eid not in current_enemy_ids:
			_remove_enemy_view(eid)
		else:
			var data = _net_client.get_interpolated_enemy(eid)
			if data != null:
				_enemy_views[eid].update_from_data(data)


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
	_prev_remote_dodge_state.erase(player_id)
	_prev_remote_collision_count.erase(player_id)


func _add_enemy_view(entity_id: int, pos: Vector2) -> void:
	if _enemy_views.has(entity_id):
		return
	var view = EnemyViewScene.instantiate()
	add_child(view)
	view.initialize(entity_id, pos)
	_enemy_views[entity_id] = view


func _remove_enemy_view(entity_id: int) -> void:
	if _enemy_views.has(entity_id):
		_enemy_views[entity_id].queue_free()
		_enemy_views.erase(entity_id)


func _on_enemy_died(event: Dictionary) -> void:
	var effect = Node2D.new()
	effect.set_script(EnemyDeathEffect)
	effect.position = event["position"]
	add_child(effect)
	_remove_enemy_view(event["entity_id"])


func _on_any_dodge_started(event: Dictionary):
	# Only shake for the local player — remote dodges don't shake your camera
	if _net_client == null:
		return
	if event["entity_id"] == _net_client.get_local_player_id():
		if _camera_rig != null:
			_camera_rig.add_shake(3.0, 0.1)


func _on_enemy_hit(event: Dictionary) -> void:
	var entity_id: int = event.get("target_entity_id", event.get("entity_id", -1))
	var flash_color: Color = event.get("flash_color", Color.WHITE)
	var flash_duration: float = event.get("flash_duration", 0.1)
	var cling_scene: PackedScene = event.get("cling_scene", null)

	if entity_id < 0:
		return

	var enemy_view = _enemy_views.get(entity_id)
	if enemy_view != null:
		if enemy_view.has_method("flash_hit"):
			enemy_view.flash_hit(flash_color, flash_duration)
		# Spawn cling effect attached to enemy
		if cling_scene != null:
			var cling = cling_scene.instantiate()
			cling.target_node = enemy_view
			cling.global_position = enemy_view.global_position
			add_child(cling)


func _on_projectile_spawned_for_recoil(event: Dictionary) -> void:
	var owner_id: int = event.get("owner_player_id", -1)
	var type_id: int = event.get("type_id", -1)
	var direction: Vector2 = event.get("direction", Vector2.RIGHT)

	if owner_id < 0 or type_id < 0:
		return

	var params: ProjectileEffectParams = _effect_params_cache.get(type_id)
	if params == null or params.sprite_recoil_distance <= 0.0:
		return

	var player_view = _player_views.get(owner_id)
	if player_view != null and player_view.has_method("apply_recoil"):
		player_view.apply_recoil(direction, params.sprite_recoil_distance)


func _exit_tree():
	if EventBus.player_dodge_started.is_connected(_on_any_dodge_started):
		EventBus.player_dodge_started.disconnect(_on_any_dodge_started)
	if EventBus.enemy_hit.is_connected(_on_enemy_hit):
		EventBus.enemy_hit.disconnect(_on_enemy_hit)
	if EventBus.projectile_spawned.is_connected(_on_projectile_spawned_for_recoil):
		EventBus.projectile_spawned.disconnect(_on_projectile_spawned_for_recoil)
	if _net_client != null:
		if _net_client.connected.is_connected(_on_connected):
			_net_client.connected.disconnect(_on_connected)
		if _net_client.disconnected.is_connected(_on_disconnected):
			_net_client.disconnected.disconnect(_on_disconnected)
		if _net_client.player_joined.is_connected(_on_player_joined):
			_net_client.player_joined.disconnect(_on_player_joined)
		if _net_client.player_left.is_connected(_on_player_left):
			_net_client.player_left.disconnect(_on_player_left)
		if _net_client.snapshot_received.is_connected(_on_snapshot):
			_net_client.snapshot_received.disconnect(_on_snapshot)
		if _net_client.enemy_died_received.is_connected(_on_enemy_died):
			_net_client.enemy_died_received.disconnect(_on_enemy_died)
