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
	buf.encode_u8(21, 1 if msg.get("dodge_pressed", false) else 0)
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
		"dodge_pressed": bytes.decode_u8(21) != 0,
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

static func _encode_snapshot(msg: Dictionary) -> PackedByteArray:
	var entities: Array = msg["entities"]
	var header_size = MessageTypes.Layout.SNAPSHOT_HEADER_SIZE
	var entity_size = MessageTypes.Layout.ENTITY_SIZE
	var buf = PackedByteArray()
	buf.resize(header_size + entities.size() * entity_size)
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
	return buf


static func _decode_snapshot(bytes: PackedByteArray, type: int) -> Variant:
	var header_size = MessageTypes.Layout.SNAPSHOT_HEADER_SIZE
	var entity_size = MessageTypes.Layout.ENTITY_SIZE
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
	return {
		"type": type,
		"tick": bytes.decode_u32(1),
		"entities": entities,
	}
