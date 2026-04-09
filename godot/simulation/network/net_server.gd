class_name NetServer
extends Node

@export var port: int = 9050

var _tcp_server := TCPServer.new()
# peer_id -> WebSocketPeer
var _peers: Dictionary = {}
# peer_id -> player_id
var _peer_to_player: Dictionary = {}
# player_id -> peer_id
var _player_to_peer: Dictionary = {}
# ip -> Array of connection timestamps (for rate limiting)
var _connection_attempts: Dictionary = {}
# peer_id -> last activity timestamp (msec)
var _last_activity: Dictionary = {}

var _movement_system: MovementSystem
var _input_buffer := InputBuffer.new()
var _player_entities: Dictionary = {}  # player_id -> PlayerEntity

# Snapshot baselines: player_id -> Snapshot (last ACK'd)
var _baselines: Dictionary = {}
# Sent snapshots awaiting ACK: player_id -> { tick -> Snapshot }
var _sent_snapshots: Dictionary = {}

var _tick: int = 0
var _tick_timer: float = 0.0
var _next_player_id: int = 1

const MAX_CONNECTIONS_PER_IP_PER_MINUTE = 10


func _ready():
	_movement_system = MovementSystem.new()
	add_child(_movement_system)

	var err = _tcp_server.listen(port)
	if err == OK:
		print("Server listening on port %d" % port)
	else:
		push_error("Failed to listen on port %d: %s" % [port, error_string(err)])
		set_process(false)
		return


func _process(delta: float):
	_accept_connections()
	_poll_peers()
	_check_zombies()
	_tick_timer += delta
	while _tick_timer >= MessageTypes.TICK_INTERVAL_MS / 1000.0:
		_tick_timer -= MessageTypes.TICK_INTERVAL_MS / 1000.0
		_server_tick()


func _accept_connections():
	while _tcp_server.is_connection_available():
		var tcp_peer = _tcp_server.take_connection()
		var ip = tcp_peer.get_connected_host()

		if not _rate_limit_ok(ip):
			tcp_peer.disconnect_from_host()
			print("Rate limited connection from %s" % ip)
			continue

		if _peers.size() >= MessageTypes.MAX_PLAYERS:
			tcp_peer.disconnect_from_host()
			print("Rejected connection: server full")
			continue

		var ws = WebSocketPeer.new()
		ws.accept_stream(tcp_peer)

		var player_id = _next_player_id
		_next_player_id += 1
		var peer_id = player_id  # 1:1 mapping

		_peers[peer_id] = ws
		_peer_to_player[peer_id] = player_id
		_player_to_peer[player_id] = peer_id

		print("Player %d connected from %s" % [player_id, ip])


func _rate_limit_ok(ip: String) -> bool:
	var now = Time.get_ticks_msec()
	var cutoff = now - 60_000  # 1 minute window
	if not _connection_attempts.has(ip):
		_connection_attempts[ip] = []
	# Prune old entries
	_connection_attempts[ip] = _connection_attempts[ip].filter(func(t): return t > cutoff)
	if _connection_attempts[ip].size() >= MAX_CONNECTIONS_PER_IP_PER_MINUTE:
		return false
	_connection_attempts[ip].append(now)
	return true


func _poll_peers():
	for peer_id in _peers.keys():
		var ws: WebSocketPeer = _peers[peer_id]
		ws.poll()

		var state = ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			# Finish handshake: spawn player if not yet spawned
			if not _player_entities.has(_peer_to_player[peer_id]):
				_on_peer_connected(peer_id)

			while ws.get_available_packet_count():
				var packet = ws.get_packet()
				if ws.was_string_packet():
					pass  # No JSON client->server messages in this step
				else:
					_handle_binary_message(peer_id, packet)

		elif state == WebSocketPeer.STATE_CLOSED:
			_on_peer_disconnected(peer_id)


