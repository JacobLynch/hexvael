extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileEntityCls = preload("res://simulation/entities/projectile_entity.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")

func test_predicted_projectile_times_out_to_rejected():
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	# rtt=100ms → 2*rtt+0.1 = 0.3s, but a 0.5s floor guards against stale RTT
	# estimates rejecting valid adoptions during startup. Use a rtt that
	# clears the floor so the computed timeout (not the floor) is exercised.
	sys._current_rtt_ms = 500   # 2*0.5 + 0.1 = 1.1s computed; above 0.5 floor
	sys.spawn_predicted(42, ProjectileType.Id.TEST,
		Vector2.ZERO, Vector2.RIGHT, 77)

	# Advance past the 1.1s computed timeout in small chunks
	var despawned: Array = []
	for _i in 70:
		despawned = sys.advance(0.02, [], [])
		if despawned.size() > 0:
			break

	assert_eq(despawned.size(), 1)
	assert_eq(despawned[0]["reason"], ProjectileEntityCls.DespawnReason.REJECTED)
	assert_false(sys.projectiles.has(-77))


func test_rejection_timeout_is_floored_for_stale_rtt():
	# The defect this guards against: before the first snapshot ack, _rtt_ms
	# is still 0, so the raw 2*rtt+0.1 formula yields 100ms — shorter than
	# a real fire's adoption round-trip (~125ms+), which silently REJECTS
	# every early prediction and drops a fresh authoritative projectile in
	# its place. The floor keeps the window wide enough until rtt warms up.
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	sys._current_rtt_ms = 0   # pre-warmup state
	sys.spawn_predicted(42, ProjectileType.Id.TEST,
		Vector2.ZERO, Vector2.RIGHT, 77)

	# At the old 0.1s timeout this would be dead by 0.12s. Advance to 0.4s
	# — still comfortably under the 0.5s floor — and verify survival.
	for _i in 20:
		var despawned: Array = sys.advance(0.02, [], [])
		for entry in despawned:
			assert_ne(entry["reason"], ProjectileEntityCls.DespawnReason.REJECTED,
				"floor must prevent rejection while rtt estimate is still zero")
	assert_true(sys.projectiles.has(-77),
		"predicted projectile must still be alive at 0.4s with rtt=0 (floor=0.5s)")

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
