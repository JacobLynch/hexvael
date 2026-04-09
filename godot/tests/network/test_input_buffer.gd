extends GutTest

var InputBuffer = preload("res://simulation/network/input_buffer.gd")

var _buffer: InputBuffer


func before_each():
	_buffer = InputBuffer.new()


func test_add_and_drain_inputs():
	_buffer.add_input(1, {
		"tick": 10, "direction": Vector2.RIGHT, "input_seq": 1,
	})
	_buffer.add_input(1, {
		"tick": 10, "direction": Vector2.UP, "input_seq": 2,
	})
	var inputs = _buffer.drain_inputs_for_player(1)
	assert_eq(inputs.size(), 2)
	assert_eq(inputs[0]["input_seq"], 1, "Should be in sequence order")
	assert_eq(inputs[1]["input_seq"], 2)


func test_drain_clears_buffer():
	_buffer.add_input(1, {
		"tick": 10, "direction": Vector2.RIGHT, "input_seq": 1,
	})
	_buffer.drain_inputs_for_player(1)
	var inputs = _buffer.drain_inputs_for_player(1)
	assert_eq(inputs.size(), 0, "Buffer should be empty after drain")


func test_inputs_sorted_by_sequence():
	_buffer.add_input(1, {
		"tick": 10, "direction": Vector2.RIGHT, "input_seq": 3,
	})
	_buffer.add_input(1, {
		"tick": 10, "direction": Vector2.UP, "input_seq": 1,
	})
	_buffer.add_input(1, {
		"tick": 10, "direction": Vector2.LEFT, "input_seq": 2,
	})
	var inputs = _buffer.drain_inputs_for_player(1)
	assert_eq(inputs[0]["input_seq"], 1)
	assert_eq(inputs[1]["input_seq"], 2)
	assert_eq(inputs[2]["input_seq"], 3)


func test_separate_players():
	_buffer.add_input(1, {
		"tick": 10, "direction": Vector2.RIGHT, "input_seq": 1,
	})
	_buffer.add_input(2, {
		"tick": 10, "direction": Vector2.LEFT, "input_seq": 1,
	})
	var p1 = _buffer.drain_inputs_for_player(1)
	var p2 = _buffer.drain_inputs_for_player(2)
	assert_eq(p1.size(), 1)
	assert_eq(p2.size(), 1)
	assert_eq(p1[0]["direction"], Vector2.RIGHT)
	assert_eq(p2[0]["direction"], Vector2.LEFT)


func test_drain_unknown_player_returns_empty():
	var inputs = _buffer.drain_inputs_for_player(99)
	assert_eq(inputs.size(), 0)


func test_duplicate_sequence_ignored():
	_buffer.add_input(1, {
		"tick": 10, "direction": Vector2.RIGHT, "input_seq": 1,
	})
	_buffer.add_input(1, {
		"tick": 10, "direction": Vector2.LEFT, "input_seq": 1,
	})
	var inputs = _buffer.drain_inputs_for_player(1)
	assert_eq(inputs.size(), 1, "Duplicate seq should be ignored")


func test_remove_player():
	_buffer.add_input(1, {
		"tick": 10, "direction": Vector2.RIGHT, "input_seq": 1,
	})
	_buffer.remove_player(1)
	var inputs = _buffer.drain_inputs_for_player(1)
	assert_eq(inputs.size(), 0)
