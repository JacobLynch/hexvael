extends GutTest

var ProjectileEntity = preload("res://simulation/entities/projectile_entity.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")
var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")

func _make(origin: Vector2 = Vector2.ZERO,
		dir: Vector2 = Vector2.RIGHT) -> ProjectileEntity:
	var p = ProjectileEntity.new()
	var params = ProjectileType.get_params(ProjectileType.Id.TEST)
	p.initialize(1, ProjectileType.Id.TEST, 42, origin, dir, params)
	return p

func test_advance_moves_projectile_along_direction():
	var p = _make(Vector2(100, 100), Vector2.RIGHT)
	var reason = p.advance(0.5, [], [], [])
	assert_eq(reason, ProjectileSystemCls.DespawnReason.ALIVE)
	assert_almost_eq(p.position.x, 100.0 + 600.0 * 0.5, 0.01)
	assert_almost_eq(p.position.y, 100.0, 0.01)

func test_advance_lifetime_despawn():
	var p = _make()
	p.advance(2.0, [], [], [])   # past the 1.5 s lifetime
	assert_true(p.time_remaining <= 0.0)

func test_advance_returns_lifetime_reason():
	var p = _make()
	var reason = p.advance(2.0, [], [], [])
	assert_eq(reason, ProjectileSystemCls.DespawnReason.LIFETIME)

func test_advance_wall_collision_returns_wall_reason():
	# Flying toward a wall at x=[-8, 0]. Start at (100, 800) moving LEFT at 600 px/s.
	# 100 / 600 ≈ 0.167 sec until hit. Advance in ~33ms chunks (5 steps).
	var p = _make(Vector2(100, 800), Vector2.LEFT)
	var walls: Array[Rect2] = [Rect2(Vector2(-8, 0), Vector2(8, 1600))]
	var reason: int = ProjectileSystemCls.DespawnReason.ALIVE
	for i in 30:
		reason = p.advance(0.033, walls, [], [])
		if reason != ProjectileSystemCls.DespawnReason.ALIVE:
			break
	assert_eq(reason, ProjectileSystemCls.DespawnReason.WALL)

func test_dt_independence_canary_straight_line():
	# The core determinism invariant: coarse and fine dt chunking must converge.
	var a = _make()
	var b = _make()
	for _i in 60:
		a.advance(1.0 / 60.0, [], [], [])
	for _i in 30:
		b.advance(1.0 / 30.0, [], [], [])
	assert_true(a.position.distance_to(b.position) < 0.01,
		"server tick and client frame must converge for same straight-line path")

func test_start_reconcile_sets_target_delta():
	var p = _make(Vector2(0, 0), Vector2.RIGHT)
	p.start_reconcile(Vector2(20, 0))  # target 20 px right of current
	assert_almost_eq(p._reconcile_delta.x, 20.0, 0.01)
	assert_almost_eq(p._reconcile_remaining, 0.1, 0.01)

func test_reconcile_lerp_converges_over_duration():
	var p = _make(Vector2(0, 0), Vector2.RIGHT)
	# Disable motion contribution for the test by zeroing direction
	p.direction = Vector2.ZERO
	p.start_reconcile(Vector2(20, 0))
	var total_dt = 0.0
	while p._reconcile_remaining > 0.0 and total_dt < 1.0:
		p.advance(1.0 / 60.0, [], [], [])
		total_dt += 1.0 / 60.0
	assert_almost_eq(p.position.x, 20.0, 0.5)
