extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")

func _make_system() -> ProjectileSystem:
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	return sys

func test_spawn_authoritative_assigns_monotonic_ids():
	var sys = _make_system()
	var a = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
		Vector2(100, 100), Vector2.RIGHT, 1)
	var b = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
		Vector2(100, 100), Vector2.RIGHT, 2)
	assert_gt(b.projectile_id, a.projectile_id)
	assert_eq(sys.projectiles.size(), 2)

func test_spawn_authoritative_stores_owner_and_direction():
	var sys = _make_system()
	var p = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
		Vector2(100, 100), Vector2.RIGHT, 7)
	assert_eq(p.owner_player_id, 42)
	assert_eq(p.direction, Vector2.RIGHT)
	assert_eq(p.spawn_input_seq, 7)
	assert_false(p.is_predicted)

func test_spawn_predicted_uses_negative_id():
	var sys = _make_system()
	var p = sys.spawn_predicted(42, ProjectileType.Id.TEST,
		Vector2(100, 100), Vector2.RIGHT, 55)
	assert_eq(p.projectile_id, -55)
	assert_true(p.is_predicted)
	assert_true(sys.projectiles.has(-55))

func test_spawn_predicted_does_not_collide_with_authoritative_ids():
	var sys = _make_system()
	var auth = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
		Vector2(100, 100), Vector2.RIGHT, 1)
	var pred = sys.spawn_predicted(42, ProjectileType.Id.TEST,
		Vector2(100, 100), Vector2.RIGHT, 99)
	assert_ne(auth.projectile_id, pred.projectile_id)
	assert_eq(sys.projectiles.size(), 2)
