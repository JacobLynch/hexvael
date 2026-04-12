extends GutTest

var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")

func test_player_collision_radius_positive():
	var p = PlayerEntityScene.instantiate()
	add_child_autofree(p)
	assert_gt(p.get_collision_radius(), 0.0)
	assert_lt(p.get_collision_radius(), 100.0)

func test_enemy_collision_radius_positive():
	var e = EnemyEntityScene.instantiate()
	add_child_autofree(e)
	assert_gt(e.get_collision_radius(), 0.0)
	assert_lt(e.get_collision_radius(), 100.0)

func test_player_collision_radius_cached():
	var p = PlayerEntityScene.instantiate()
	add_child_autofree(p)
	var r1 = p.get_collision_radius()
	var r2 = p.get_collision_radius()
	assert_eq(r1, r2)
