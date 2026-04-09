extends GutTest

var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
const MovementParams = preload("res://shared/movement/movement_params.gd")

var _params: MovementParams


func before_each():
	_params = MovementParams.new()


func _make_player() -> PlayerEntity:
	var p = PlayerEntityScene.instantiate()
	add_child_autofree(p)
	p.initialize(1, Vector2(100.0, 100.0))
	p.params = _params
	return p


func test_accel_reaches_top_speed():
	var p = _make_player()
	p.apply_input({"move_direction": Vector2(1.0, 0.0), "aim_direction": Vector2.RIGHT})
	# At accel=1800, top_speed=200, time to top is ~0.111s. Advance 0.2s in small steps.
	for i in range(20):
		p.advance(0.01)
	assert_almost_eq(p.velocity.x, 200.0, 1.0, "Should reach top_speed within 0.2s")


func test_friction_decays_to_near_zero_after_release():
	var p = _make_player()
	p.velocity = Vector2(200.0, 0.0)
	p.apply_input({"move_direction": Vector2.ZERO, "aim_direction": Vector2.RIGHT})
	# Exponential friction at coeff=18 halves in ~38ms. After 0.3s should be < 1.
	for i in range(30):
		p.advance(0.01)
	assert_lt(p.velocity.length(), 1.0, "Velocity should decay to near-zero after release")


func test_dt_independence_canary():
	# THE CANARY: running advance(0.1) once vs advance(0.01) ten times must converge.
	# If this fails, someone wrote framerate-dependent math (velocity *= 0.9 etc).
	var coarse = _make_player()
	coarse.apply_input({"move_direction": Vector2(1.0, 0.0), "aim_direction": Vector2.RIGHT})
	coarse.advance(0.1)

	var fine = _make_player()
	fine.apply_input({"move_direction": Vector2(1.0, 0.0), "aim_direction": Vector2.RIGHT})
	for i in range(10):
		fine.advance(0.01)

	assert_almost_eq(coarse.velocity.x, fine.velocity.x, 0.5,
		"Velocity must be dt-independent — coarse vs fine must converge")
	assert_almost_eq(coarse.position.x, fine.position.x, 0.5,
		"Position must be dt-independent — coarse vs fine must converge")


func test_idle_stays_at_rest():
	var p = _make_player()
	var start = p.position
	for i in range(20):
		p.advance(0.05)
	assert_eq(p.position, start, "Idle player should not drift")
	assert_eq(p.velocity, Vector2.ZERO)


func test_diagonal_input_normalizes():
	var p = _make_player()
	p.apply_input({"move_direction": Vector2(1.0, 1.0), "aim_direction": Vector2.RIGHT})
	# Advance long enough to reach top speed
	for i in range(30):
		p.advance(0.01)
	assert_almost_eq(p.velocity.length(), 200.0, 1.0,
		"Diagonal movement should not exceed top_speed")


func test_advance_moves_position_with_velocity():
	var p = _make_player()
	p.apply_input({"move_direction": Vector2(1.0, 0.0), "aim_direction": Vector2.RIGHT})
	# Pre-set velocity to skip accel ramp
	p.velocity = Vector2(200.0, 0.0)
	var before = p.position.x
	p.advance(0.1)
	# Expect ~20 px over 0.1s at 200px/s (minus sub-frame rounding)
	assert_almost_eq(p.position.x - before, 20.0, 1.0)
