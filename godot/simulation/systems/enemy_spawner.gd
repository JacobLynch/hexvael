class_name EnemySpawner
extends Node

var _enemy_system: EnemySystem
var _spawner_params: SpawnerParams
var _enemy_params: EnemyParams
var _spawn_timer: float = 0.0
var _next_enemy_id: int = 10000

var EnemyEntityScene: PackedScene = preload("res://simulation/entities/enemy_entity.tscn")

const MAX_SPAWN_ATTEMPTS: int = 5


func initialize(enemy_system: EnemySystem, spawner_params: SpawnerParams, enemy_params: EnemyParams) -> void:
	_enemy_system = enemy_system
	_spawner_params = spawner_params
	_enemy_params = enemy_params
	_spawn_timer = spawner_params.spawn_interval


func advance(dt: float, players: Dictionary) -> void:
	_spawn_timer -= dt
	if _spawn_timer > 0.0:
		return
	_spawn_timer = _spawner_params.spawn_interval

	var alive_count = _enemy_system.get_all_enemies().size()
	var to_spawn = mini(_spawner_params.batch_size, _spawner_params.max_alive - alive_count)

	for i in range(to_spawn):
		var point = _pick_spawn_point(players)
		if point == null:
			continue
		_spawn_enemy_at(point)


func _pick_spawn_point(players: Dictionary) -> Variant:
	var arena = _spawner_params.arena_size
	var inset = _spawner_params.spawn_edge_inset

	for _attempt in range(MAX_SPAWN_ATTEMPTS):
		var point = _random_edge_point(arena, inset)
		if _is_far_from_players(point, players):
			return point
	return null


func _random_edge_point(arena: Vector2, inset: float) -> Vector2:
	var edge = RNG.next_int(0, 3)
	match edge:
		0:  # Top
			return Vector2(RNG.next_float_range(inset, arena.x - inset), inset)
		1:  # Bottom
			return Vector2(RNG.next_float_range(inset, arena.x - inset), arena.y - inset)
		2:  # Left
			return Vector2(inset, RNG.next_float_range(inset, arena.y - inset))
		3:  # Right
			return Vector2(arena.x - inset, RNG.next_float_range(inset, arena.y - inset))
	return Vector2(inset, inset)


func _is_far_from_players(point: Vector2, players: Dictionary) -> bool:
	for player in players.values():
		if point.distance_to(player.position) < _spawner_params.spawn_margin:
			return false
	return true


func _spawn_enemy_at(point: Vector2) -> void:
	var enemy: EnemyEntity = EnemyEntityScene.instantiate()
	enemy.initialize(_next_enemy_id, point, _enemy_params)
	_next_enemy_id += 1
	get_parent().add_child(enemy)
	_enemy_system.register_enemy(enemy)
	EventBus.enemy_spawned.emit({
		"entity_id": enemy.entity_id,
		"position": point,
		"spawn_duration": enemy.spawn_timer,
	})
