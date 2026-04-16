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
