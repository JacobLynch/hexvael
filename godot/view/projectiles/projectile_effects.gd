class_name ProjectileEffects
extends Node2D
## Coordinates projectile visual effects: muzzle flash, trails, and impacts.
## Listens to EventBus signals and spawns appropriate effect scenes.

## Maps projectile type_id -> ProjectileEffectParams
var _effect_params: Dictionary = {}

## Maps projectile_id -> { "last_trail": float, "position": Vector2 }
var _active_projectiles: Dictionary = {}

## Reference to projectile system for position lookups
var _projectile_system: ProjectileSystem


func initialize(projectile_system: ProjectileSystem) -> void:
	_projectile_system = projectile_system


func register_effect_params(type_id: int, params: ProjectileEffectParams) -> void:
	_effect_params[type_id] = params


func _ready() -> void:
	EventBus.projectile_spawned.connect(_on_projectile_spawned)
	EventBus.projectile_despawned.connect(_on_projectile_despawned)


func _on_projectile_spawned(event: Dictionary) -> void:
	var type_id: int = event["type_id"]
	var proj_id: int = event["projectile_id"]
	var pos: Vector2 = event["position"]
	var dir: Vector2 = event["direction"]

	var params: ProjectileEffectParams = _effect_params.get(type_id)
	if params == null:
		return

	# Spawn muzzle flash at fire position
	if params.muzzle_scene != null:
		var muzzle = params.muzzle_scene.instantiate()
		muzzle.position = pos
		if muzzle.has_method("set") and "direction" in muzzle:
			muzzle.direction = dir
		elif muzzle.get("direction") != null:
			muzzle.direction = dir
		add_child(muzzle)

	# Track for trail spawning
	if params.trail_interval > 0.0 and params.trail_scene != null:
		_active_projectiles[proj_id] = {
			"type_id": type_id,
			"last_trail": 0.0,
			"direction": dir,
		}


func _on_projectile_despawned(event: Dictionary) -> void:
	var type_id: int = event["type_id"]
	var proj_id: int = event["projectile_id"]
	var pos: Vector2 = event["position"]
	var reason: int = event["reason"]

	# Stop tracking
	_active_projectiles.erase(proj_id)

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
