class_name NetClient
extends Node

signal connected(player_id: int)
signal disconnected()
signal snapshot_received(tick: int, entities: Array)
signal player_joined(player_id: int, spawn_position: Vector2)
signal player_left(player_id: int)

var _ws := WebSocketPeer.new()
var _connected: bool = false
var _local_player_id: int = -1
var _server_tick: int = 0

# Client-side prediction state
var _input_seq: int = 0
var _pending_inputs: Array = []  # { seq, direction }
var _local_player: PlayerEntity = null

# Interpolation state: two most recent snapshots for remote entities
var _snapshot_prev: Snapshot = null
var _snapshot_curr: Snapshot = null
var _snapshot_time: float = 0.0  # Time since _snapshot_curr arrived

# Max remote interpolation t — allows brief extrapolation past the latest snapshot
# to cover network jitter, preventing the freeze-then-jump stutter.
# 1.5 = up to 25ms of extrapolation at 20Hz tick rate.
const MAX_REMOTE_INTERP: float = 1.5

# Visual reconciliation
const SNAP_THRESHOLD: float = 50.0   # pixels — snap if over this
const BLEND_SPEED: float = 10.0      # lerp rate per second
var _visual_offset: Vector2 = Vector2.ZERO  # visual correction being blended out

# Input sending timer (match server tick rate)
var _input_timer: float = 0.0

# Direction set by caller each frame (view/input layer)
var input_direction: Vector2 = Vector2.ZERO


func connect_to_server(address: String, port: int) -> Error:
	var url = "ws://%s:%d" % [address, port]
	var err = _ws.connect_to_url(url)
	if err != OK:
		push_error("Failed to connect to %s: %s" % [url, error_string(err)])
	return err


func _process(delta: float):
	_ws.poll()
	var state = _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true

		while _ws.get_available_packet_count():
			var packet = _ws.get_packet()
			if _ws.was_string_packet():
				_handle_json_message(packet.get_string_from_utf8())
			else:
				_handle_binary_message(packet)

		# Frame-rate prediction: run physics every frame for instant response
		if _local_player != null:
			_local_player.apply_input(input_direction)
			_local_player.move_delta(delta)

		# Send input at tick rate (network bandwidth stays at 20Hz)
		_input_timer += delta
		var tick_interval = MessageTypes.TICK_INTERVAL_MS / 1000.0
		while _input_timer >= tick_interval:
			_input_timer -= tick_interval
			_send_input()

		# Advance remote interpolation timer
		_snapshot_time += delta

	elif state == WebSocketPeer.STATE_CLOSED and _connected:
		_connected = false
		_local_player_id = -1
		disconnected.emit()


func _handle_json_message(text: String):
	var msg = NetMessage.decode_json(text)
	if msg == null:
		return

	match msg.get("type", ""):
		MessageTypes.JsonMsg.HANDSHAKE:
			_local_player_id = int(msg["player_id"])
			_server_tick = int(msg["server_tick"])
			RNG.seed(int(msg["world_seed"]))
			connected.emit(_local_player_id)

		MessageTypes.JsonMsg.PLAYER_JOINED:
			var pos_dict = msg["spawn_position"]
			var pos = Vector2(float(pos_dict["x"]), float(pos_dict["y"]))
			player_joined.emit(int(msg["player_id"]), pos)

		MessageTypes.JsonMsg.PLAYER_LEFT:
			player_left.emit(int(msg["player_id"]))


func _handle_binary_message(bytes: PackedByteArray):
	var msg = NetMessage.decode_binary(bytes)
	if msg == null:
		return

	match msg["type"]:
		MessageTypes.Binary.FULL_SNAPSHOT:
			_apply_full_snapshot(msg)
		MessageTypes.Binary.DELTA_SNAPSHOT:
			_apply_delta_snapshot(msg)


func _apply_full_snapshot(msg: Dictionary):
	var snap = Snapshot.new()
	snap.tick = msg["tick"]
	for ent in msg["entities"]:
		snap.entities[ent["entity_id"]] = ent
	_snapshot_prev = snap.duplicate_snapshot()
	_snapshot_curr = snap
	_snapshot_time = 0.0
	_server_tick = msg["tick"]

	_reconcile_local_player(snap)
	_send_ack(msg["tick"])
	snapshot_received.emit(snap.tick, msg["entities"])