func _on_peer_connected(peer_id: int):
	var player_id = _peer_to_player[peer_id]
	var ws: WebSocketPeer = _peers[peer_id]

	# Spawn player entity
	var player_scene = preload("res://simulation/entities/player_entity.tscn")
	var player = player_scene.instantiate()
	player.initialize(player_id, MessageTypes.SPAWN_POSITION)
	add_child(player)
	_player_entities[player_id] = player
	_movement_system.register_player(player)

	# Send handshake (JSON)
	var handshake = NetMessage.encode_json({
		"type": MessageTypes.JsonMsg.HANDSHAKE,
		"server_tick": _tick,
		"player_id": player_id,
		"world_seed": RNG.get_seed(),
	})
	ws.send_text(handshake)

	# Send full snapshot
	var snap = _build_current_snapshot()
	var full_msg = {
		"type": MessageTypes.Binary.FULL_SNAPSHOT,
		"tick": _tick,
		"entities": snap.to_entity_array(),
	}
	ws.send(NetMessage.encode(full_msg))

	# Set baseline for delta compression
	_baselines[player_id] = snap

	# Notify other clients
	var join_msg = NetMessage.encode_json({
		"type": MessageTypes.JsonMsg.PLAYER_JOINED,
		"player_id": player_id,
		"spawn_position": {"x": MessageTypes.SPAWN_POSITION.x, "y": MessageTypes.SPAWN_POSITION.y},
	})
	for other_peer_id in _peers:
		if other_peer_id != peer_id:
			var other_ws: WebSocketPeer = _peers[other_peer_id]
			if other_ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				other_ws.send_text(join_msg)

	EventBus.player_connected.emit({
		"player_id": player_id,
		"position": MessageTypes.SPAWN_POSITION,
	})
	print("Player %d spawned" % player_id)
	_last_activity[peer_id] = Time.get_ticks_msec()


func _on_peer_disconnected(peer_id: int):
	if not _peer_to_player.has(peer_id):
		_peers.erase(peer_id)
		return

	var player_id = _peer_to_player[peer_id]

	# Clean up player entity
	if _player_entities.has(player_id):
		_movement_system.unregister_player(player_id)
		_player_entities[player_id].queue_free()
		_player_entities.erase(player_id)

	_input_buffer.remove_player(player_id)
	_baselines.erase(player_id)
	_sent_snapshots.erase(player_id)
	_player_to_peer.erase(player_id)
	_peer_to_player.erase(peer_id)
	_peers.erase(peer_id)
	_last_activity.erase(peer_id)

	# Notify other clients
	var leave_msg = NetMessage.encode_json({
		"type": MessageTypes.JsonMsg.PLAYER_LEFT,
		"player_id": player_id,
	})
	for other_peer_id in _peers:
		var ws: WebSocketPeer = _peers[other_peer_id]
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(leave_msg)

	EventBus.player_disconnected.emit({"player_id": player_id})
	print("Player %d disconnected" % player_id)


func _handle_binary_message(peer_id: int, bytes: PackedByteArray):
	_last_activity[peer_id] = Time.get_ticks_msec()
	var msg = NetMessage.decode_binary(bytes)
	if msg == null:
		return  # Malformed -- silently drop

	var player_id = _peer_to_player.get(peer_id, -1)
	if player_id == -1:
		return  # Unknown connection -- ignore

	match msg["type"]:
		MessageTypes.Binary.PLAYER_INPUT:
			var move_dir: Vector2 = msg["move_direction"]
			var aim_dir: Vector2 = msg["aim_direction"]
			if not (is_finite(move_dir.x) and is_finite(move_dir.y) and is_finite(aim_dir.x) and is_finite(aim_dir.y)):
				return  # Reject non-finite input
			if move_dir.length_squared() > 2.0 or aim_dir.length_squared() > 2.0:
				return  # Reject absurd values (aim is expected to be a unit vector)
			_input_buffer.add_input(player_id, msg)
		MessageTypes.Binary.SNAPSHOT_ACK:
			_handle_snapshot_ack(player_id, msg["tick"])


