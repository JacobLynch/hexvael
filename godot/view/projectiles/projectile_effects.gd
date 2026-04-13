class_name ProjectileEffects
extends Node2D
## Coordinates projectile visual effects: muzzle flash, trails, and impacts.
## Listens to EventBus signals and spawns appropriate effect scenes.

## Maps projectile type_id -> ProjectileEffectParams
var _effect_params: Dictionary = {}

## Maps projectile_id -> { "type_id": int, "last_trail": float, "direction": Vector2 }
## Tracks ALL projectiles (not just those with trails) so we know type_id on despawn.
var _active_projectiles: Dictionary = {}

## Reference to projectile system for position lookups
var _projectile_system: ProjectileSystem

## Reference to net client for local player check
var _net_client: NetClient


## Set by client_main after connection
func set_net_client(net_client: NetClient) -> void:
	_net_client = net_client


func initialize(projectile_system: ProjectileSystem) -> void:
	_projectile_system = projectile_system


func register_effect_params(type_id: int, params: ProjectileEffectParams) -> void:
	_effect_params[type_id] = params


func _ready() -> void:
	EventBus.projectile_spawned.connect(_on_projectile_spawned)
	EventBus.projectile_despawned.connect(_on_projectile_despawned)
	EventBus.projectile_adopted.connect(_on_projectile_adopted)


func _on_projectile_adopted(event: Dictionary) -> void:
	# Remap tracking from temp_id to new_id so despawn lookup succeeds.
	var temp_id: int = event["temp_id"]
	var new_id: int = event["new_id"]
	if not _active_projectiles.has(temp_id):
		return
	_active_projectiles[new_id] = _active_projectiles[temp_id]
	_active_projectiles.erase(temp_id)


## Spawns muzzle flash for local player. Called directly from input handling
## for instant feedback, bypassing the event system.
func spawn_local_muzzle_flash(pos: Vector2, dir: Vector2, type_id: int) -> void:
	var params: ProjectileEffectParams = _effect_params.get(type_id)
	if params == null or params.muzzle_scene == null:
		return
	var muzzle = params.muzzle_scene.instantiate()
	muzzle.position = pos
	if muzzle.get("direction") != null:
		muzzle.direction = dir
	add_child(muzzle)


func _on_projectile_spawned(event: Dictionary) -> void:
	var type_id: int = event["type_id"]
	var proj_id: int = event["projectile_id"]
	var pos: Vector2 = event["position"]
	var dir: Vector2 = event["direction"]
	var owner_id: int = event.get("owner_player_id", -1)

	# Always track projectile so we know type_id on despawn
	_active_projectiles[proj_id] = {
		"type_id": type_id,
		"last_trail": 0.0,
		"direction": dir,
	}

	var params: ProjectileEffectParams = _effect_params.get(type_id)
	if params == null:
		return

	# Skip muzzle flash for local player — handled by spawn_local_muzzle_flash
	# for instant feedback. Only spawn for remote players.
	var local_id: int = -1
	if _net_client != null:
		local_id = _net_client.get_local_player_id()

	if owner_id != local_id and params.muzzle_scene != null:
		# Use source_position for muzzle flash (player position, not projectile offset)
		var muzzle_pos: Vector2 = event.get("source_position", pos)
		var muzzle = params.muzzle_scene.instantiate()
		muzzle.position = muzzle_pos
		if muzzle.get("direction") != null:
			muzzle.direction = dir
		add_child(muzzle)


func _on_projectile_despawned(event: Dictionary) -> void:
	var proj_id: int = event["projectile_id"]
	var pos: Vector2 = event["position"]
	var reason: int = event["reason"]

	# Get type_id from our tracking (not in event)
	var tracked: Dictionary = _active_projectiles.get(proj_id, {})
	var type_id: int = tracked.get("type_id", -1)

	# Stop tracking
	_active_projectiles.erase(proj_id)

	if type_id < 0:
		return

	var params: ProjectileEffectParams = _effect_params.get(type_id)
	if params == null:
		return

	# Spawn impact or expire effect based on reason
	var is_collision = reason in [
		ProjectileEntity.DespawnReason.WALL,
		ProjectileEntity.DespawnReason.ENEMY,
		ProjectileEntity.DespawnReason.PLAYER,
		ProjectileEntity.DespawnReason.SELF,
	]

	if is_collision and params.impact_scene != null:
		var impact = params.impact_scene.instantiate()
		impact.position = pos
		add_child(impact)

		# Enemy flash
		if reason == ProjectileEntity.DespawnReason.ENEMY:
			var target_id: int = event.get("target_entity_id", -1)
			if target_id >= 0:
				_flash_enemy(target_id, params.enemy_flash_color, params.enemy_flash_duration)

	elif reason == ProjectileEntity.DespawnReason.LIFETIME and params.expire_scene != null:
		var expire = params.expire_scene.instantiate()
		expire.position = pos
		add_child(expire)


func _flash_enemy(entity_id: int, color: Color, duration: float) -> void:
	EventBus.enemy_hit.emit({
		"entity_id": entity_id,
		"flash_color": color,
		"flash_duration": duration,
	})


func _process(delta: float) -> void:
	if _projectile_system == null:
		return

	for proj_id in _active_projectiles.keys():
		var data: Dictionary = _active_projectiles[proj_id]
		var proj: ProjectileEntity = _projectile_system.projectiles.get(proj_id)
		if proj == null:
			_active_projectiles.erase(proj_id)
			continue

		var params: ProjectileEffectParams = _effect_params.get(data["type_id"])
		if params == null or params.trail_scene == null:
			continue

		data["last_trail"] += delta
		if data["last_trail"] >= params.trail_interval:
			data["last_trail"] = 0.0
			_spawn_trail_shard(proj.position, data["direction"], params.trail_scene)


func _spawn_trail_shard(pos: Vector2, dir: Vector2, scene: PackedScene) -> void:
	var shard = scene.instantiate()
	shard.position = pos
	# Velocity: backward with slight random spread
	var spread_angle = (randf() - 0.5) * 0.8
	var vel_dir = -dir.rotated(spread_angle)
	if shard.get("velocity") != null:
		shard.velocity = vel_dir * (60.0 + randf() * 40.0)
	add_child(shard)


func _exit_tree() -> void:
	if EventBus.projectile_spawned.is_connected(_on_projectile_spawned):
		EventBus.projectile_spawned.disconnect(_on_projectile_spawned)
	if EventBus.projectile_despawned.is_connected(_on_projectile_despawned):
		EventBus.projectile_despawned.disconnect(_on_projectile_despawned)
	if EventBus.projectile_adopted.is_connected(_on_projectile_adopted):
		EventBus.projectile_adopted.disconnect(_on_projectile_adopted)
