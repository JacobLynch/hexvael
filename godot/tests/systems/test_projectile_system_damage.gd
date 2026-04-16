extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var DamageSystemCls = preload("res://simulation/systems/damage_system.gd")
var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")
var EnemyParamsCls = preload("res://simulation/entities/enemy_params.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


func test_projectile_damages_enemy_on_hit():
	var projectile_system = ProjectileSystemCls.new()
	var damage_system = DamageSystemCls.new()
	projectile_system.set_damage_system(damage_system)
	add_child_autofree(projectile_system)

	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParamsCls.new()
	params.max_health = 100
	enemy.initialize(1, Vector2(50, 0), params)
	enemy._set_state(EnemyEntity.State.IDLE)  # Not spawning

	var proj = projectile_system.spawn_authoritative(99, 0, Vector2.ZERO, Vector2.RIGHT, 1)
	proj.params.damage = 25
	proj.params.radius = 10.0

	projectile_system.advance(0.1, [], [enemy])

	assert_eq(enemy.health.current, 75, "Enemy should have taken 25 damage")


func test_projectile_damages_other_player():
	var projectile_system = ProjectileSystemCls.new()
	var damage_system = DamageSystemCls.new()
	projectile_system.set_damage_system(damage_system)
	add_child_autofree(projectile_system)

	var target = PlayerEntityScene.instantiate()
	add_child_autofree(target)
	target.initialize(2, Vector2(50, 0))

	var proj = projectile_system.spawn_authoritative(1, 0, Vector2.ZERO, Vector2.RIGHT, 1)
	proj.params.damage = 25
	proj.params.radius = 10.0
	proj.params.spawn_grace = 0.0  # No grace period

	projectile_system.advance(0.1, [target], [])

	assert_eq(target.health.current, 75, "Target should have taken 25 damage")
