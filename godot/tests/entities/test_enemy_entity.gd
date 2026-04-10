extends GutTest

var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")


func _make_enemy(id: int = 1, pos: Vector2 = Vector2(100, 100)) -> EnemyEntity:
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParams.new()
	enemy.initialize(id, pos, params)
	return enemy


func test_initial_state_is_spawning():
	var enemy = _make_enemy()
	assert_eq(enemy.state, EnemyEntity.State.SPAWNING)
	assert_eq(enemy.entity_id, 1)
	assert_eq(enemy.position, Vector2(100, 100))


func test_spawn_timer_counts_down():
	var enemy = _make_enemy()
	var initial_timer = enemy.spawn_timer
	enemy.advance(0.1, [], [])
	assert_almost_eq(enemy.spawn_timer, initial_timer - 0.1, 0.01)


func test_spawning_transitions_to_idle():
	var enemy = _make_enemy()
	enemy.advance(enemy.spawn_timer + 0.01, [], [])
	assert_eq(enemy.state, EnemyEntity.State.IDLE)


func test_no_movement_during_spawning():
	var enemy = _make_enemy()
	var pos_before = enemy.position
	enemy.advance(0.1, [], [])
	assert_eq(enemy.position, pos_before, "Should not move while spawning")


func test_velocity_zero_during_spawning():
	var enemy = _make_enemy()
	enemy.advance(0.1, [], [])
	assert_eq(enemy.velocity, Vector2.ZERO)


func test_actual_speed_varies_with_rng():
	RNG.seed(42)
	var e1 = _make_enemy(1)
	RNG.seed(99)
	var e2 = _make_enemy(2)
	assert_ne(e1.actual_speed, e2.actual_speed, "Different RNG seeds should produce different speeds")


func test_to_snapshot_data_roundtrip():
	var enemy = _make_enemy()
	enemy.facing = Vector2(0.707, 0.707).normalized()
	var data = enemy.to_snapshot_data()
	assert_eq(data["entity_id"], 1)
	assert_eq(data["state"], EnemyEntity.State.SPAWNING)
	assert_true(data.has("position"))
	assert_true(data.has("facing"))
	assert_true(data.has("spawn_timer"))


func test_dt_independence_spawning():
	RNG.seed(42)
	var e1 = _make_enemy(1, Vector2(100, 100))
	var timer1 = e1.spawn_timer
	RNG.seed(42)
	var e2 = _make_enemy(2, Vector2(100, 100))
	var timer2 = e2.spawn_timer
	assert_almost_eq(timer1, timer2, 0.001, "Same seed should give same timer")
	e1.advance(0.3, [], [])
	for i in range(30):
		e2.advance(0.01, [], [])
	assert_almost_eq(e1.spawn_timer, e2.spawn_timer, 0.01, "Spawn timer should converge")


func test_kill_sets_dead():
	var enemy = _make_enemy()
	enemy.kill()
	assert_eq(enemy.state, EnemyEntity.State.DEAD)
