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
var _pending_inputs: Array = []  # { input_seq, move_direction, aim_direction, dodge_pressed }
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
const MAX_PENDING_INPUTS: int = 60   # 3 seconds at tick rate
var _visual_offset: Vector2 = Vector2.ZERO  # visual correction being blended out

# Input sending timer (match server tick rate)
var _input_timer: float = 0.0

# Direction set by caller each frame (view/input layer)
var input_direction: Vector2 = Vector2.ZERO
var aim_direction: Vector2 = Vector2.RIGHT  # set by caller each frame
# Edge-triggered dodge latch. Set to true by the view layer on the display frame
# the dodge key is pressed; cleared by _send_input when the next tick fires.
# This bridges the display-rate-to-tick-rate cadence gap so a dodge press that
# lands between two tick boundaries is never dropped and never double-fires.
var dodge_pressed_latch: bool = false


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

		# Frame-rate prediction: run canonical advance() at display framerate.
		# dt-independent math means client and server produce the same result.
		if _local_player != null:
			_local_player.apply_input({
				"move_direction": input_direction,
				"aim_direction": aim_direction,
			})
			# Don't pass dodge_pressed via apply_input — it's handled directly below
			# so that prediction kicks off the dodge exactly once per latch-set state,
			# and _send_input clears the latch at tick rate.
			if dodge_pressed_latch and _local_player.can_dodge():
				_local_player.start_dodge()  # client predicts dodge immediately
			_local_player.advance(delta)

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

	var dodge = dodge_pressed_latch
	dodge_pressed_latch = false  # consume once per tick send

	var input = {
		"input_seq": _input_seq,
		"move_direction": input_direction,
		"aim_direction": aim_direction,
		"dodge_pressed": dodge,
	}
	_pending_inputs.append(input)
	if _pending_inputs.size() > MAX_PENDING_INPUTS:
		_pending_inputs = _pending_inputs.slice(-MAX_PENDING_INPUTS)

	var msg = {
		"type": MessageTypes.Binary.PLAYER_INPUT,
		"tick": _server_tick,
		"move_direction": input_direction,
		"aim_direction": aim_direction,
		"dodge_pressed": dodge,
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
	while _pending_inputs.size() > 0 and _pending_inputs[0]["input_seq"] <= server_seq:
		_pending_inputs.pop_front()

	# Restore authoritative state before replay
	_local_player.position = server_pos
	_local_player.velocity = server_data.get("velocity", Vector2.ZERO)
	_local_player.aim_direction = server_data.get("aim_direction", Vector2.RIGHT)
	_local_player.state = server_data.get("state", 0)
	_local_player.dodge_time_remaining = server_data.get("dodge_time_remaining", 0.0)
	# dodge_cooldown_remaining is not in the snapshot; if the server says we're
	# past a dodge, cooldown is implicit in server state. Leave local cooldown.
	# If currently dodging, derive dodge_direction from velocity so the next
	# replayed tick continues in the server-authoritative direction rather than
	# overriding with the client's stale direction * dodge_speed.
	if _local_player.state == PlayerMovementState.DODGING:
		var v: Vector2 = _local_player.velocity
		if v.length_squared() > 0.01:
			_local_player.dodge_direction = v.normalized()

	# Replay unacknowledged inputs through the canonical advance function,
	# using tick interval as dt to match how the server processed them.
	# Suppress EventBus emissions during replay — view-side juice (FootstepDust,
	# WallBump, DodgeTrail, screen shake) must not fire once per replayed input.
	var tick_dt: float = MessageTypes.TICK_INTERVAL_MS / 1000.0
	_local_player._suppress_events = true
	for pending in _pending_inputs:
		_local_player.apply_input(pending)
		_local_player.advance(tick_dt)
	_local_player._suppress_events = false

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
		return null

	if _snapshot_prev == null or _snapshot_curr == null:
		return null

	if not _snapshot_curr.entities.has(entity_id):
		return null

	var curr = _snapshot_curr.entities[entity_id]
	var curr_pos: Vector2 = curr["position"]

	if not _snapshot_prev.entities.has(entity_id):
		return curr_pos

	var prev = _snapshot_prev.entities[entity_id]
	var prev_pos: Vector2 = prev["position"]

	var tick_interval = MessageTypes.TICK_INTERVAL_MS / 1000.0
	var t = clampf(_snapshot_time / tick_interval, 0.0, MAX_REMOTE_INTERP)

	if t <= 1.0:
		# Within interpolation window — lerp between snapshots
		return prev_pos.lerp(curr_pos, t)
	else:
		# Extrapolate forward using current snapshot velocity.
		# Fall back to positional delta as implied velocity when the snapshot
		# does not carry an explicit velocity field (e.g. in tests or older server builds).
		var snap_vel: Vector2 = curr.get("velocity", (curr_pos - prev_pos) / tick_interval)
		var extra_time = (t - 1.0) * tick_interval
		return curr_pos + snap_vel * extra_time


func get_local_player_position() -> Variant:
	if _local_player == null:
		return null
	return _local_player.position


## Returns the local player's predicted aim direction (unit vector), or null if no local player.
func get_local_player_aim_direction() -> Variant:
	if _local_player == null: return null
	return _local_player.aim_direction


## Returns the local player's current movement state (PlayerMovementState constant), or null.
func get_local_player_state() -> Variant:
	if _local_player == null: return null
	return _local_player.state


## Returns the local player's current velocity vector, or null.
func get_local_player_velocity() -> Variant:
	if _local_player == null: return null
	return _local_player.velocity


## Returns a remote entity's snapshot data dict (read-only), or null if not present.
func get_remote_entity_snapshot(entity_id: int) -> Variant:
	if _snapshot_curr == null: return null
	if not _snapshot_curr.entities.has(entity_id): return null
	return _snapshot_curr.entities[entity_id]


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
