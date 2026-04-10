extends GutTest

var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


func _make_system() -> EnemySystem:
	var system = EnemySystem.new()
	add_child_autofree(system)
	return system


func _make_spawner(system: EnemySystem, params: SpawnerParams = null) -> EnemySpawner:
	if params == null:
		params = SpawnerParams.new()
	var enemy_params = EnemyParams.new()
	var spawner = EnemySpawner.new()
	add_child_autofree(spawner)
	spawner.initialize(system, params, enemy_params)
	return spawner


func _make_player(id: int, pos: Vector2) -> PlayerEntity:
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(id, pos)
	return player


func test_spawns_batch_on_interval():
	var system = _make_system()
	var params = SpawnerParams.new()
	params.spawn_interval = 1.0
	params.batch_size = 3
	RNG.seed(42)
	var spawner = _make_spawner(system, params)
	var players: Dictionary = {}
	spawner.advance(1.0, players)
	assert_eq(system.get_all_enemies().size(), 3, "Should spawn batch of 3")


func test_respects_max_alive():
	var system = _make_system()
	var params = SpawnerParams.new()
	params.spawn_interval = 0.5
	params.batch_size = 10
	params.max_alive = 5
	RNG.seed(42)
	var spawner = _make_spawner(system, params)
	var players: Dictionary = {}
	spawner.advance(0.5, players)
	assert_eq(system.get_all_enemies().size(), 5, "Should cap at max_alive")
	spawner.advance(0.5, players)
	assert_eq(system.get_all_enemies().size(), 5, "Should still be at max_alive")


func test_no_spawn_before_interval():
	var system = _make_system()
	var params = SpawnerParams.new()
	params.spawn_interval = 2.0
	params.batch_size = 3
	RNG.seed(42)
	var spawner = _make_spawner(system, params)
	spawner.advance(1.0, {})
	assert_eq(system.get_all_enemies().size(), 0, "Should not spawn before interval")


func test_spawn_margin_rejects_near_player():
	var system = _make_system()
	var params = SpawnerParams.new()
	params.spawn_interval = 0.1
	params.batch_size = 50
	params.spawn_margin = 9999.0
	params.max_alive = 50
	RNG.seed(42)
	var spawner = _make_spawner(system, params)
	var player = _make_player(1, Vector2(240, 160))
	var players: Dictionary = {1: player}
	spawner.advance(0.1, players)
	assert_eq(system.get_all_enemies().size(), 0, "All spawns rejected near player")


func test_entity_ids_are_unique():
	var system = _make_system()
	var params = SpawnerParams.new()
	params.spawn_interval = 0.5
	params.batch_size = 5
	RNG.seed(42)
	var spawner = _make_spawner(system, params)
	spawner.advance(0.5, {})
	var ids: Dictionary = {}
	for enemy in system.get_all_enemies():
		assert_false(ids.has(enemy.entity_id), "ID %d should be unique" % enemy.entity_id)
		ids[enemy.entity_id] = true
	assert_gte(system.get_all_enemies()[0].entity_id, 10000, "IDs should start at 10000+")


func test_spawned_enemies_start_in_spawning_state():
	var system = _make_system()
	var params = SpawnerParams.new()
	params.spawn_interval = 0.5
	params.batch_size = 3
	RNG.seed(42)
	var spawner = _make_spawner(system, params)
	spawner.advance(0.5, {})
	for enemy in system.get_all_enemies():
		assert_eq(enemy.state, EnemyEntity.State.SPAWNING)
