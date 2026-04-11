extends GutTest

const MovementParams = preload("res://shared/movement/movement_params.gd")

func test_default_values():
	var params = MovementParams.new()
	assert_eq(params.top_speed, 200.0)
	assert_almost_eq(params.accel, 1800.0, 0.01)
	assert_almost_eq(params.friction, 18.0, 0.01)
	assert_almost_eq(params.dodge_speed, 700.0, 0.01)
	assert_almost_eq(params.dodge_duration, 0.2, 0.001)
	assert_almost_eq(params.dodge_cooldown, 0.7, 0.001)
	assert_almost_eq(params.dodge_iframe_duration, 0.2, 0.001)

func test_default_tres_loads():
	var params = load("res://shared/movement/default_movement_params.tres")
	assert_not_null(params, "default_movement_params.tres should load")
	assert_eq(params.top_speed, 200.0)
	assert_almost_eq(params.dodge_duration, 0.2, 0.001)

func test_runtime_swap():
	# Proves that swapping params at runtime works — future surface/gear integration
	var base = MovementParams.new()
	var slowed = MovementParams.new()
	slowed.top_speed = 50.0
	assert_eq(base.top_speed, 200.0)
	assert_eq(slowed.top_speed, 50.0)
