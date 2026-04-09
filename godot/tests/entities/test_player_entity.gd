extends GutTest

var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


func test_initial_state():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	assert_eq(player.player_id, -1, "Default player_id should be -1")
	assert_eq(player.velocity, Vector2.ZERO)


func test_initialize_sets_id_and_position():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(5, Vector2(100.0, 200.0))
	assert_eq(player.player_id, 5)
	assert_eq(player.position, Vector2(100.0, 200.0))


func test_apply_input_sets_velocity():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(1, Vector2.ZERO)
	player.apply_input(Vector2(1.0, 0.0))
	assert_eq(player.velocity, Vector2(player.SPEED, 0.0))


func test_apply_input_normalizes_diagonal():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(1, Vector2.ZERO)
	player.apply_input(Vector2(1.0, 1.0))
	var expected_speed = player.SPEED
	# Diagonal should be normalized, so magnitude equals SPEED
	assert_almost_eq(player.velocity.length(), expected_speed, 0.01)


func test_apply_zero_input_stops():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(1, Vector2.ZERO)
	player.apply_input(Vector2(1.0, 0.0))
	player.apply_input(Vector2.ZERO)
	assert_eq(player.velocity, Vector2.ZERO)


func test_to_snapshot_data():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(3, Vector2(50.0, 75.0))
	player.apply_input(Vector2(1.0, 0.0))
	var data = player.to_snapshot_data()
	assert_eq(data["entity_id"], 3)
	assert_eq(data["position"], Vector2(50.0, 75.0))
	assert_eq(data["flags"], MessageTypes.EntityFlags.MOVING)
	assert_true(data.has("last_input_seq"), "Snapshot data should include last_input_seq")
	assert_eq(data["last_input_seq"], 0, "Default last_input_seq should be 0")


func test_to_snapshot_data_not_moving():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(3, Vector2(50.0, 75.0))
	var data = player.to_snapshot_data()
	assert_eq(data["flags"], MessageTypes.EntityFlags.NONE)
	assert_eq(data["last_input_seq"], 0)


func test_to_snapshot_data_tracks_input_seq():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(3, Vector2(50.0, 75.0))
	player.last_processed_input_seq = 42
	var data = player.to_snapshot_data()
	assert_eq(data["last_input_seq"], 42)


func test_move_delta_moves_by_frame_delta():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(1, Vector2(100.0, 100.0))
	player.apply_input(Vector2(1.0, 0.0))
	player.move_delta(1.0 / 60.0)
	# At 200 speed, 1/60s frame = ~3.33 pixels
	var expected_x = 100.0 + (PlayerEntity.SPEED / 60.0)
	assert_almost_eq(player.position.x, expected_x, 0.5)
	assert_almost_eq(player.position.y, 100.0, 0.1)
