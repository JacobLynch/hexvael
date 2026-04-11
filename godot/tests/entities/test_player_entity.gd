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


func test_to_snapshot_data():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(3, Vector2(50.0, 75.0))
	# Set velocity directly to simulate a moving player (apply_input alone doesn't set velocity)
	player.velocity = Vector2(200.0, 0.0)
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
