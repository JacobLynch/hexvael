extends GutTest

var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


func _make_enemy(pos: Vector2 = Vector2(100, 100)) -> EnemyEntity:
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParams.new()
	params.detection_radius = 200.0
	params.leash_radius = 300.0
	params.hysteresis_distance = 80.0
	RNG.seed(42)
	enemy.initialize(1, pos, params)
	return enemy


func _make_player(id: int, pos: Vector2) -> PlayerEntity:
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(id, pos)
	return player


func test_idle_detects_player_in_range():
	var enemy = _make_enemy()
	enemy.state = EnemyEntity.State.IDLE
	var player = _make_player(1, Vector2(150, 100))
	enemy.advance(0.05, [player], [])
	assert_eq(enemy.state, EnemyEntity.State.CHASING)
	assert_eq(enemy.target_player_id, 1)


func test_idle_ignores_player_outside_detection():
	var enemy = _make_enemy()
	enemy.state = EnemyEntity.State.IDLE
	var player = _make_player(1, Vector2(400, 100))
	enemy.advance(0.05, [player], [])
	assert_eq(enemy.state, EnemyEntity.State.IDLE)


func test_chasing_leash_returns_to_idle():
	var enemy = _make_enemy()
	enemy.state = EnemyEntity.State.CHASING
	enemy.facing = Vector2.RIGHT
	var player = _make_player(1, Vector2(500, 100))
	enemy.target_player_id = 1
	enemy.advance(0.05, [player], [])
	assert_eq(enemy.state, EnemyEntity.State.IDLE, "Should leash back to idle")
	assert_eq(enemy.target_player_id, -1)


func test_sticky_aggro_keeps_target():
	var enemy = _make_enemy()
	enemy.state = EnemyEntity.State.CHASING
	enemy.facing = Vector2.RIGHT
	var p1 = _make_player(1, Vector2(200, 100))
	var p2 = _make_player(2, Vector2(180, 100))
	enemy.target_player_id = 1
	enemy.advance(0.05, [p1, p2], [])
	assert_eq(enemy.target_player_id, 1, "Should stick to original target")


func test_hysteresis_switches_target():
	var enemy = _make_enemy()
	enemy.state = EnemyEntity.State.CHASING
	enemy.facing = Vector2.RIGHT
	var p1 = _make_player(1, Vector2(290, 100))
	var p2 = _make_player(2, Vector2(105, 100))
	enemy.target_player_id = 1
	enemy.advance(0.05, [p1, p2], [])
	assert_eq(enemy.target_player_id, 2, "Should switch to much closer player")


func test_retargets_on_disconnect():
	# When the current target is not in the player list (disconnect), the enemy
	# transitions to IDLE on the first advance.  A second advance from IDLE then
	# detects the remaining player within detection_radius and begins chasing.
	var enemy = _make_enemy()
	enemy.state = EnemyEntity.State.CHASING
	enemy.facing = Vector2.RIGHT
	enemy.target_player_id = 1
	var p2 = _make_player(2, Vector2(150, 100))
	enemy.advance(0.05, [p2], [])
	assert_eq(enemy.state, EnemyEntity.State.IDLE, "Should go IDLE when target disconnects")
	enemy.advance(0.05, [p2], [])
	assert_eq(enemy.target_player_id, 2, "Should retarget to available player on next tick")
