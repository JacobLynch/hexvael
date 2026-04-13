class_name NetClient
extends Node

signal connected(player_id: int)
signal disconnected()
signal snapshot_received(tick: int, entities: Array)
signal player_joined(player_id: int, spawn_position: Vector2)
signal player_left(player_id: int)
signal enemy_snapshot_updated(enemy_entities: Dictionary)
signal enemy_died_received(event: Dictionary)

var _ws := WebSocketPeer.new()
var _connected: bool = false
var _local_player_id: int = -1
var _server_tick: int = 0

# Client-side prediction state
var _input_seq: int = 0
var _pending_inputs: Array = []  # { input_seq, move_direction, aim_direction, action_flags }
var _local_player: PlayerEntity = null

# Client-side RTT tracking: time input_seq was sent -> compute round trip when ACK'd
var _input_send_times: Dictionary = {}  # input_seq (int) -> send time msec (int)
const _RTT_SEND_HISTORY: int = 60       # keep at most 60 unack'd entries (~2s at 30Hz)
var _rtt_ms: int = 0                    # rolling RTT estimate (ms); 0 until first ack

# Projectile simulation (set by client_main via set_projectile_system)
var _projectile_system: ProjectileSystem = null

# Interpolation state: ring buffer of recent snapshots for remote entities
# 3 snapshots provides resilience against single packet loss
const SNAPSHOT_BUFFER_SIZE: int = 3
const BUFFER_DELAY_TICKS: int = 2  # Render 2 ticks behind latest snapshot (~66ms at 30Hz)
var _snapshot_buffer: Array = []  # Array of Snapshot, newest at end
var _snapshot_time: float = 0.0   # Time since newest snapshot arrived
var _enemy_prev: Dictionary = {}  # entity_id -> snapshot data
var _enemy_curr: Dictionary = {}  # entity_id -> snapshot data

# Snapshot object pool to reduce GC pressure
var _snapshot_pool: Array = []  # Array of Snapshot objects available for reuse
const _SNAPSHOT_POOL_SIZE: int = 5

# Max remote interpolation t — allows brief extrapolation past the latest snapshot
# to cover network jitter, preventing the freeze-then-jump stutter.
# 3.0 = up to 2 ticks of extrapolation (~66ms at 30Hz).
const MAX_REMOTE_INTERP: float = 3.0

# Visual reconciliation
const SNAP_THRESHOLD: float = 50.0   # pixels — snap if over this
const BLEND_SPEED: float = 10.0      # lerp rate per second
const MAX_PENDING_INPUTS: int = 60   # 2 seconds at 30Hz tick rate
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
# Edge-triggered fire latch. Set to true by the view layer on the display frame
# the fire button is pressed (left mouse / fire action); cleared by _send_input
# when the next tick fires. Same cadence-bridging contract as dodge_pressed_latch.
var fire_pressed_latch: bool = false


func _get_pooled_snapshot() -> Snapshot:
	if _snapshot_pool.is_empty():
		return Snapshot.new()
	return _snapshot_pool.pop_back()


func _return_to_pool(snap: Snapshot) -> void:
	if _snapshot_pool.size() < _SNAPSHOT_POOL_SIZE:
		snap.reset()
		_snapshot_pool.append(snap)


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
			# Don't pass action_flags via apply_input — the dodge bit is handled directly
			# below so that prediction kicks off the dodge exactly once per latch-set
			# state, and _send_input clears the latch at tick rate.
			if dodge_pressed_latch and _local_player.can_dodge():
				_local_player.start_dodge()  # client predicts dodge immediately
			_local_player.advance(delta)

		# Send input at tick rate (network bandwidth matches server tick rate)
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
		MessageTypes.Binary.ENEMY_DIED:
			var event = {
				"entity_id": msg["entity_id"],
				"position": msg["position"],
				"killer_id": msg["killer_id"],
			}
			EventBus.enemy_died.emit(event)
			enemy_died_received.emit(event)
		MessageTypes.Binary.PROJECTILE_SPAWNED:
			_handle_projectile_spawned(bytes)
		MessageTypes.Binary.PROJECTILE_DESPAWNED:
			_handle_projectile_despawned(bytes)


func _handle_projectile_spawned(bytes: PackedByteArray) -> void:
	if _projectile_system == null:
		return
	var event = NetMessage.decode_projectile_spawned(bytes)
	if event.is_empty():
		return
	_projectile_system.adopt_authoritative(
		event["projectile_id"],
		event["owner_player_id"],
		event["type_id"],
		event["origin"],
		event["direction"],
		event["input_seq"],
		get_rtt_ms(),
		event.get("tick_age_ms", 0),
		event.get("source_position", event["origin"]))


