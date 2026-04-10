extends GutTest

var NetMessage = preload("res://simulation/network/net_message.gd")


func test_player_input_round_trip():
	var msg = {
		"type": MessageTypes.Binary.PLAYER_INPUT,
		"tick": 42,
		"move_direction": Vector2(0.6, -0.8),
		"aim_direction": Vector2(1.0, 0.0),
		"input_seq": 1234,
	}
	var bytes = NetMessage.encode(msg)
	assert_eq(bytes.size(), MessageTypes.Layout.INPUT_SIZE)
	var decoded = NetMessage.decode_binary(bytes)
	assert_eq(decoded["tick"], 42)
	assert_almost_eq(decoded["move_direction"].x, 0.6, 0.001)
	assert_almost_eq(decoded["move_direction"].y, -0.8, 0.001)
	assert_almost_eq(decoded["aim_direction"].x, 1.0, 0.001)
	assert_almost_eq(decoded["aim_direction"].y, 0.0, 0.001)
	assert_eq(decoded["dodge_pressed"], false)
	assert_eq(decoded["input_seq"], 1234)


func test_player_input_round_trip_with_dodge():
	var msg = {
		"type": MessageTypes.Binary.PLAYER_INPUT,
		"tick": 42,
		"move_direction": Vector2(0.6, -0.8),
		"aim_direction": Vector2(1.0, 0.0),
		"dodge_pressed": true,
		"input_seq": 1234,
	}
	var bytes = NetMessage.encode(msg)
	assert_eq(bytes.size(), MessageTypes.Layout.INPUT_SIZE)
	var decoded = NetMessage.decode_binary(bytes)
	assert_eq(decoded["dodge_pressed"], true)
	assert_eq(decoded["input_seq"], 1234)


func test_snapshot_round_trip_with_dodge_state():
	var msg = {
		"type": MessageTypes.Binary.FULL_SNAPSHOT,
		"tick": 100,
		"entities": [{
			"entity_id": 1,
			"position": Vector2(240.0, 160.0),
			"flags": MessageTypes.EntityFlags.MOVING | MessageTypes.EntityFlags.DODGING,
			"last_input_seq": 55,
			"velocity": Vector2(700.0, 0.0),
			"aim_direction": Vector2(1.0, 0.0),
			"state": 1,
			"dodge_time_remaining": 0.15,
		}],
	}
	var bytes = NetMessage.encode(msg)
	var decoded = NetMessage.decode_binary(bytes)
	var ent = decoded["entities"][0]
	assert_eq(ent["entity_id"], 1)
	assert_almost_eq(ent["velocity"].x, 700.0, 0.01)
	assert_eq(ent["state"], 1)
	assert_almost_eq(ent["dodge_time_remaining"], 0.15, 0.001)
	assert_eq(ent["flags"] & MessageTypes.EntityFlags.DODGING, MessageTypes.EntityFlags.DODGING)


func test_encode_decode_snapshot_ack():
	var msg = {
		"type": MessageTypes.Binary.SNAPSHOT_ACK,
		"tick": 1000,
	}
	var bytes = NetMessage.encode(msg)
	assert_eq(bytes.size(), MessageTypes.Layout.ACK_SIZE)

	var decoded = NetMessage.decode_binary(bytes)
	assert_eq(decoded["type"], MessageTypes.Binary.SNAPSHOT_ACK)
	assert_eq(decoded["tick"], 1000)


func test_encode_decode_full_snapshot():
	var entities = [
		{"entity_id": 1, "position": Vector2(100.5, 200.75), "flags": MessageTypes.EntityFlags.MOVING, "last_input_seq": 42},
		{"entity_id": 2, "position": Vector2(300.0, 400.0), "flags": MessageTypes.EntityFlags.NONE, "last_input_seq": 0},
	]
	var msg = {
		"type": MessageTypes.Binary.FULL_SNAPSHOT,
		"tick": 500,
		"entities": entities,
	}
	var bytes = NetMessage.encode(msg)
	var expected_size = MessageTypes.Layout.SNAPSHOT_HEADER_SIZE + (2 * MessageTypes.Layout.ENTITY_SIZE)
	assert_eq(bytes.size(), expected_size)

	var decoded = NetMessage.decode_binary(bytes)
	assert_eq(decoded["type"], MessageTypes.Binary.FULL_SNAPSHOT)
	assert_eq(decoded["tick"], 500)
	assert_eq(decoded["entities"].size(), 2)
	assert_eq(decoded["entities"][0]["entity_id"], 1)
	assert_almost_eq(decoded["entities"][0]["position"].x, 100.5, 0.01)
	assert_almost_eq(decoded["entities"][0]["position"].y, 200.75, 0.01)
	assert_eq(decoded["entities"][0]["flags"], MessageTypes.EntityFlags.MOVING)
	assert_eq(decoded["entities"][0]["last_input_seq"], 42)
	assert_eq(decoded["entities"][1]["last_input_seq"], 0)


