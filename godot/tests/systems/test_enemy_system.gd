extends GutTest

var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")

var _system: EnemySystem


func before_each():
	_system = EnemySystem.new()
	add_child_autofree(_system)


func _make_enemy(id: int, pos: Vector2 = Vector2(100, 100)) -> EnemyEntity:
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParams.new()
	RNG.seed(id * 7)
	enemy.initialize(id, pos, params)
	return enemy


func _make_player(id: int, pos: Vector2) -> PlayerEntity:
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(id, pos)
	return player


func test_register_and_get():
	var enemy = _make_enemy(10001)
	_system.register_enemy(enemy)
	assert_true(_system.has_enemy(10001))
	assert_eq(_system.get_enemy(10001), enemy)


func test_unregister():
	var enemy = _make_enemy(10001)
	_system.register_enemy(enemy)
	_system.unregister_enemy(10001)
	assert_false(_system.has_enemy(10001))


func test_get_all_enemies():
	var e1 = _make_enemy(10001, Vector2(50, 50))
	var e2 = _make_enemy(10002, Vector2(150, 150))
	_system.register_enemy(e1)
	_system.register_enemy(e2)
	assert_eq(_system.get_all_enemies().size(), 2)


func test_advance_all_ticks_enemies():
	var enemy = _make_enemy(10001)
	_system.register_enemy(enemy)
	var initial_timer = enemy.spawn_timer
	var players: Dictionary = {}
	_system.advance_all(0.1, players)
	assert_almost_eq(enemy.spawn_timer, initial_timer - 0.1, 0.01)


func test_advance_all_removes_dead_enemies():
	var enemy = _make_enemy(10001)
	_system.register_enemy(enemy)
	enemy.kill()
	var players: Dictionary = {}
	_system.advance_all(0.05, players)
	assert_false(_system.has_enemy(10001), "Dead enemy should be removed")


func test_get_enemies_in_radius():
	var e1 = _make_enemy(10001, Vector2(50, 50))
	var e2 = _make_enemy(10002, Vector2(55, 50))
	var e3 = _make_enemy(10003, Vector2(500, 500))
	e1.state = EnemyEntity.State.IDLE
	e2.state = EnemyEntity.State.IDLE
	e3.state = EnemyEntity.State.IDLE
	_system.register_enemy(e1)
	_system.register_enemy(e2)
	_system.register_enemy(e3)
	_system.advance_all(0.0, {})
	var nearby = _system.get_enemies_in_radius(Vector2(50, 50), 30.0)
	assert_eq(nearby.size(), 2, "Should find 2 nearby enemies")
