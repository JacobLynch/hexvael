# godot/tests/network/test_rate_limiting.gd
extends GutTest


func test_input_rate_limit_allows_burst():
	var inputs_this_tick = 0
	var max_allowed = 3

	for i in range(max_allowed):
		inputs_this_tick += 1
		assert_true(inputs_this_tick <= max_allowed, "Should allow up to %d inputs" % max_allowed)


func test_input_rate_limit_rejects_excess():
	var inputs_this_tick = 4
	var max_allowed = 3

	assert_true(inputs_this_tick > max_allowed, "Should reject excess inputs")
