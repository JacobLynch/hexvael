class_name EnemySystem
extends Node

var _enemies: Dictionary = {}  # entity_id -> EnemyEntity
var _spatial_grid: SpatialGrid
var _dead_queue: Array = []

@export var params: EnemyParams = null


func _init() -> void:
	_spatial_grid = SpatialGrid.new()


func register_enemy(enemy: EnemyEntity) -> void:
	_enemies[enemy.entity_id] = enemy


func unregister_enemy(entity_id: int) -> void:
	_enemies.erase(entity_id)


func has_enemy(entity_id: int) -> bool:
	return _enemies.has(entity_id)


func get_enemy(entity_id: int) -> EnemyEntity:
	return _enemies.get(entity_id)


func get_all_enemies() -> Array:
	return _enemies.values()


func get_enemies_in_radius(pos: Vector2, radius: float) -> Array:
	return _spatial_grid.query_radius(pos, radius)


func advance_all(dt: float, players: Dictionary) -> void:
	_dead_queue.clear()

	# Rebuild spatial grid with non-spawning, non-dead enemies
	_spatial_grid.clear()
	for enemy in _enemies.values():
		if enemy.state == EnemyEntity.State.IDLE or enemy.state == EnemyEntity.State.CHASING:
			_spatial_grid.insert(enemy, enemy.position)

	var player_array: Array = players.values()

	# Advance each enemy
	for enemy in _enemies.values():
		if enemy.state == EnemyEntity.State.DEAD:
			_dead_queue.append(enemy.entity_id)
			continue
		var neighbors = _spatial_grid.query_nearby(enemy.position)
		enemy.advance(dt, player_array, neighbors)

	# Remove dead enemies
	for eid in _dead_queue:
		_enemies.erase(eid)
