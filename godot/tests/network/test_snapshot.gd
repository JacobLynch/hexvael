extends GutTest

var Snapshot = preload("res://simulation/network/snapshot.gd")


func _make_entity(id: int, x: float, y: float, flags: int = 0, last_input_seq: int = 0) -> Dictionary:
	return {"entity_id": id, "position": Vector2(x, y), "flags": flags, "last_input_seq": last_input_seq}


func test_capture_entities():
	var snap = Snapshot.new()
	snap.tick = 10
	snap.entities = {
		1: _make_entity(1, 100.0, 200.0),
		2: _make_entity(2, 300.0, 400.0),
	}
	assert_eq(snap.tick, 10)
	assert_eq(snap.entities.size(), 2)
	assert_eq(snap.entities[1]["position"], Vector2(100.0, 200.0))


func test_diff_detects_moved_entity():
	var baseline = Snapshot.new()
	baseline.tick = 10
	baseline.entities = {
		1: _make_entity(1, 100.0, 200.0),
		2: _make_entity(2, 300.0, 400.0),
	}
	var current = Snapshot.new()
	current.tick = 11
	current.entities = {
		1: _make_entity(1, 105.0, 200.0, MessageTypes.EntityFlags.MOVING),
		2: _make_entity(2, 300.0, 400.0),
	}
	var delta = Snapshot.diff(baseline, current)
	assert_eq(delta.size(), 1, "Only entity 1 moved")
	assert_eq(delta[0]["entity_id"], 1)
	assert_almost_eq(delta[0]["position"].x, 105.0, 0.01)


func test_diff_detects_new_entity():
	var baseline = Snapshot.new()
	baseline.tick = 10
	baseline.entities = {
		1: _make_entity(1, 100.0, 200.0),
	}
	var current = Snapshot.new()
	current.tick = 11
	current.entities = {
		1: _make_entity(1, 100.0, 200.0),
		2: _make_entity(2, 300.0, 400.0),
	}
	var delta = Snapshot.diff(baseline, current)
	assert_eq(delta.size(), 1, "Entity 2 is new")
	assert_eq(delta[0]["entity_id"], 2)


func test_diff_detects_removed_entity():
	var baseline = Snapshot.new()
	baseline.tick = 10
	baseline.entities = {
		1: _make_entity(1, 100.0, 200.0),
		2: _make_entity(2, 300.0, 400.0),
	}
	var current = Snapshot.new()
	current.tick = 11
	current.entities = {
		1: _make_entity(1, 100.0, 200.0),
	}
	var delta = Snapshot.diff(baseline, current)
	assert_eq(delta.size(), 1, "Entity 2 removed")
	assert_eq(delta[0]["entity_id"], 2)
	assert_eq(delta[0]["flags"], MessageTypes.EntityFlags.REMOVED)


func test_diff_empty_when_no_changes():
	var snap = Snapshot.new()
	snap.tick = 10
	snap.entities = {
		1: _make_entity(1, 100.0, 200.0),
	}
	var same = Snapshot.new()
	same.tick = 11
	same.entities = {
		1: _make_entity(1, 100.0, 200.0),
	}
	var delta = Snapshot.diff(snap, same)
	assert_eq(delta.size(), 0)


func test_apply_delta_updates_position():
	var snap = Snapshot.new()
	snap.tick = 10
	snap.entities = {
		1: _make_entity(1, 100.0, 200.0),
	}
	var delta_entities = [_make_entity(1, 110.0, 210.0, MessageTypes.EntityFlags.MOVING)]
	snap.apply_delta(11, delta_entities)
	assert_eq(snap.tick, 11)
	assert_almost_eq(snap.entities[1]["position"].x, 110.0, 0.01)


func test_apply_delta_adds_new_entity():
	var snap = Snapshot.new()
	snap.tick = 10
	snap.entities = {}
	var delta_entities = [_make_entity(5, 50.0, 60.0)]
	snap.apply_delta(11, delta_entities)
	assert_eq(snap.entities.size(), 1)
	assert_true(snap.entities.has(5))


func test_apply_delta_removes_entity():
	var snap = Snapshot.new()
	snap.tick = 10
	snap.entities = {
		1: _make_entity(1, 100.0, 200.0),
	}
	var delta_entities = [{"entity_id": 1, "position": Vector2.ZERO, "flags": MessageTypes.EntityFlags.REMOVED, "last_input_seq": 0}]
	snap.apply_delta(11, delta_entities)
	assert_false(snap.entities.has(1))


func test_to_entity_array():
	var snap = Snapshot.new()
	snap.tick = 10
	snap.entities = {
		1: _make_entity(1, 100.0, 200.0),
		3: _make_entity(3, 300.0, 400.0),
	}
	var arr = snap.to_entity_array()
	assert_eq(arr.size(), 2)


func test_duplicate_creates_independent_copy():
	var snap = Snapshot.new()
	snap.tick = 10
	snap.entities = {
		1: _make_entity(1, 100.0, 200.0),
	}
	var copy = snap.duplicate_snapshot()
	copy.entities[1]["position"] = Vector2(999.0, 999.0)
	assert_almost_eq(snap.entities[1]["position"].x, 100.0, 0.01, "Original should be unchanged")
