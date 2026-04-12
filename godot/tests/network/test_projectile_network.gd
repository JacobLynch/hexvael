extends GutTest

var NetMessage = preload("res://simulation/network/net_message.gd")


# Round-trip tests for PROJECTILE_SPAWNED and PROJECTILE_DESPAWNED binary messages.

func test_projectile_spawned_round_trip():
	var event = {
		"projectile_id": 1234,
		"type_id": 0,
		"owner_player_id": 42,
		"origin": Vector2(100.5, 200.25),
		"direction": Vector2(0.6, 0.8),
		"input_seq": 999,
	}
	var bytes: PackedByteArray = NetMessage.encode_projectile_spawned(event)
	assert_eq(bytes.size(), MessageTypes.Layout.PROJECTILE_SPAWNED_SIZE)
	var decoded: Dictionary = NetMessage.decode_projectile_spawned(bytes)
	assert_eq(decoded["projectile_id"], 1234)
	assert_eq(decoded["type_id"], 0)
	assert_eq(decoded["owner_player_id"], 42)
	assert_almost_eq(decoded["origin"].x, 100.5, 0.01)
	assert_almost_eq(decoded["origin"].y, 200.25, 0.01)
	assert_almost_eq(decoded["direction"].x, 0.6, 0.01)
	assert_almost_eq(decoded["direction"].y, 0.8, 0.01)
	assert_eq(decoded["input_seq"], 999)


func test_projectile_despawned_round_trip():
	var event = {
		"projectile_id": 1234,
		"reason": 2,  # ENEMY
		"position": Vector2(500.75, 300.5),
	}
	var bytes: PackedByteArray = NetMessage.encode_projectile_despawned(event)
	assert_eq(bytes.size(), MessageTypes.Layout.PROJECTILE_DESPAWNED_SIZE)
	var decoded = NetMessage.decode_projectile_despawned(bytes)
	assert_eq(decoded["projectile_id"], 1234)
	assert_eq(decoded["reason"], 2)
	assert_almost_eq(decoded["position"].x, 500.75, 0.01)
	assert_almost_eq(decoded["position"].y, 300.5, 0.01)