func _handle_snapshot_ack(player_id: int, ack_tick: int) -> void:
	if not _sent_snapshots.has(player_id):
		return
	var player_sent = _sent_snapshots[player_id]
	if not player_sent.has(ack_tick):
		return  # ACK references unknown tick, ignore

	# Advance baseline to the ACK'd snapshot
	_baselines[player_id] = player_sent[ack_tick]

	# Prune all sent snapshots at or before the ACK'd tick
	var ticks_to_erase: Array = []
	for t in player_sent:
		if t <= ack_tick:
			ticks_to_erase.append(t)
	for t in ticks_to_erase:
		player_sent.erase(t)


func _server_tick():
	_tick += 1

	# Phase 1-2: Process queued inputs for each player
	for player_id in _player_entities:
		var inputs = _input_buffer.drain_inputs_for_player(player_id)
		_movement_system.process_inputs_for_player(player_id, inputs)

	# Phase 3: Tick physics
	var tick_dt = MessageTypes.TICK_INTERVAL_MS / 1000.0
	_movement_system.advance_all(tick_dt)

	# Phase 4-5: Build and send snapshots
	var current_snap = _build_current_snapshot()

	for player_id in _player_to_peer:
		var peer_id = _player_to_peer[player_id]
		var ws: WebSocketPeer = _peers.get(peer_id)
		if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue

		if not _sent_snapshots.has(player_id):
			_sent_snapshots[player_id] = {}

		var snap_copy = current_snap.duplicate_snapshot()

		if not _baselines.has(player_id):
			# No baseline -- send full snapshot
			var full_msg = {
				"type": MessageTypes.Binary.FULL_SNAPSHOT,
				"tick": _tick,
				"entities": current_snap.to_entity_array(),
			}
			ws.send(NetMessage.encode(full_msg))
			# Store sent snapshot; baseline advances on ACK
			_sent_snapshots[player_id][_tick] = snap_copy
		else:
			var baseline = _baselines[player_id]
			# Check ACK timeout -- fall back to full snapshot
			if _tick - baseline.tick > MessageTypes.ACK_TIMEOUT_TICKS:
				var full_msg = {
					"type": MessageTypes.Binary.FULL_SNAPSHOT,
					"tick": _tick,
					"entities": current_snap.to_entity_array(),
				}
				ws.send(NetMessage.encode(full_msg))
			else:
				var delta = Snapshot.diff(baseline, current_snap)
				# Always send deltas, even empty ones, so the client receives a
				# consistent tick stream. Without this, the client can't distinguish
				# "nothing changed" from "packet lost", causing the remote player
				# interpolation to freeze and jump.
				var delta_msg = {
					"type": MessageTypes.Binary.DELTA_SNAPSHOT,
					"tick": _tick,
					"entities": delta,
				}
				ws.send(NetMessage.encode(delta_msg))
			# Store sent snapshot; baseline advances on ACK
			_sent_snapshots[player_id][_tick] = snap_copy


func _check_zombies() -> void:
	var now: int = Time.get_ticks_msec()
	var zombies: Array = []
	for peer_id in _last_activity:
		if (now - _last_activity[peer_id]) > MessageTypes.ZOMBIE_TIMEOUT_MS:
			zombies.append(peer_id)
	for peer_id in zombies:
		print("Disconnecting zombie peer %d (no data for %dms)" % [peer_id, now - _last_activity[peer_id]])
		var ws: WebSocketPeer = _peers.get(peer_id)
		if ws != null:
			ws.close()
		_on_peer_disconnected(peer_id)


func _build_current_snapshot() -> Snapshot:
	var snap = Snapshot.new()
	snap.tick = _tick
	for player_id in _player_entities:
		var player: PlayerEntity = _player_entities[player_id]
		snap.entities[player_id] = player.to_snapshot_data()
	return snap
