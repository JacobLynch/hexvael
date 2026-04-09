extends GutTest

var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
const MovementParams = preload("res://shared/movement/movement_params.gd")
const PlayerMovementState = preload("res://simulation/entities/player_movement_state.gd")

var _params: MovementParams


func before_each():
	_params = MovementParams.new()


func _make_player() -> PlayerEntity:
	var p = PlayerEntityScene.instantiate()
	add_child_autofree(p)
	p.initialize(1, Vector2(240.0, 160.0))  # arena center, away from walls
	p.params = _params
	return p


func test_default_state_is_walking():
	var p = _make_player()
	assert_eq(p.state, PlayerMovementState.WALKING)
	assert_true(p.can_dodge())


func test_dodge_from_walking_with_move_direction():
	var p = _make_player()
	p.move_input = Vector2(1.0, 0.0)
	p.start_dodge()
	assert_eq(p.state, PlayerMovementState.DODGING)
	assert_eq(p.dodge_direction, Vector2(1.0, 0.0))
	assert_almost_eq(p.dodge_time_remaining, _params.dodge_duration, 0.001)
	assert_almost_eq(p.dodge_cooldown_remaining, _params.dodge_cooldown, 0.001)


func test_dodge_falls_back_to_aim_when_no_move_input():
	var p = _make_player()
	p.move_input = Vector2.ZERO
	p.aim_direction = Vector2(0.0, 1.0)  # aiming down
	p.start_dodge()
	assert_eq(p.dodge_direction, Vector2(0.0, 1.0))


func test_cannot_dodge_while_dodging():
	var p = _make_player()
	p.move_input = Vector2(1.0, 0.0)
	p.start_dodge()
	assert_false(p.can_dodge(), "Should not be able to dodge while DODGING")


func test_cannot_dodge_while_cooldown_remains():
	var p = _make_player()
	p.move_input = Vector2(1.0, 0.0)
	p.start_dodge()
	# Advance past dodge duration but not past cooldown
	for i in range(3):
		p.advance(_params.dodge_duration * 0.5)
	assert_eq(p.state, PlayerMovementState.WALKING, "Dodge should have ended")
	assert_gt(p.dodge_cooldown_remaining, 0.0, "Cooldown should still be active")
	assert_false(p.can_dodge())


func test_dodge_ends_after_duration():
	var p = _make_player()
	p.move_input = Vector2(1.0, 0.0)
	p.start_dodge()
	# Advance just past the dodge duration
	p.advance(_params.dodge_duration + 0.001)
	assert_eq(p.state, PlayerMovementState.WALKING)


func test_can_dodge_again_after_cooldown():
	var p = _make_player()
	p.move_input = Vector2(1.0, 0.0)
	p.start_dodge()
	# Advance past full cooldown
	p.advance(_params.dodge_cooldown + 0.01)
	assert_true(p.can_dodge())


func test_cooldown_ticks_down_during_dodge():
	var p = _make_player()
	p.move_input = Vector2(1.0, 0.0)
	p.start_dodge()
	var cd_before = p.dodge_cooldown_remaining
	p.advance(0.05)
	assert_lt(p.dodge_cooldown_remaining, cd_before,
		"Cooldown should tick down during DODGING state")


func test_dodge_emits_event():
	var p = _make_player()
	p.move_input = Vector2(1.0, 0.0)
	watch_signals(EventBus)
	p.start_dodge()
	assert_signal_emitted(EventBus, "player_dodge_started")


func test_dodge_respects_walls():
	# Requires the arena to be present so the wall is actually there
	var arena = preload("res://shared/world/arena.tscn").instantiate()
	add_child_autofree(arena)
	var p = _make_player()
	p.position = Vector2(470.0, 160.0)  # near right wall
	p.move_input = Vector2(1.0, 0.0)
	p.start_dodge()
	# Dodge a full duration of motion
	for i in range(10):
		p.advance(_params.dodge_duration / 10.0)
	assert_lt(p.position.x, 480.0, "Dodge must not phase through walls")
