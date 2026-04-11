class_name Snapshot

var tick: int = 0
# entity_id -> { entity_id, position, flags, last_input_seq, velocity,
#                aim_direction, state, dodge_time_remaining }
var entities: Dictionary = {}


# Returns an array of entity dicts that changed between baseline and current.
# Removed entities appear with the REMOVED flag.
static func diff(baseline: Snapshot, current: Snapshot) -> Array:
	var changes: Array = []

	# Check for changed or new entities
	for eid in current.entities:
		if not baseline.entities.has(eid):
			changes.append(current.entities[eid].duplicate())
		else:
			var base_ent = baseline.entities[eid]
			var curr_ent = current.entities[eid]
			var changed = false
			if not base_ent["position"].is_equal_approx(curr_ent["position"]):
				changed = true
			elif base_ent["flags"] != curr_ent["flags"]:
				changed = true
			elif base_ent.get("last_input_seq", 0) != curr_ent.get("last_input_seq", 0):
				changed = true
			elif not base_ent.get("velocity", Vector2.ZERO).is_equal_approx(curr_ent.get("velocity", Vector2.ZERO)):
				changed = true
			elif not base_ent.get("aim_direction", Vector2.RIGHT).is_equal_approx(curr_ent.get("aim_direction", Vector2.RIGHT)):
				changed = true
			elif base_ent.get("state", 0) != curr_ent.get("state", 0):
				changed = true
			elif abs(base_ent.get("dodge_time_remaining", 0.0) - curr_ent.get("dodge_time_remaining", 0.0)) > 0.001:
				changed = true
			elif base_ent.get("collision_count", 0) != curr_ent.get("collision_count", 0):
				changed = true
			if changed:
				changes.append(curr_ent.duplicate())

	# Check for removed entities
	for eid in baseline.entities:
		if not current.entities.has(eid):
			changes.append({
				"entity_id": eid,
				"position": Vector2.ZERO,
				"flags": MessageTypes.EntityFlags.REMOVED,
				"last_input_seq": 0,
				"velocity": Vector2.ZERO,
				"aim_direction": Vector2.RIGHT,
				"state": 0,
				"dodge_time_remaining": 0.0,
				"collision_count": 0,
				"last_collision_normal": Vector2.ZERO,
			})

	return changes


# Applies a delta (array of entity dicts) to this snapshot in-place.
func apply_delta(new_tick: int, delta_entities: Array) -> void:
	tick = new_tick
	for ent in delta_entities:
		var eid: int = ent["entity_id"]
		if ent["flags"] & MessageTypes.EntityFlags.REMOVED:
			entities.erase(eid)
		else:
			entities[eid] = ent.duplicate()


# Returns all entities as a flat array (for NetMessage encoding).
func to_entity_array() -> Array:
	return entities.values()


# Returns an independent deep copy of this snapshot.
func duplicate_snapshot() -> Snapshot:
	var copy = Snapshot.new()
	copy.tick = tick
	for eid in entities:
		copy.entities[eid] = entities[eid].duplicate()
	return copy
