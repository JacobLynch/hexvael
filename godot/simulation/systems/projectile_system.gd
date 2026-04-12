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