func _apply_delta_snapshot(msg: Dictionary):
	if _snapshot_curr == null:
		return  # Need a full snapshot first

	_snapshot_prev = _snapshot_curr.duplicate_snapshot()
	_snapshot_curr.apply_delta(msg["tick"], msg["entities"])
	_snapshot_time = 0.0
	_server_tick = msg["tick"]

	_reconcile_local_player(_snapshot_curr)
	_send_ack(msg["tick"])
	snapshot_received.emit(_snapshot_curr.tick, msg["entities"])


func _send_ack(tick: int):
	var msg = {
		"type": MessageTypes.Binary.SNAPSHOT_ACK,
		"tick": tick,
	}
	_ws.send(NetMessage.encode(msg))


# --- Client-Side Prediction ---

func set_local_player(player: PlayerEntity) -> void:
	_local_player = player


func _send_input():
	if _local_player == null or _local_player_id == -1:
		return

	_input_seq += 1

	# Store for reconciliation (direction only — position is continuous now)
	_pending_inputs.append({
		"seq": _input_seq,
		"direction": input_direction,
	})

	# Send to server
	var msg = {
		"type": MessageTypes.Binary.PLAYER_INPUT,
		"tick": _server_tick,
		"direction": input_direction,
		"input_seq": _input_seq,
	}
	_ws.send(NetMessage.encode(msg))


func _reconcile_local_player(snap: Snapshot):
	if _local_player == null or _local_player_id == -1:
		return
	if not snap.entities.has(_local_player_id):
		return

	var server_data = snap.entities[_local_player_id]
	var server_pos: Vector2 = server_data["position"]
	var server_seq: int = server_data.get("last_input_seq", 0)

	# Capture what the view was showing before reconciliation
	var visual_before: Vector2 = _local_player.position + _visual_offset

	# Discard predictions the server has already processed
	while _pending_inputs.size() > 0 and _pending_inputs[0]["seq"] <= server_seq:
		_pending_inputs.pop_front()

	# Snap to server authoritative position
	_local_player.position = server_pos

	# Replay unacknowledged inputs at tick delta (matching server simulation)
	for pending in _pending_inputs:
		_local_player.apply_input(pending["direction"])
		_local_player.tick()

	# Visual offset: smoothly blend from old visual position to new logical position
	var correction: Vector2 = visual_before - _local_player.position
	var correction_dist: float = correction.length()

	if correction_dist < 0.01:
		_visual_offset = Vector2.ZERO
	elif correction_dist < SNAP_THRESHOLD:
		_visual_offset = correction
	else:
		# Teleport — too far to blend
		_visual_offset = Vector2.ZERO


# --- Interpolation for Remote Entities ---

func get_interpolated_position(entity_id: int) -> Variant:
	if entity_id == _local_player_id:
		return null  # Local player uses prediction, not interpolation

	if _snapshot_prev == null or _snapshot_curr == null:
		return null

	if not _snapshot_curr.entities.has(entity_id):
		return null

	var curr_pos: Vector2 = _snapshot_curr.entities[entity_id]["position"]

	if not _snapshot_prev.entities.has(entity_id):
		return curr_pos  # New entity, no interpolation yet

	var prev_pos: Vector2 = _snapshot_prev.entities[entity_id]["position"]

	var tick_interval = MessageTypes.TICK_INTERVAL_MS / 1000.0
	var t = clampf(_snapshot_time / tick_interval, 0.0, MAX_REMOTE_INTERP)
	return prev_pos.lerp(curr_pos, t)


func get_local_player_position() -> Variant:
	if _local_player == null:
		return null
	return _local_player.position


func get_visual_offset() -> Vector2:
	return _visual_offset


func blend_visual_offset(delta: float) -> void:
	# Exponential decay — framerate-independent unlike lerp(offset, zero, speed * delta).
	# At BLEND_SPEED=10, half-life is ~69ms regardless of whether the game runs at
	# 60fps, 120fps, or 144fps.
	_visual_offset *= exp(-BLEND_SPEED * delta)
	if _visual_offset.length() < 0.1:
		_visual_offset = Vector2.ZERO


func is_server_connected() -> bool:
	return _connected


func get_local_player_id() -> int:
	return _local_player_id