func test_encode_decode_delta_snapshot():
	var entities = [
		{"entity_id": 1, "position": Vector2(105.0, 205.0), "flags": MessageTypes.EntityFlags.MOVING, "last_input_seq": 7},
	]
	var msg = {
		"type": MessageTypes.Binary.DELTA_SNAPSHOT,
		"tick": 501,
		"entities": entities,
	}
	var bytes = NetMessage.encode(msg)
	var decoded = NetMessage.decode_binary(bytes)
	assert_eq(decoded["type"], MessageTypes.Binary.DELTA_SNAPSHOT)
	assert_eq(decoded["tick"], 501)
	assert_eq(decoded["entities"].size(), 1)


func test_encode_decode_json_handshake():
	var msg = {
		"type": MessageTypes.JsonMsg.HANDSHAKE,
		"server_tick": 100,
		"player_id": 3,
		"world_seed": 12345,
	}
	var text = NetMessage.encode_json(msg)
	var decoded = NetMessage.decode_json(text)
	assert_eq(decoded["type"], MessageTypes.JsonMsg.HANDSHAKE)
	assert_eq(decoded["server_tick"], 100)
	assert_eq(decoded["player_id"], 3)
	assert_eq(decoded["world_seed"], 12345)


func test_encode_decode_json_player_joined():
	var msg = {
		"type": MessageTypes.JsonMsg.PLAYER_JOINED,
		"player_id": 5,
		"spawn_position": {"x": 240.0, "y": 160.0},
	}
	var text = NetMessage.encode_json(msg)
	var decoded = NetMessage.decode_json(text)
	assert_eq(decoded["type"], MessageTypes.JsonMsg.PLAYER_JOINED)
	assert_eq(decoded["player_id"], 5)
	assert_almost_eq(float(decoded["spawn_position"]["x"]), 240.0, 0.01)


func test_encode_decode_json_player_left():
	var msg = {
		"type": MessageTypes.JsonMsg.PLAYER_LEFT,
		"player_id": 5,
	}
	var text = NetMessage.encode_json(msg)
	var decoded = NetMessage.decode_json(text)
	assert_eq(decoded["type"], MessageTypes.JsonMsg.PLAYER_LEFT)
	assert_eq(decoded["player_id"], 5)


func test_decode_binary_rejects_malformed_data():
	var garbage = PackedByteArray([255, 0, 0])
	var decoded = NetMessage.decode_binary(garbage)
	assert_null(decoded, "Malformed binary should return null")


func test_decode_binary_rejects_truncated_input():
	# Valid type byte for PLAYER_INPUT but too short
	var truncated = PackedByteArray([MessageTypes.Binary.PLAYER_INPUT, 0, 0])
	var decoded = NetMessage.decode_binary(truncated)
	assert_null(decoded, "Truncated message should return null")


func test_empty_snapshot():
	var msg = {
		"type": MessageTypes.Binary.FULL_SNAPSHOT,
		"tick": 1,
		"entities": [],
	}
	var bytes = NetMessage.encode(msg)
	assert_eq(bytes.size(), MessageTypes.Layout.SNAPSHOT_HEADER_SIZE)

	var decoded = NetMessage.decode_binary(bytes)
	assert_eq(decoded["entities"].size(), 0)


func test_input_seq_supports_u32_range():
	var large_seq: int = 100000  # Well beyond u16 max of 65535
	var msg = {
		"type": MessageTypes.Binary.PLAYER_INPUT,
		"tick": 1,
		"move_direction": Vector2.ZERO,
		"aim_direction": Vector2.RIGHT,
		"input_seq": large_seq,
	}
	var bytes = NetMessage.encode(msg)
	var decoded = NetMessage.decode_binary(bytes)
	assert_eq(decoded["input_seq"], large_seq)


func test_last_input_seq_supports_u32_range():
	var large_seq: int = 100000
	var entities = [
		{"entity_id": 1, "position": Vector2.ZERO, "flags": 0, "last_input_seq": large_seq},
	]
	var msg = {
		"type": MessageTypes.Binary.FULL_SNAPSHOT,
		"tick": 1,
		"entities": entities,
	}
	var bytes = NetMessage.encode(msg)
	var decoded = NetMessage.decode_binary(bytes)
	assert_eq(decoded["entities"][0]["last_input_seq"], large_seq)
