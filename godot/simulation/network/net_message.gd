class_name NetMessage


# --- Binary encoding ---

static func encode(msg: Dictionary) -> PackedByteArray:
	var type: int = msg["type"]
	match type:
		MessageTypes.Binary.PLAYER_INPUT:
			return _encode_player_input(msg)
		MessageTypes.Binary.SNAPSHOT_ACK:
			return _encode_snapshot_ack(msg)
		MessageTypes.Binary.FULL_SNAPSHOT, MessageTypes.Binary.DELTA_SNAPSHOT:
			return _encode_snapshot(msg)
		MessageTypes.Binary.ENEMY_DIED:
			return _encode_enemy_died(msg)
	push_error("NetMessage.encode: unknown binary type %d" % type)
	return PackedByteArray()


static func decode_binary(bytes: PackedByteArray) -> Variant:
	if bytes.size() < 1:
		return null
	var type: int = bytes.decode_u8(0)
	match type:
		MessageTypes.Binary.PLAYER_INPUT:
			return _decode_player_input(bytes)
		MessageTypes.Binary.SNAPSHOT_ACK:
			return _decode_snapshot_ack(bytes)
		MessageTypes.Binary.FULL_SNAPSHOT, MessageTypes.Binary.DELTA_SNAPSHOT:
			return _decode_snapshot(bytes, type)
		MessageTypes.Binary.ENEMY_DIED:
			return _decode_enemy_died(bytes)
	return null


# --- JSON encoding ---

static func encode_json(msg: Dictionary) -> String:
	return JSON.stringify(msg)


static func decode_json(text: String) -> Variant:
	var result = JSON.parse_string(text)
	if result == null:
		push_error("NetMessage.decode_json: failed to parse: %s" % text)
	return result


# --- Private: Player Input ---

static func _encode_player_input(msg: Dictionary) -> PackedByteArray:
	var buf = PackedByteArray()
	buf.resize(MessageTypes.Layout.INPUT_SIZE)
	var move_dir: Vector2 = msg["move_direction"]
	var aim_dir: Vector2 = msg["aim_direction"]
	buf.encode_u8(0, MessageTypes.Binary.PLAYER_INPUT)
	buf.encode_u32(1, msg["tick"])
	buf.encode_float(5, move_dir.x)
	buf.encode_float(9, move_dir.y)
	buf.encode_float(13, aim_dir.x)
	buf.encode_float(17, aim_dir.y)
	buf.encode_u8(21, msg.get("action_flags", 0))
	buf.encode_u32(22, msg["input_seq"])
	return buf


static func _decode_player_input(bytes: PackedByteArray) -> Variant:
	if bytes.size() < MessageTypes.Layout.INPUT_SIZE:
		return null
	return {
		"type": MessageTypes.Binary.PLAYER_INPUT,
		"tick": bytes.decode_u32(1),
		"move_direction": Vector2(bytes.decode_float(5), bytes.decode_float(9)),
		"aim_direction": Vector2(bytes.decode_float(13), bytes.decode_float(17)),
		"action_flags": bytes.decode_u8(21),
		"input_seq": bytes.decode_u32(22),
	}


# --- Private: Snapshot ACK ---

static func _encode_snapshot_ack(msg: Dictionary) -> PackedByteArray:
	var buf = PackedByteArray()
	buf.resize(MessageTypes.Layout.ACK_SIZE)
	buf.encode_u8(0, MessageTypes.Binary.SNAPSHOT_ACK)
	buf.encode_u32(1, msg["tick"])
	return buf


static func _decode_snapshot_ack(bytes: PackedByteArray) -> Variant:
	if bytes.size() < MessageTypes.Layout.ACK_SIZE:
		return null
	return {
		"type": MessageTypes.Binary.SNAPSHOT_ACK,
		"tick": bytes.decode_u32(1),
	}


# --- Private: Snapshots (full + delta use same format) ---
# Format: [msg_type: u8][tick: u32][player_count: u16][...player entities...][enemy_count: u16][...enemy entities...]

