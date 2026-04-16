extends GutTest

var DamageSystemCls = preload("res://simulation/systems/damage_system.gd")
var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")
var EnemyParamsCls = preload("res://simulation/entities/enemy_params.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


func test_apply_damage_to_enemy():
	var damage_system = DamageSystemCls.new()
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParamsCls.new()
	params.max_health = 100
	enemy.initialize(1, Vector2.ZERO, params)

	var result = damage_system.apply_damage(enemy, 30, {
		"source_entity_id": 5,
		"projectile_id": 10,
		"element": "frost",
	})

	assert_eq(enemy.health.current, 70)
	assert_eq(result["damage_dealt"], 30)
	assert_false(result["killed"])


func test_apply_damage_kills_enemy():
	var damage_system = DamageSystemCls.new()
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParamsCls.new()
	params.max_health = 50
	enemy.initialize(1, Vector2.ZERO, params)

	var result = damage_system.apply_damage(enemy, 50, {})

	assert_eq(enemy.health.current, 0)
	assert_true(result["killed"])
	assert_eq(enemy.state, EnemyEntity.State.DEAD)


func test_apply_damage_to_player():
	var damage_system = DamageSystemCls.new()
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(1, Vector2.ZERO)

	var result = damage_system.apply_damage(player, 40, {
		"source_entity_id": 99,
		"element": "frost",
	})

	assert_eq(player.health.current, 60)
	assert_eq(result["damage_dealt"], 40)
	assert_false(result["killed"])


func test_apply_damage_kills_player():
	var damage_system = DamageSystemCls.new()
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(1, Vector2(100, 100))

	var result = damage_system.apply_damage(player, 100, {})

	assert_true(result["killed"])
	assert_eq(player.state, PlayerMovementState.GHOST)


func test_apply_damage_on_dead_enemy_is_noop():
	# If an already-dead target is hit again (e.g. a second projectile in flight
	# or a future AoE trigger re-applying), DamageSystem must not fire a second
	# enemy_died event — consumers would try to destroy the same view twice.
	var damage_system = DamageSystemCls.new()
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParamsCls.new()
	params.max_health = 30
	enemy.initialize(1, Vector2.ZERO, params)

	damage_system.apply_damage(enemy, 30, {})  # kills
	assert_true(enemy.health.is_dead())
	var death_count: int = 0
	var counter := func(_e: Dictionary) -> void:
		death_count += 1
	EventBus.enemy_died.connect(counter)

	var result = damage_system.apply_damage(enemy, 20, {})  # should be no-op

	EventBus.enemy_died.disconnect(counter)
	assert_eq(result["damage_dealt"], 0)
	assert_false(result["killed"])
	assert_eq(death_count, 0, "Must not re-emit enemy_died for already-dead target")


func test_apply_damage_on_ghost_player_is_noop():
	var damage_system = DamageSystemCls.new()
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(1, Vector2(100, 100))

	damage_system.apply_damage(player, 100, {})  # kills, enters GHOST
	assert_eq(player.state, PlayerMovementState.GHOST)
	var died_count: int = 0
	var counter := func(_e: Dictionary) -> void:
		died_count += 1
	EventBus.player_died.connect(counter)

	var result = damage_system.apply_damage(player, 50, {})

	EventBus.player_died.disconnect(counter)
	assert_eq(result["damage_dealt"], 0)
	assert_false(result["killed"])
	assert_eq(died_count, 0)


func test_apply_negative_damage_is_noop():
	var damage_system = DamageSystemCls.new()
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParamsCls.new()
	params.max_health = 100
	enemy.initialize(1, Vector2.ZERO, params)

	damage_system.apply_damage(enemy, 30, {})  # 70 remaining
	var result = damage_system.apply_damage(enemy, -50, {})

	assert_eq(enemy.health.current, 70, "Negative damage must not heal")
	assert_eq(result["damage_dealt"], 0)
