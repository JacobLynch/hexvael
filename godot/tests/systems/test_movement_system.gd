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
	assert_eq(_player.velocity, Vector2(PlayerEntity.SPEED, 0.0))


func test_process_multiple_inputs_applies_last():
	var inputs = [
		{"input_seq": 1, "direction": Vector2(1.0, 0.0), "tick": 10},
		{"input_seq": 2, "direction": Vector2(0.0, -1.0), "tick": 10},
	]
	_system.process_inputs_for_player(1, inputs)
	# After processing both, velocity should reflect the last input
	assert_eq(_player.velocity, Vector2(0.0, -PlayerEntity.SPEED))


func test_process_empty_inputs_keeps_last_velocity():
	_player.apply_input(Vector2(1.0, 0.0))
	_system.process_inputs_for_player(1, [])
	assert_eq(_player.velocity, Vector2(PlayerEntity.SPEED, 0.0))


func test_tick_all_calls_move_and_slide():
	_player.apply_input(Vector2(1.0, 0.0))
	var pos_before = _player.position
	_system.tick_all()
	# After move_and_slide, position should have changed (no collision in test)
	assert_ne(_player.position, pos_before, "Position should change after tick")


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
