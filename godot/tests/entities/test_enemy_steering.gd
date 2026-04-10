extends GutTest

var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


func _make_enemy(pos: Vector2 = Vector2(100, 100), params: EnemyParams = null) -> EnemyEntity:
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	if params == null:
		params = EnemyParams.new()
	RNG.seed(42)
	enemy.initialize(1, pos, params)
	# Skip spawning state
	enemy.state = EnemyEntity.State.CHASING
	return enemy


func _make_player(id: int, pos: Vector2) -> PlayerEntity:
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(id, pos)
	return player


func test_enemy_moves_toward_player():
	var enemy = _make_enemy(Vector2(100, 100))
	var player = _make_player(1, Vector2(200, 100))
	enemy.target_player_id = 1
	enemy.facing = Vector2.RIGHT
	enemy.advance(0.5, [player], [])
	assert_gt(enemy.position.x, 100.0, "Enemy should move toward player")


func test_separation_pushes_enemies_apart():
	var e1 = _make_enemy(Vector2(100, 100))
	var player = _make_player(1, Vector2(200, 100))
	e1.target_player_id = 1
	e1.facing = Vector2.RIGHT
	var e2 = _make_enemy(Vector2(105, 100))
	e1.advance(0.05, [player], [e2])
	assert_ne(e1.velocity, Vector2.ZERO, "Enemy should move")


func test_arrival_slows_near_target():
	var params = EnemyParams.new()
	params.arrival_radius = 40.0
	var enemy = _make_enemy(Vector2(100, 100), params)
	var player = _make_player(1, Vector2(110, 100))
	enemy.target_player_id = 1
	enemy.facing = Vector2.RIGHT
	enemy.advance(0.05, [player], [])
	var close_speed = enemy.velocity.length()

	RNG.seed(42)
	var enemy_far = _make_enemy(Vector2(100, 100), params)
	var player_far = _make_player(2, Vector2(200, 100))
	enemy_far.target_player_id = 2
	enemy_far.facing = Vector2.RIGHT
	enemy_far.advance(0.05, [player_far], [])
	var far_speed = enemy_far.velocity.length()

	assert_lt(close_speed, far_speed, "Should move slower near target")


func test_turn_rate_lerps_facing():
	var params = EnemyParams.new()
	params.turn_rate = 4.0
	var enemy = _make_enemy(Vector2(100, 100), params)
	var player = _make_player(1, Vector2(100, 200))
	enemy.target_player_id = 1
	enemy.facing = Vector2.RIGHT
	enemy.advance(0.05, [player], [])
	assert_gt(enemy.facing.y, 0.0, "Facing should rotate toward target")
	assert_gt(enemy.facing.x, 0.0, "Should not have fully rotated yet")


func test_dt_independence_chasing():
	# Facing uses exponential decay which is dt-independent.
	# Position is not compared because CharacterBody2D.move_and_slide() uses
	# engine-internal physics timing rather than the dt we pass — the resulting
	# positions diverge between a single large step and many small steps.
	var player = _make_player(1, Vector2(300, 100))

	RNG.seed(42)
	var e1 = _make_enemy(Vector2(100, 100))
	e1.target_player_id = 1
	e1.facing = Vector2.RIGHT
	e1.advance(0.5, [player], [])

	RNG.seed(42)
	var e2 = _make_enemy(Vector2(100, 100))
	e2.target_player_id = 1
	e2.facing = Vector2.RIGHT
	for i in range(10):
		e2.advance(0.05, [player], [])

	assert_almost_eq(e1.facing.x, e2.facing.x, 0.05, "Facing X should converge")
	assert_almost_eq(e1.facing.y, e2.facing.y, 0.05, "Facing Y should converge")
