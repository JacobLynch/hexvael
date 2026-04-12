extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileEntityCls = preload("res://simulation/entities/projectile_entity.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")

func _make_system() -> ProjectileSystem:
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	return sys

func test_adopt_rekeys_matching_predicted_by_input_seq():
	var sys = _make_system()
	sys.spawn_predicted(42, ProjectileType.Id.TEST,
		Vector2.ZERO, Vector2.RIGHT, 77)
	assert_true(sys.projectiles.has(-77))

	sys.adopt_authoritative(500, 42, ProjectileType.Id.TEST,
		Vector2.ZERO, Vector2.RIGHT, 77, 0)

	assert_false(sys.projectiles.has(-77))
	assert_true(sys.projectiles.has(500))
	assert_eq(sys.projectiles[500].projectile_id, 500)
	assert_false(sys.projectiles[500].is_predicted)

func test_adopt_spawns_fresh_when_no_matching_predicted():
	var sys = _make_system()
	sys.adopt_authoritative(500, 99, ProjectileType.Id.TEST,
		Vector2(100, 100), Vector2.RIGHT, 77, 100)
	assert_true(sys.projectiles.has(500))
	# Fresh spawn should fast-forward by rtt/2 = 50 ms = 0.05s × 600 px/s = 30 px
	var p: ProjectileEntity = sys.projectiles[500]
	assert_almost_eq(p.position.x, 130.0, 1.0)

func test_on_despawn_event_removes_projectile():
	var sys = _make_system()
	var pred = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
		Vector2.ZERO, Vector2.RIGHT, 1)
	var id = pred.projectile_id
	sys.on_despawn_event(id, ProjectileEntityCls.DespawnReason.WALL, Vector2(10, 10))
	assert_false(sys.projectiles.has(id))

func test_on_despawn_event_idempotent_on_missing_id():
	var sys = _make_system()
	# No crash when despawning an id that doesn't exist
	sys.on_despawn_event(999, ProjectileEntityCls.DespawnReason.WALL, Vector2(10, 10))
	pass_test("did not crash")
