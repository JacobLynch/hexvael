extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileEntityCls = preload("res://simulation/entities/projectile_entity.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")

func test_predicted_projectile_times_out_to_rejected():
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	sys._current_rtt_ms = 100   # 0.1 s RTT, so timeout = 0.3 s
	sys.spawn_predicted(42, ProjectileType.Id.TEST,
		Vector2.ZERO, Vector2.RIGHT, 77)

	# Advance past the timeout in small chunks
	var despawned: Array = []
	for _i in 20:
		despawned = sys.advance(0.02, [], [])
		if despawned.size() > 0:
			break

	assert_eq(despawned.size(), 1)
	assert_eq(despawned[0]["reason"], ProjectileEntityCls.DespawnReason.REJECTED)
	assert_false(sys.projectiles.has(-77))

func test_authoritative_projectile_never_times_out_to_rejected():
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	sys._current_rtt_ms = 100
	var p = sys.spawn_authoritative(42, ProjectileType.Id.TEST,
		Vector2.ZERO, Vector2.RIGHT, 1)
	p.time_remaining = 100.0   # force lifetime to not expire
	for _i in 20:
		var despawned = sys.advance(0.02, [], [])
		for entry in despawned:
			assert_ne(entry["reason"], ProjectileEntityCls.DespawnReason.REJECTED)
	# Authoritative projectile must still be alive after 20 advances at 0.02s each
	assert_true(sys.projectiles.has(p.projectile_id), "authoritative projectile should still be alive")
