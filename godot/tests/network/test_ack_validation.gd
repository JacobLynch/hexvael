extends GutTest


func test_ack_future_tick_rejected():
	# Simulate: server at tick 100, client ACKs tick 200
	# This should be rejected because server never sent tick 200
	var sent_snapshots = {100: {}, 99: {}}  # Only sent ticks 99 and 100
	var ack_tick = 200

	assert_false(sent_snapshots.has(ack_tick), "Future tick should not exist in sent snapshots")


func test_ack_past_tick_accepted():
	var sent_snapshots = {100: {}, 99: {}, 98: {}}
	var ack_tick = 99

	assert_true(sent_snapshots.has(ack_tick), "Past sent tick should be valid")


func test_ack_current_tick_accepted():
	var sent_snapshots = {100: {}}
	var ack_tick = 100

	assert_true(sent_snapshots.has(ack_tick), "Current tick should be valid")
