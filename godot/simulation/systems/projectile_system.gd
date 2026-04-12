class_name ProjectileSystem
extends Node

const MAX_ACTIVE = 1024

var projectiles: Dictionary = {}         # projectile_id -> ProjectileEntity
var _next_server_id: int = 1
var _walls: Array[Rect2] = []
var _fire_cooldown: Dictionary = {}      # player_id -> seconds remaining
var _current_rtt_ms: int = 0             # local client's RTT estimate for rejection timeout

func set_walls(aabbs: Array[Rect2]) -> void:
	_walls = aabbs

func get_walls() -> Array[Rect2]:
	return _walls


func spawn_authoritative(
		owner_id: int, type_id: int,
		origin: Vector2, direction: Vector2,
		input_seq: int) -> ProjectileEntity:
	var id: int = _next_server_id
	_next_server_id = ((_next_server_id + 1) % 65535)
	if _next_server_id == 0:
		_next_server_id = 1
	var params := ProjectileType.get_params(type_id)
	var p := ProjectileEntity.new()
	p.initialize(id, type_id, owner_id, origin, direction, params)
	p.is_predicted = false
	p.spawn_input_seq = input_seq
	projectiles[id] = p
	EventBus.projectile_spawned.emit({
		"projectile_id": id,
		"type_id": type_id,
		"owner_player_id": owner_id,
		"position": p.position,
		"direction": direction,
	})
	return p


func spawn_predicted(
		owner_id: int, type_id: int,
		origin: Vector2, direction: Vector2,
		input_seq: int) -> ProjectileEntity:
	var temp_id: int = -input_seq
	var params := ProjectileType.get_params(type_id)
	var p := ProjectileEntity.new()
	p.initialize(temp_id, type_id, owner_id, origin, direction, params)
	p.is_predicted = true
	p.spawn_input_seq = input_seq
	projectiles[temp_id] = p
	EventBus.projectile_spawned.emit({
		"projectile_id": temp_id,
		"type_id": type_id,
		"owner_player_id": owner_id,
		"position": p.position,
		"direction": direction,
	})
	return p


const _RECONCILE_NO_ACTION_THRESHOLD: float = 2.0
const _RECONCILE_SNAP_THRESHOLD: float = 200.0


func adopt_authoritative(
		projectile_id: int, owner_id: int, type_id: int,
		origin: Vector2, direction: Vector2,
		input_seq: int, current_rtt_ms: int) -> void:
	var temp_id: int = -input_seq
	if projectiles.has(temp_id) and projectiles[temp_id].owner_player_id == owner_id:
		var predicted: ProjectileEntity = projectiles[temp_id]
		projectiles.erase(temp_id)
		predicted.projectile_id = projectile_id
		predicted.is_predicted = false
		projectiles[projectile_id] = predicted

		var one_way_s: float = current_rtt_ms / 2000.0
		var expected: Vector2 = origin + direction * predicted.params.speed * one_way_s
		var drift: float = predicted.position.distance_to(expected)
		if drift < _RECONCILE_NO_ACTION_THRESHOLD:
			pass
		elif drift < _RECONCILE_SNAP_THRESHOLD:
			predicted.start_reconcile(expected)
		else:
			push_warning("projectile %d hard snap, drift %.1f px" % [projectile_id, drift])
			predicted.position = expected
		return

	# No matching predicted — spawn a fresh remote projectile and fast-forward.
	var params := ProjectileType.get_params(type_id)
	var fresh := ProjectileEntity.new()
	var one_way_s: float = current_rtt_ms / 2000.0
	var spawn_pos: Vector2 = origin + direction * params.speed * one_way_s
	fresh.initialize(projectile_id, type_id, owner_id, spawn_pos, direction, params)
	fresh.is_predicted = false
	fresh.spawn_input_seq = input_seq
	projectiles[projectile_id] = fresh
	EventBus.projectile_spawned.emit({
		"projectile_id": projectile_id,
		"type_id": type_id,
		"owner_player_id": owner_id,
		"position": spawn_pos,
		"direction": direction,
	})


func on_despawn_event(projectile_id: int, reason: int, pos: Vector2) -> void:
	if not projectiles.has(projectile_id):
		return
	projectiles.erase(projectile_id)
	EventBus.projectile_despawned.emit({
		"projectile_id": projectile_id,
		"reason": reason,
		"position": pos,
	})


func advance(dt: float, players: Array, enemies: Array) -> Array:
	var despawned: Array = []
	var rejection_timeout_s: float = 2.0 * (_current_rtt_ms / 1000.0) + 0.1

	for id in projectiles.keys():
		var p: ProjectileEntity = projectiles[id]
		var reason: int = p.advance(dt, _walls, players, enemies)

		# Rejection timeout for predicted projectiles (client-side only).
		# Lives here, not in ProjectileEntity.advance(), because only the system
		# holds the current RTT estimate.
		if reason == ProjectileEntity.DespawnReason.ALIVE and p.is_predicted:
			if p.time_since_spawn > rejection_timeout_s:
				reason = ProjectileEntity.DespawnReason.REJECTED

		if reason != ProjectileEntity.DespawnReason.ALIVE:
			despawned.append({
				"id": id,
				"reason": reason,
				"position": p.position,
			})

	for entry in despawned:
		var dead_id: int = entry["id"]
		projectiles.erase(dead_id)
		EventBus.projectile_despawned.emit({
			"projectile_id": dead_id,
			"reason": entry["reason"],
			"position": entry["position"],
		})

	return despawned


func can_fire(player_id: int) -> bool:
	return _fire_cooldown.get(player_id, 0.0) <= 0.0


func start_cooldown(player_id: int) -> void:
	var params := ProjectileType.get_params(ProjectileType.Id.TEST)
	_fire_cooldown[player_id] = params.fire_cooldown


func tick_cooldowns(dt: float) -> void:
	for id in _fire_cooldown.keys():
		_fire_cooldown[id] = max(0.0, _fire_cooldown[id] - dt)