static func _encode_snapshot(msg: Dictionary) -> PackedByteArray:
	var entities: Array = msg.get("entities", [])
	var enemy_entities: Array = msg.get("enemy_entities", [])
	var header_size = MessageTypes.Layout.SNAPSHOT_HEADER_SIZE
	var entity_size = MessageTypes.Layout.ENTITY_SIZE
	var enemy_entity_size = MessageTypes.Layout.ENEMY_ENTITY_SIZE
	# Total: header + player section + enemy_count u16 + enemy section
	var total_size = header_size + entities.size() * entity_size + 2 + enemy_entities.size() * enemy_entity_size
	var buf = PackedByteArray()
	buf.resize(total_size)
	buf.encode_u8(0, msg["type"])
	buf.encode_u32(1, msg["tick"])
	buf.encode_u16(5, entities.size())
	for i in range(entities.size()):
		var offset = header_size + i * entity_size
		var ent = entities[i]
		var pos: Vector2 = ent["position"]
		var vel: Vector2 = ent.get("velocity", Vector2.ZERO)
		var aim: Vector2 = ent.get("aim_direction", Vector2.RIGHT)
		buf.encode_u16(offset, ent["entity_id"])
		buf.encode_float(offset + 2, pos.x)
		buf.encode_float(offset + 6, pos.y)
		buf.encode_u8(offset + 10, ent["flags"])
		buf.encode_u32(offset + 11, ent.get("last_input_seq", 0))
		buf.encode_float(offset + 15, vel.x)
		buf.encode_float(offset + 19, vel.y)
		buf.encode_float(offset + 23, aim.x)
		buf.encode_float(offset + 27, aim.y)
		buf.encode_u8(offset + 31, ent.get("state", 0))
		buf.encode_float(offset + 32, ent.get("dodge_time_remaining", 0.0))
		buf.encode_u8(offset + 36, ent.get("collision_count", 0))
		var cnorm: Vector2 = ent.get("last_collision_normal", Vector2.ZERO)
		buf.encode_float(offset + 37, cnorm.x)
		buf.encode_float(offset + 41, cnorm.y)
	# Enemy section starts after player section
	var enemy_section_start = header_size + entities.size() * entity_size
	buf.encode_u16(enemy_section_start, enemy_entities.size())
	for i in range(enemy_entities.size()):
		var offset = enemy_section_start + 2 + i * enemy_entity_size
		var ent = enemy_entities[i]
		var pos: Vector2 = ent["position"]
		var facing: Vector2 = ent.get("facing", Vector2.RIGHT)
		buf.encode_u16(offset, ent["entity_id"])
		buf.encode_float(offset + 2, pos.x)
		buf.encode_float(offset + 6, pos.y)
		buf.encode_u8(offset + 10, ent.get("state", 0))
		buf.encode_half(offset + 11, facing.x)
		buf.encode_half(offset + 13, facing.y)
		buf.encode_half(offset + 15, ent.get("spawn_timer", 0.0))
	return buf


static func _decode_snapshot(bytes: PackedByteArray, type: int) -> Variant:
	var header_size = MessageTypes.Layout.SNAPSHOT_HEADER_SIZE
	var entity_size = MessageTypes.Layout.ENTITY_SIZE
	var enemy_entity_size = MessageTypes.Layout.ENEMY_ENTITY_SIZE
	if bytes.size() < header_size:
		return null
	var entity_count = bytes.decode_u16(5)
	if bytes.size() < header_size + entity_count * entity_size:
		return null
	var entities: Array = []
	for i in range(entity_count):
		var offset = header_size + i * entity_size
		entities.append({
			"entity_id": bytes.decode_u16(offset),
			"position": Vector2(bytes.decode_float(offset + 2), bytes.decode_float(offset + 6)),
			"flags": bytes.decode_u8(offset + 10),
			"last_input_seq": bytes.decode_u32(offset + 11),
			"velocity": Vector2(bytes.decode_float(offset + 15), bytes.decode_float(offset + 19)),
			"aim_direction": Vector2(bytes.decode_float(offset + 23), bytes.decode_float(offset + 27)),
			"state": bytes.decode_u8(offset + 31),
			"dodge_time_remaining": bytes.decode_float(offset + 32),
			"collision_count": bytes.decode_u8(offset + 36),
			"last_collision_normal": Vector2(bytes.decode_float(offset + 37), bytes.decode_float(offset + 41)),
		})
	# Parse enemy section if present (backward-compatible: old format may not have it)
	var enemy_entities: Array = []
	var enemy_section_start = header_size + entity_count * entity_size
	if bytes.size() >= enemy_section_start + 2:
		var enemy_count = bytes.decode_u16(enemy_section_start)
		if bytes.size() >= enemy_section_start + 2 + enemy_count * enemy_entity_size:
			for i in range(enemy_count):
				var offset = enemy_section_start + 2 + i * enemy_entity_size
				enemy_entities.append({
					"entity_id": bytes.decode_u16(offset),
					"position": Vector2(bytes.decode_float(offset + 2), bytes.decode_float(offset + 6)),
					"state": bytes.decode_u8(offset + 10),
					"facing": Vector2(bytes.decode_half(offset + 11), bytes.decode_half(offset + 13)),
					"spawn_timer": bytes.decode_half(offset + 15),
				})
	return {
		"type": type,
		"tick": bytes.decode_u32(1),
		"entities": entities,
		"enemy_entities": enemy_entities,
	}


# --- Private: Enemy Died ---
# Format: [type: u8][entity_id: u16][x: f32][y: f32][killer_id: u16]

static func _encode_enemy_died(msg: Dictionary) -> PackedByteArray:
	var buf = PackedByteArray()
	buf.resize(MessageTypes.Layout.ENEMY_DIED_SIZE)
	var pos: Vector2 = msg["position"]
	buf.encode_u8(0, MessageTypes.Binary.ENEMY_DIED)
	buf.encode_u16(1, msg["entity_id"])
	buf.encode_float(3, pos.x)
	buf.encode_float(7, pos.y)
	buf.encode_u16(11, msg["killer_id"])
	return buf


static func _decode_enemy_died(bytes: PackedByteArray) -> Variant:
	if bytes.size() < MessageTypes.Layout.ENEMY_DIED_SIZE:
		return null
	return {
		"type": MessageTypes.Binary.ENEMY_DIED,
		"entity_id": bytes.decode_u16(1),
		"position": Vector2(bytes.decode_float(3), bytes.decode_float(7)),
		"killer_id": bytes.decode_u16(11),
	}
