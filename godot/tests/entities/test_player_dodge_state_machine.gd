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
	# Verify payload shape
	var params_list = get_signal_parameters(EventBus, "player_dodge_started", 0)
	assert_not_null(params_list)
	var event = params_list[0]
	assert_eq(event["entity_id"], p.player_id)
	assert_true(event.has("position"))
	assert_true(event.has("direction"))
	assert_eq(event["direction"], Vector2(1.0, 0.0))


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


func test_dodge_impulse_overrides_walking_velocity():
	# Impulse semantics: dodge hard-sets velocity to dodge_speed immediately,
	# regardless of prior walking velocity. Prevents midpoint integration from
	# blending old velocity with new dodge velocity on the first tick.
	var p = _make_player()
	p.move_input = Vector2(1.0, 0.0)
	p.velocity = Vector2(200.0, 0.0)  # simulate prior walking velocity
	p.start_dodge()
	# After start_dodge, velocity should be exactly dodge_speed in dodge direction
	assert_almost_eq(p.velocity.x, _params.dodge_speed, 0.01,
		"start_dodge must hard-set velocity.x to dodge_speed")
	assert_almost_eq(p.velocity.y, 0.0, 0.01)


func test_dodge_impulse_overrides_opposite_walking_velocity():
	# Even when walking in the opposite direction, the dodge must instantly
	# commit to the dodge direction — no blending.
	var p = _make_player()
	p.move_input = Vector2(1.0, 0.0)
	p.velocity = Vector2(-200.0, 0.0)  # walking left
	p.start_dodge()  # dodging right
	assert_almost_eq(p.velocity.x, _params.dodge_speed, 0.01,
		"Dodge velocity must instantly override opposite walking velocity")


func test_dodge_first_tick_travels_full_distance():
	# Regression guard for the midpoint-integration-blends-prior-velocity bug.
	# A dodge starting from any prior velocity should travel the same distance
	# on its first tick as a dodge from standstill.
	var arena = preload("res://shared/world/arena.tscn").instantiate()
	add_child_autofree(arena)

	var p_rest = _make_player()
	p_rest.position = Vector2(100.0, 160.0)
	p_rest.velocity = Vector2.ZERO
	p_rest.move_input = Vector2(1.0, 0.0)
	p_rest.start_dodge()
	p_rest.advance(0.05)
	var dist_rest = p_rest.position.x - 100.0

	var p_move = _make_player()
	p_move.position = Vector2(100.0, 160.0)
	p_move.velocity = Vector2(200.0, 0.0)
	p_move.move_input = Vector2(1.0, 0.0)
	p_move.start_dodge()
	p_move.advance(0.05)
	var dist_move = p_move.position.x - 100.0

	assert_almost_eq(dist_move, dist_rest, 0.1,
		"Dodge first-tick distance must match regardless of prior velocity")


func test_dodge_ended_emits_event_with_position():
	var p = _make_player()
	p.move_input = Vector2(1.0, 0.0)
	p.start_dodge()
	watch_signals(EventBus)  # after start_dodge, so we don't count player_dodge_started
	# Advance past the dodge duration — should trigger dodge_ended
	p.advance(_params.dodge_duration + 0.001)
	assert_signal_emitted(EventBus, "player_dodge_ended")
	# Verify payload shape — entity_id and position must be present
	var params_list = get_signal_parameters(EventBus, "player_dodge_ended", 0)
	assert_not_null(params_list, "player_dodge_ended should have been emitted")
	var event = params_list[0]
	assert_eq(event["entity_id"], p.player_id)
	assert_true(event.has("position"), "player_dodge_ended payload must include position")
