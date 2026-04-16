extends GutTest

var NetMessage = preload("res://simulation/network/net_message.gd")
var Snapshot = preload("res://simulation/network/snapshot.gd")


func _make_enemy_data(id: int, x: float, y: float, state: int = 0,
		facing: Vector2 = Vector2.RIGHT, spawn_timer: float = 0.5) -> Dictionary:
	return {
		"entity_id": id, "position": Vector2(x, y), "state": state,
		"facing": facing, "spawn_timer": spawn_timer,
	}


func test_encode_decode_snapshot_with_enemies():
	var msg = {
		"type": MessageTypes.Binary.FULL_SNAPSHOT,
		"tick": 100,
		"entities": [
			{"entity_id": 1, "position": Vector2(100, 200), "flags": 0, "last_input_seq": 5},
		],
		"enemy_entities": [
			_make_enemy_data(10001, 50.0, 75.0, 0, Vector2(0.707, 0.707), 0.4),
			_make_enemy_data(10002, 300.0, 200.0, 2, Vector2(-1.0, 0.0), 0.0),
		],
	}
	var bytes = NetMessage.encode(msg)
	var decoded = NetMessage.decode_binary(bytes)

	assert_eq(decoded["type"], MessageTypes.Binary.FULL_SNAPSHOT)
	assert_eq(decoded["tick"], 100)
	assert_eq(decoded["entities"].size(), 1)
	assert_eq(decoded["enemy_entities"].size(), 2)

	var e0 = decoded["enemy_entities"][0]
	assert_eq(e0["entity_id"], 10001)
	assert_almost_eq(e0["position"].x, 50.0, 0.1)
	assert_almost_eq(e0["position"].y, 75.0, 0.1)
	assert_eq(e0["state"], 0)
	assert_almost_eq(e0["facing"].x, 0.707, 0.01)
	assert_almost_eq(e0["spawn_timer"], 0.4, 0.01)


func test_encode_decode_snapshot_no_enemies():
	var msg = {
		"type": MessageTypes.Binary.FULL_SNAPSHOT,
		"tick": 50,
		"entities": [],
		"enemy_entities": [],
	}
	var bytes = NetMessage.encode(msg)
	var decoded = NetMessage.decode_binary(bytes)
	assert_eq(decoded["enemy_entities"].size(), 0)


func test_encode_decode_enemy_died():
	var msg = {
		"type": MessageTypes.Binary.ENEMY_DIED,
		"target_entity_id": 10005,
		"position": Vector2(123.5, 456.75),
		"killer_id": 2,
	}
	var bytes = NetMessage.encode(msg)
	assert_eq(bytes.size(), MessageTypes.Layout.ENEMY_DIED_SIZE)

	var decoded = NetMessage.decode_binary(bytes)
	assert_eq(decoded["type"], MessageTypes.Binary.ENEMY_DIED)
	assert_eq(decoded["target_entity_id"], 10005)
	assert_almost_eq(decoded["position"].x, 123.5, 0.01)
	assert_almost_eq(decoded["position"].y, 456.75, 0.01)
	assert_eq(decoded["killer_id"], 2)


func test_encode_decode_enemy_hit_full_payload():
	var event = {
		"target_entity_id": 10042,
		"position": Vector2(250.0, 125.5),
		"damage": 25,
		"remaining_health": 75,
		"max_health": 100,
		"source_entity_id": 3,
		"element": "frost",
		"chain_depth": 2,
		"projectile_id": 9000,
	}
	var bytes = NetMessage.encode_enemy_hit(event)
	assert_eq(bytes.size(), MessageTypes.Layout.ENEMY_HIT_SIZE)

	var decoded = NetMessage.decode_enemy_hit(bytes)
	assert_eq(decoded["target_entity_id"], 10042)
	assert_almost_eq(decoded["position"].x, 250.0, 0.01)
	assert_eq(decoded["damage"], 25)
	assert_eq(decoded["remaining_health"], 75)
	assert_eq(decoded["max_health"], 100)
	assert_eq(decoded["source_entity_id"], 3)
	assert_eq(decoded["element"], "frost")
	assert_eq(decoded["chain_depth"], 2)
	assert_eq(decoded["projectile_id"], 9000)
	assert_false(decoded.has("entity_id"), "Alias key entity_id must not be present")


