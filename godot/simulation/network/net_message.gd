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
	var dir: Vector2 = msg["direction"]
	buf.encode_u8(0, MessageTypes.Binary.PLAYER_INPUT)
	buf.encode_u32(1, msg["tick"])
	buf.encode_float(5, dir.x)
	buf.encode_float(9, dir.y)
	buf.encode_u32(13, msg["input_seq"])
	return buf


static func _decode_player_input(bytes: PackedByteArray) -> Variant:
	if bytes.size() < MessageTypes.Layout.INPUT_SIZE:
		return null
	return {
		"type": MessageTypes.Binary.PLAYER_INPUT,
		"tick": bytes.decode_u32(1),
		"direction": Vector2(bytes.decode_float(5), bytes.decode_float(9)),
		"input_seq": bytes.decode_u32(13),
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
		buf.encode_u16(offset, ent["entity_id"])
		buf.encode_float(offset + 2, pos.x)
		buf.encode_float(offset + 6, pos.y)
		buf.encode_u8(offset + 10, ent["flags"])
		buf.encode_u32(offset + 11, ent.get("last_input_seq", 0))
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
		})
	return {
		"type": type,
		"tick": bytes.decode_u32(1),
		"entities": entities,
	}
