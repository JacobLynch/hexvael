extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileEntityCls = preload("res://simulation/entities/projectile_entity.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")

func _make_system() -> ProjectileSystem:
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	return sys

func test_advance_steps_all_projectiles():
	var sys = _make_system()
	sys.spawn_authoritative(42, ProjectileType.Id.TEST,
		Vector2.ZERO, Vector2.RIGHT, 1)
	sys.spawn_authoritative(42, ProjectileType.Id.TEST,
		Vector2(500, 500), Vector2.DOWN, 2)
	sys.advance(0.05, [], [])
	for id in sys.projectiles.keys():
		var p = sys.projectiles[id]
		assert_ne(p.position, Vector2.ZERO)

func test_advance_removes_despawned_projectiles():
	var sys = _make_system()
	var p = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
		Vector2.ZERO, Vector2.RIGHT, 1)
	p.time_remaining = 0.001   # force near-immediate lifetime expiry
	var despawned = sys.advance(0.1, [], [])
	assert_eq(despawned.size(), 1)
	assert_eq(despawned[0]["reason"], ProjectileEntityCls.DespawnReason.LIFETIME)
	assert_false(sys.projectiles.has(p.projectile_id))

func test_advance_returns_empty_array_when_no_despawns():
	var sys = _make_system()
	sys.spawn_authoritative(42, ProjectileType.Id.TEST,
		Vector2(1000, 1000), Vector2.RIGHT, 1)
	var despawned = sys.advance(0.05, [], [])
	assert_eq(despawned.size(), 0)
