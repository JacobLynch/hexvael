class_name Snapshot

var tick: int = 0
# entity_id -> { entity_id, position, flags, last_input_seq, velocity,
#                aim_direction, state, dodge_time_remaining }
var entities: Dictionary = {}
# entity_id -> { "entity_id": int, "position": Vector2, "state": int, "facing": Vector2, "spawn_timer": float }
var enemy_entities: Dictionary = {}


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


# Returns an array of enemy dicts that changed between baseline and current.
# Removed enemies appear with state = MessageTypes.EnemyFlags.REMOVED.
static func diff_enemies(baseline: Snapshot, current: Snapshot) -> Array:
	var changes: Array = []

	# Check for changed or new enemies
	for eid in current.enemy_entities:
		if not baseline.enemy_entities.has(eid):
			changes.append(current.enemy_entities[eid].duplicate())
		else:
			var base_ent = baseline.enemy_entities[eid]
			var curr_ent = current.enemy_entities[eid]
			var pos_changed = not base_ent["position"].is_equal_approx(curr_ent["position"])
			var state_changed = base_ent.get("state", 0) != curr_ent.get("state", 0)
			var facing_changed = not base_ent.get("facing", Vector2.RIGHT).is_equal_approx(curr_ent.get("facing", Vector2.RIGHT))
			var timer_changed = not is_equal_approx(base_ent.get("spawn_timer", 0.0), curr_ent.get("spawn_timer", 0.0))
			if pos_changed or state_changed or facing_changed or timer_changed:
				changes.append(curr_ent.duplicate())

	# Check for removed enemies
	for eid in baseline.enemy_entities:
		if not current.enemy_entities.has(eid):
			changes.append({
				"entity_id": eid,
				"position": Vector2.ZERO,
				"state": MessageTypes.EnemyFlags.REMOVED,
				"facing": Vector2.RIGHT,
				"spawn_timer": 0.0,
			})

	return changes


# Applies a delta (array of enemy dicts) to this snapshot's enemy_entities in-place.
func apply_enemy_delta(new_tick: int, delta_entities: Array) -> void:
	tick = new_tick
	for ent in delta_entities:
		var eid: int = ent["entity_id"]
		if ent.get("state", 0) == MessageTypes.EnemyFlags.REMOVED:
			enemy_entities.erase(eid)
		else:
			enemy_entities[eid] = ent.duplicate()


# Returns all enemy entities as a flat array (for NetMessage encoding).
func to_enemy_entity_array() -> Array:
	return enemy_entities.values()


# Returns an independent deep copy of this snapshot.
func duplicate_snapshot() -> Snapshot:
	var copy = Snapshot.new()
	copy.tick = tick
	for eid in entities:
		copy.entities[eid] = entities[eid].duplicate()
	for eid in enemy_entities:
		copy.enemy_entities[eid] = enemy_entities[eid].duplicate()
	return copy


## Resets this snapshot for reuse, avoiding allocation of a new Snapshot object.
func reset() -> void:
	tick = 0
	entities.clear()
	enemy_entities.clear()


## Copies data from another snapshot into this one (in-place update).
## Used for object pooling — avoids allocating a new Snapshot.
func copy_from(other: Snapshot) -> void:
	tick = other.tick
	entities.clear()
	for eid in other.entities:
		entities[eid] = other.entities[eid].duplicate()
	enemy_entities.clear()
	for eid in other.enemy_entities:
		enemy_entities[eid] = other.enemy_entities[eid].duplicate()
