extends GutTest

var MovementSystem = preload("res://simulation/systems/movement_system.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")

var _system: MovementSystem
var _player: PlayerEntity


func before_each():
	_system = MovementSystem.new()
	add_child_autofree(_system)
	_player = PlayerEntityScene.instantiate()
	add_child_autofree(_player)
	_player.initialize(1, Vector2(100.0, 100.0))
	_system.register_player(_player)


func test_process_inputs_applies_direction():
	var inputs = [
		{"input_seq": 1, "direction": Vector2(1.0, 0.0), "tick": 10},
	]
	_system.process_inputs_for_player(1, inputs)
	assert_eq(_player.move_input, Vector2(1.0, 0.0))


func test_process_multiple_inputs_applies_last():
	var inputs = [
		{"input_seq": 1, "direction": Vector2(1.0, 0.0), "tick": 10},
		{"input_seq": 2, "direction": Vector2(0.0, -1.0), "tick": 10},
	]
	_system.process_inputs_for_player(1, inputs)
	# After processing both, move_input should reflect the last input
	assert_eq(_player.move_input, Vector2(0.0, -1.0))


func test_process_empty_inputs_keeps_last_velocity():
	_player.apply_input(Vector2(1.0, 0.0))
	_system.process_inputs_for_player(1, [])
	assert_eq(_player.move_input, Vector2(1.0, 0.0))


func test_advance_all_moves_players():
	_player.apply_input(Vector2(1.0, 0.0))
	var pos_before = _player.position
	var tick_dt = MessageTypes.TICK_INTERVAL_MS / 1000.0
	# Accel needs a few ticks to build up movement
	for i in range(3):
		_system.advance_all(tick_dt)
	assert_ne(_player.position, pos_before, "Position should change after advance_all")


func test_register_and_unregister_player():
	assert_true(_system.has_player(1))
	_system.unregister_player(1)
	assert_false(_system.has_player(1))


func test_updates_last_processed_seq():
	var inputs = [
		{"input_seq": 5, "direction": Vector2(1.0, 0.0), "tick": 10},
		{"input_seq": 7, "direction": Vector2(0.0, 1.0), "tick": 10},
	]
	_system.process_inputs_for_player(1, inputs)
	assert_eq(_player.last_processed_input_seq, 7)
