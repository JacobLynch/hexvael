extends GutTest


func test_get_seed_returns_seeded_value():
	RNG.seed(42)
	assert_eq(RNG.get_seed(), 42)


func test_get_seed_returns_updated_value():
	RNG.seed(100)
	assert_eq(RNG.get_seed(), 100)
	RNG.seed(200)
	assert_eq(RNG.get_seed(), 200)