func test_encode_decode_player_hit_full_payload():
	var event = {
		"target_entity_id": 1,
		"position": Vector2(800.0, 400.0),
		"damage": 10,
		"remaining_health": 90,
		"max_health": 100,
		"source_entity_id": 2,
		"element": "fire",
		"chain_depth": 0,
		"projectile_id": 4242,
	}
	var bytes = NetMessage.encode_player_hit(event)
	var decoded = NetMessage.decode_player_hit(bytes)
	assert_eq(decoded["target_entity_id"], 1)
	assert_eq(decoded["source_entity_id"], 2)
	assert_eq(decoded["element"], "fire")
	assert_eq(decoded["chain_depth"], 0)
	assert_eq(decoded["projectile_id"], 4242)


func test_enemy_hit_negative_sentinels_round_trip():
	# -1 source/projectile (damage with no identifiable origin) must survive
	# wire round-trip unchanged.
	var event = {
		"target_entity_id": 10001,
		"position": Vector2(0, 0),
		"damage": 5,
		"remaining_health": 45,
		"max_health": 50,
		"source_entity_id": -1,
		"element": "physical",
		"chain_depth": 0,
		"projectile_id": -1,
	}
	var bytes = NetMessage.encode_enemy_hit(event)
	var decoded = NetMessage.decode_enemy_hit(bytes)
	assert_eq(decoded["source_entity_id"], -1)
	assert_eq(decoded["projectile_id"], -1)


func test_enemy_hit_unknown_element_round_trips_as_unknown():
	var event = {
		"target_entity_id": 10001,
		"position": Vector2(0, 0),
		"damage": 1,
		"remaining_health": 49,
		"max_health": 50,
		"source_entity_id": 1,
		"element": "not_a_real_element",
		"chain_depth": 0,
		"projectile_id": 1,
	}
	var bytes = NetMessage.encode_enemy_hit(event)
	var decoded = NetMessage.decode_enemy_hit(bytes)
	assert_eq(decoded["element"], "unknown")


func test_snapshot_diff_with_enemies():
	var baseline = Snapshot.new()
	baseline.tick = 10
	baseline.enemy_entities = {
		10001: _make_enemy_data(10001, 50.0, 50.0, 2),
		10002: _make_enemy_data(10002, 100.0, 100.0, 1),
	}
	var current = Snapshot.new()
	current.tick = 11
	current.enemy_entities = {
		10001: _make_enemy_data(10001, 55.0, 50.0, 2),  # moved
		10002: _make_enemy_data(10002, 100.0, 100.0, 1),  # unchanged
		10003: _make_enemy_data(10003, 200.0, 200.0, 0),  # new
	}
	var delta = Snapshot.diff_enemies(baseline, current)
	assert_eq(delta.size(), 2, "Should have moved + new enemy")


func test_snapshot_diff_enemy_removed():
	var baseline = Snapshot.new()
	baseline.tick = 10
	baseline.enemy_entities = {
		10001: _make_enemy_data(10001, 50.0, 50.0),
	}
	var current = Snapshot.new()
	current.tick = 11
	current.enemy_entities = {}
	var delta = Snapshot.diff_enemies(baseline, current)
	assert_eq(delta.size(), 1)
	assert_eq(delta[0]["entity_id"], 10001)
	assert_eq(delta[0]["state"], MessageTypes.EnemyFlags.REMOVED)


func test_snapshot_apply_delta_enemies():
	var snap = Snapshot.new()
	snap.tick = 10
	snap.enemy_entities = {
		10001: _make_enemy_data(10001, 50.0, 50.0, 2),
	}
	var delta = [
		_make_enemy_data(10001, 55.0, 50.0, 2),  # updated
		_make_enemy_data(10002, 100.0, 100.0, 0),  # new
	]
	snap.apply_enemy_delta(11, delta)
	assert_eq(snap.tick, 11)
	assert_eq(snap.enemy_entities.size(), 2)
	assert_almost_eq(snap.enemy_entities[10001]["position"].x, 55.0, 0.1)


func test_snapshot_duplicate_includes_enemies():
	var snap = Snapshot.new()
	snap.tick = 10
	snap.enemy_entities = {10001: _make_enemy_data(10001, 50.0, 50.0)}
	var copy = snap.duplicate_snapshot()
	copy.enemy_entities[10001]["position"] = Vector2(999, 999)
	assert_almost_eq(snap.enemy_entities[10001]["position"].x, 50.0, 0.1,
		"Original should be unchanged")
