extends GutTest


func test_get_seed_returns_seeded_value():
	RNG.seed(42)
	assert_eq(RNG.get_seed(), 42)


func test_get_seed_returns_updated_value():
	RNG.seed(100)
	assert_eq(RNG.get_seed(), 100)
	RNG.seed(200)
	assert_eq(RNG.get_seed(), 200)


func test_next_float_range():
	RNG.seed(42)
	var val = RNG.next_float_range(-0.5, 0.5)
	assert_true(val >= -0.5 and val <= 0.5, "Value should be within range")
	for i in range(100):
		val = RNG.next_float_range(-1.0, 1.0)
		assert_true(val >= -1.0 and val <= 1.0, "Iteration %d out of range" % i)
