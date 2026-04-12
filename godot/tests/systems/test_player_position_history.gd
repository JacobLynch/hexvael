extends GutTest

var PlayerPositionHistory = preload("res://simulation/systems/player_position_history.gd")


func test_record_and_lookup_exact_tick():
	var hist = PlayerPositionHistory.new()
	hist.record(1, 100, Vector2(50, 50))
	assert_eq(hist.lookup(1, 100), Vector2(50, 50))


func test_lookup_returns_closest_older_sample():
	var hist = PlayerPositionHistory.new()
	hist.record(1, 100, Vector2(50, 50))
	hist.record(1, 105, Vector2(100, 100))
	# Between 100 and 105 — pick the one at-or-before.
	assert_eq(hist.lookup(1, 103), Vector2(50, 50))


func test_lookup_returns_latest_when_target_in_future():
	var hist = PlayerPositionHistory.new()
	hist.record(1, 100, Vector2(50, 50))
	hist.record(1, 105, Vector2(100, 100))
	assert_eq(hist.lookup(1, 200), Vector2(100, 100))


func test_lookup_returns_oldest_when_target_too_far_back():
	var hist = PlayerPositionHistory.new()
	hist.record(1, 100, Vector2(50, 50))
	hist.record(1, 105, Vector2(100, 100))
	assert_eq(hist.lookup(1, 50), Vector2(50, 50))


func test_ring_buffer_prunes_to_max_samples():
	var hist = PlayerPositionHistory.new()
	for i in 100:
		hist.record(1, i, Vector2(i, 0))
	# Should keep MAX_SAMPLES (32) most-recent samples
	assert_eq(hist._samples_per_player[1].size(), PlayerPositionHistory.MAX_SAMPLES)
	# Oldest kept sample should be tick (100 - MAX_SAMPLES)
	assert_eq(hist._samples_per_player[1][0]["tick"],
		100 - PlayerPositionHistory.MAX_SAMPLES)


func test_drop_player_removes_all_samples():
	var hist = PlayerPositionHistory.new()
	hist.record(1, 100, Vector2(50, 50))
	hist.drop_player(1)
	assert_false(hist._samples_per_player.has(1))


func test_per_player_isolation():
	var hist = PlayerPositionHistory.new()
	hist.record(1, 100, Vector2(50, 50))
	hist.record(2, 100, Vector2(200, 200))
	assert_eq(hist.lookup(1, 100), Vector2(50, 50))
	assert_eq(hist.lookup(2, 100), Vector2(200, 200))