func _handle_projectile_despawned(bytes: PackedByteArray) -> void:
	if _projectile_system == null:
		return
	var event = NetMessage.decode_projectile_despawned(bytes)
	if event.is_empty():
		return
	_projectile_system.on_despawn_event(
		event["projectile_id"], event["reason"], event["position"],
		event["target_entity_id"], event.get("tick_age_ms", 0))


func _apply_full_snapshot(msg: Dictionary):
	var snap = Snapshot.new()
	snap.tick = msg["tick"]
	for ent in msg["entities"]:
		snap.entities[ent["entity_id"]] = ent

	# Reset buffer with this snapshot duplicated (need 2 for interpolation to start)
	_snapshot_buffer = [snap.duplicate_snapshot(), snap]
	_snapshot_time = 0.0
	_server_tick = msg["tick"]

	_reconcile_local_player(snap)
	_send_ack(msg["tick"])

	# Enemy entities
	_enemy_prev = {}
	_enemy_curr = {}
	for ent in msg.get("enemy_entities", []):
		var eid = ent["entity_id"]
		_enemy_prev[eid] = ent.duplicate()
		_enemy_curr[eid] = ent.duplicate()
	enemy_snapshot_updated.emit(_enemy_curr)

	snapshot_received.emit(snap.tick, msg["entities"])


func _apply_delta_snapshot(msg: Dictionary):
	if _snapshot_buffer.is_empty():
		return  # Need a full snapshot first

	# Get a snapshot from pool or create new
	var snap: Snapshot = _get_pooled_snapshot()

	# Copy latest snapshot data into pooled object
	var newest: Snapshot = _snapshot_buffer[-1]
	snap.copy_from(newest)
	snap.apply_delta(msg["tick"], msg["entities"])

	# Push to buffer, return evicted snapshot to pool
	_snapshot_buffer.append(snap)
	while _snapshot_buffer.size() > SNAPSHOT_BUFFER_SIZE:
		var evicted: Snapshot = _snapshot_buffer.pop_front()
		_return_to_pool(evicted)

	_snapshot_time = 0.0
	_server_tick = msg["tick"]

	_reconcile_local_player(snap)
	_send_ack(msg["tick"])

	# Enemy delta
	_enemy_prev = _enemy_curr.duplicate()
	for ent in msg.get("enemy_entities", []):
		var eid: int = ent["entity_id"]
		if ent["state"] == MessageTypes.EnemyFlags.REMOVED:
			_enemy_curr.erase(eid)
		else:
			_enemy_curr[eid] = ent.duplicate()
	enemy_snapshot_updated.emit(_enemy_curr)

	snapshot_received.emit(snap.tick, msg["entities"])


