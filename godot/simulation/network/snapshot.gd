class_name Snapshot

var tick: int = 0
# entity_id -> { "entity_id": int, "position": Vector2, "flags": int }
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
			if not base_ent["position"].is_equal_approx(curr_ent["position"]) or base_ent["flags"] != curr_ent["flags"] or base_ent.get("last_input_seq", 0) != curr_ent.get("last_input_seq", 0):
				changes.append(curr_ent.duplicate())

	# Check for removed entities
	for eid in baseline.entities:
		if not current.entities.has(eid):
			changes.append({
				"entity_id": eid,
				"position": Vector2.ZERO,
				"flags": MessageTypes.EntityFlags.REMOVED,
				"last_input_seq": 0,
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