func _send_ack(tick: int):
	if not _connected:
		return
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

	var flags: int = 0
	if dodge_pressed_latch:
		flags |= MessageTypes.InputActionFlags.DODGE
	dodge_pressed_latch = false  # consume once per tick send
	if fire_pressed_latch:
		flags |= MessageTypes.InputActionFlags.FIRE
	fire_pressed_latch = false  # consume once per tick send

	var input = {
		"input_seq": _input_seq,
		"move_direction": input_direction,
		"aim_direction": aim_direction,
		"action_flags": flags,
	}
	_pending_inputs.append(input)
	while _pending_inputs.size() > MAX_PENDING_INPUTS:
		_pending_inputs.pop_front()

	# Record send time for RTT measurement; pruned when ack'd or overflows.
	_input_send_times[_input_seq] = Time.get_ticks_msec()
	if _input_send_times.size() > _RTT_SEND_HISTORY:
		var oldest_seq: int = _input_seq - _RTT_SEND_HISTORY
		_input_send_times.erase(oldest_seq)

	var msg = {
		"type": MessageTypes.Binary.PLAYER_INPUT,
		"tick": _server_tick,
		"move_direction": input_direction,
		"aim_direction": aim_direction,
		"action_flags": flags,
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

	# Update RTT estimate from the round-trip of this input_seq.
	if _input_send_times.has(server_seq):
		var sample_ms: int = Time.get_ticks_msec() - _input_send_times[server_seq]
		# Simple running average over recent acks — keeps computation O(1) per tick.
		_rtt_ms = (_rtt_ms * 7 + sample_ms) / 8
		_input_send_times.erase(server_seq)

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
	_local_player.collision_count = server_data.get("collision_count", 0)
	_local_player.last_collision_normal = server_data.get("last_collision_normal", Vector2.ZERO)
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

	if _snapshot_buffer.size() < 2:
		return null

	var tick_interval = MessageTypes.TICK_INTERVAL_MS / 1000.0
	var newest_tick: int = _snapshot_buffer[-1].tick

	# Calculate render time: newest_tick minus buffer delay, plus elapsed time
	# render_tick is a float representing where we are in the timeline
	var render_tick: float = float(newest_tick) - BUFFER_DELAY_TICKS + (_snapshot_time / tick_interval)

	# Find the two snapshots that bracket render_tick
	var snap_a: Snapshot = null
	var snap_b: Snapshot = null
	for i in range(_snapshot_buffer.size() - 1):
		var s0: Snapshot = _snapshot_buffer[i]
		var s1: Snapshot = _snapshot_buffer[i + 1]
		if float(s0.tick) <= render_tick and render_tick <= float(s1.tick):
			snap_a = s0
			snap_b = s1
			break

	# Fallback: if render_tick is before all snapshots, use oldest two
	if snap_a == null:
		if render_tick < float(_snapshot_buffer[0].tick):
			snap_a = _snapshot_buffer[0]
			snap_b = _snapshot_buffer[min(1, _snapshot_buffer.size() - 1)]
		else:
			# render_tick is past all snapshots — extrapolate from newest two
			snap_a = _snapshot_buffer[-2]
			snap_b = _snapshot_buffer[-1]

	if not snap_b.entities.has(entity_id):
		return null

	var curr = snap_b.entities[entity_id]
	var curr_pos: Vector2 = curr["position"]

	if not snap_a.entities.has(entity_id):
		return curr_pos

	var prev = snap_a.entities[entity_id]
	var prev_pos: Vector2 = prev["position"]

	# Compute interpolation parameter between snap_a and snap_b
	var tick_span: float = float(snap_b.tick - snap_a.tick)
	if tick_span <= 0.0:
		return curr_pos

	var t: float = (render_tick - float(snap_a.tick)) / tick_span
	t = clampf(t, 0.0, MAX_REMOTE_INTERP)

	if t <= 1.0:
		# Within interpolation window — lerp between snapshots
		return prev_pos.lerp(curr_pos, t)
	else:
		# Extrapolate forward using current snapshot velocity.
		# Fall back to positional delta as implied velocity when the snapshot
		# does not carry an explicit velocity field (e.g. in tests or older server builds).
		var snap_vel: Vector2 = curr.get("velocity", (curr_pos - prev_pos) / (tick_span * tick_interval))
		var extra_time = (t - 1.0) * tick_span * tick_interval
		return curr_pos + snap_vel * extra_time


func get_interpolated_enemy(entity_id: int) -> Variant:
	if not _enemy_curr.has(entity_id):
		return null

	var curr = _enemy_curr[entity_id]
	if not _enemy_prev.has(entity_id):
		return curr  # New enemy, no interpolation

	var prev = _enemy_prev[entity_id]
	var tick_interval = MessageTypes.TICK_INTERVAL_MS / 1000.0
	var t = clampf(_snapshot_time / tick_interval, 0.0, MAX_REMOTE_INTERP)

	var result = curr.duplicate()
	result["position"] = prev["position"].lerp(curr["position"], t)
	result["facing"] = prev["facing"].lerp(curr["facing"], t)
	if result["facing"].length_squared() > 0.0:
		result["facing"] = result["facing"].normalized()
	return result


func get_snapshot_buffer_size() -> int:
	return _snapshot_buffer.size()


func get_enemy_ids() -> Array:
	return _enemy_curr.keys()


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
	if _snapshot_buffer.is_empty(): return null
	var snap_curr: Snapshot = _snapshot_buffer[-1]
	if not snap_curr.entities.has(entity_id): return null
	return snap_curr.entities[entity_id]


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


## Returns the current rolling RTT estimate in milliseconds (0 until the first
## round-trip completes). Used by ProjectileSystem for rejection timeout scaling
## and by adopt_authoritative for fast-forward distance.
func get_rtt_ms() -> int:
	return _rtt_ms


func set_projectile_system(ps: ProjectileSystem) -> void:
	_projectile_system = ps
