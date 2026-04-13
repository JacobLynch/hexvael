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

var _enemy_system: EnemySystem
var _enemy_spawner: EnemySpawner
var _death_events: Array = []

# Snapshot baselines: player_id -> Snapshot (last ACK'd)
var _baselines: Dictionary = {}
# Sent snapshots awaiting ACK: player_id -> { tick -> Snapshot }
var _sent_snapshots: Dictionary = {}

# Per-player RTT tracking. Measures round-trip by timing SNAPSHOT_ACK.
const _RTT_SAMPLE_WINDOW = 8
# player_id -> Dictionary[tick: int, send_time_ms: int]
var _pending_snapshot_sends: Dictionary = {}
# player_id -> Array[int] (rolling RTT samples in ms)
var _rtt_samples: Dictionary = {}

# Per-player input rate limiting: player_id -> inputs received this tick
var _inputs_this_tick: Dictionary = {}

var _tick: int = 0
var _tick_timer: float = 0.0
var _next_player_id: int = 1

const MAX_CONNECTIONS_PER_IP_PER_MINUTE = 10

var _projectile_system: ProjectileSystem
var _player_position_history: PlayerPositionHistory


func _ready():
	_movement_system = MovementSystem.new()
	add_child(_movement_system)

	_enemy_system = EnemySystem.new()
	add_child(_enemy_system)

	var enemy_params = EnemyParams.new()
	var spawner_params = SpawnerParams.new()
	_enemy_spawner = EnemySpawner.new()
	add_child(_enemy_spawner)
	_enemy_spawner.initialize(_enemy_system, spawner_params, enemy_params)

	_projectile_system = ProjectileSystem.new()
	add_child(_projectile_system)

	_player_position_history = PlayerPositionHistory.new()

	# Extract wall AABBs from the arena and pass them to the projectile system.
	# The arena is a sibling node ("Arena") in the server scene root.
	# In unit-test environments NetServer has no parent with an Arena child, so
	# we degrade gracefully (projectiles fly through walls) rather than crashing.
	var parent: Node = get_parent()
	var arena: Node = parent.get_node_or_null("Arena") if parent != null else null
	if arena != null:
		_projectile_system.set_walls(WallGeometry.extract_aabbs(arena))
	else:
		push_warning("NetServer: Arena node not found — projectiles will have no wall collisions")

	EventBus.enemy_died.connect(_on_enemy_died)

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

	# Prune old entries for this IP
	_connection_attempts[ip] = _connection_attempts[ip].filter(func(t): return t > cutoff)

	# If this IP has no recent attempts, remove it entirely
	if _connection_attempts[ip].is_empty():
		_connection_attempts.erase(ip)

	# Enforce max tracked IPs — drop oldest entries if over limit
	if _connection_attempts.size() >= MessageTypes.MAX_TRACKED_IPS:
		_prune_oldest_connection_attempts(cutoff)

	# Re-check after potential pruning
	if not _connection_attempts.has(ip):
		_connection_attempts[ip] = []

	if _connection_attempts[ip].size() >= MAX_CONNECTIONS_PER_IP_PER_MINUTE:
		return false

	_connection_attempts[ip].append(now)
	return true


func _prune_oldest_connection_attempts(cutoff: int) -> void:
	# Remove all IPs with no recent attempts
	var ips_to_remove: Array = []
	for ip in _connection_attempts:
		_connection_attempts[ip] = _connection_attempts[ip].filter(func(t): return t > cutoff)
		if _connection_attempts[ip].is_empty():
			ips_to_remove.append(ip)
	for ip in ips_to_remove:
		_connection_attempts.erase(ip)

	# If still over limit, remove IPs with oldest last attempt
	while _connection_attempts.size() >= MessageTypes.MAX_TRACKED_IPS:
		var oldest_ip: String = ""
		var oldest_time: int = Time.get_ticks_msec()
		for ip in _connection_attempts:
			if _connection_attempts[ip].is_empty():
				oldest_ip = ip
				break
			var last_attempt: int = _connection_attempts[ip][-1]
			if last_attempt < oldest_time:
				oldest_time = last_attempt
				oldest_ip = ip
		if oldest_ip != "":
			_connection_attempts.erase(oldest_ip)
		else:
			break


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
		"enemy_entities": snap.to_enemy_entity_array(),
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
	_pending_snapshot_sends.erase(player_id)
	_rtt_samples.erase(player_id)
	_player_position_history.drop_player(player_id)
	_projectile_system._fire_cooldown.erase(player_id)
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
		push_warning("NetServer: malformed packet from peer %d (%d bytes, first byte: %d)" % [
			peer_id, bytes.size(), bytes[0] if bytes.size() > 0 else -1])
		return

	var player_id = _peer_to_player.get(peer_id, -1)
	if player_id == -1:
		return  # Unknown connection -- ignore

	match msg["type"]:
		MessageTypes.Binary.PLAYER_INPUT:
			var move_dir: Vector2 = msg["move_direction"]
			var aim_dir: Vector2 = msg["aim_direction"]
			if not (is_finite(move_dir.x) and is_finite(move_dir.y) and is_finite(aim_dir.x) and is_finite(aim_dir.y)):
				return  # Reject non-finite input
			if move_dir.length_squared() > 2.5:
				return  # Reject absurd move values; 2.5 gives float headroom above max diagonal (2.0)
			# Aim direction must be approximately unit length (tolerance: 0.9 to 1.1)
			var aim_mag_sq: float = aim_dir.length_squared()
			if aim_mag_sq < 0.81 or aim_mag_sq > 1.21:
				return  # Reject non-unit aim direction
			# Rate limit: max inputs per tick per player
			var count: int = _inputs_this_tick.get(player_id, 0)
			if count >= MessageTypes.MAX_INPUTS_PER_TICK:
				push_warning("NetServer: rate limiting player %d (>%d inputs this tick)" % [
					player_id, MessageTypes.MAX_INPUTS_PER_TICK])
				return
			_inputs_this_tick[player_id] = count + 1
			_input_buffer.add_input(player_id, msg)
		MessageTypes.Binary.SNAPSHOT_ACK:
			_handle_snapshot_ack(player_id, msg["tick"])


func _handle_snapshot_ack(player_id: int, ack_tick: int) -> void:
	if not _sent_snapshots.has(player_id):
		push_warning("NetServer: ACK from player %d but no sent snapshots recorded" % player_id)
		return
	var player_sent = _sent_snapshots[player_id]
	if not player_sent.has(ack_tick):
		# Client ACKed a tick we never sent — could be packet corruption,
		# replay attack, or malicious client. Log and ignore.
		push_warning("NetServer: player %d ACKed unknown tick %d (sent: %s)" % [
			player_id, ack_tick, player_sent.keys()])
		return

	# Record RTT sample for this ACK
	_record_snapshot_ack(player_id, ack_tick)

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
	# Reset per-tick input counters
	_inputs_this_tick.clear()
	var tick_dt: float = MessageTypes.TICK_INTERVAL_MS / 1000.0

	# Record player positions before movement so the rewind lookup in
	# ProjectileSpawnRouter.handle_fire uses pre-step positions (matching
	# what the client's position history also records at this point).
	for player_id in _player_entities:
		var player: PlayerEntity = _player_entities[player_id]
		_player_position_history.record(player_id, _tick, player.position)

	# Phase 1-2: Process queued inputs for each player.
	# We inline the input loop (rather than delegating solely to MovementSystem)
	# so we can also route fire inputs through ProjectileSpawnRouter per-input.
	var queued_spawn_events: Array = []
	for player_id in _player_entities:
		var player: PlayerEntity = _player_entities[player_id]
		var inputs: Array = _input_buffer.drain_inputs_for_player(player_id)
		for input in inputs:
			player.apply_input(input)
			var context: Dictionary = {
				"authoritative": true,
				"rtt_ms": get_rtt_ms(player_id),
				"position_history": _player_position_history,
				"tick": _tick,
				"spawn_events": queued_spawn_events,
			}
			ProjectileSpawnRouter.handle_fire(player, input, _projectile_system, context)

	# Phase 3: Tick physics
	_movement_system.advance_all(tick_dt)

	# Phase: Spawn and tick enemies
	_enemy_spawner.advance(tick_dt, _player_entities)
	_enemy_system.advance_all(tick_dt, _player_entities)

	# Phase: Tick cooldowns and advance projectiles; collect despawns via return value.
	_projectile_system.tick_cooldowns(tick_dt)
	var advance_start_ms: int = Time.get_ticks_msec()
	var despawns: Array = _projectile_system.advance(
		tick_dt,
		_player_entities.values(),
		_enemy_system.get_all_enemies()
	)

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
				"enemy_entities": current_snap.to_enemy_entity_array(),
			}
			ws.send(NetMessage.encode(full_msg))
			# Store sent snapshot; baseline advances on ACK
			_sent_snapshots[player_id][_tick] = snap_copy
			_record_snapshot_send(player_id, _tick)
		else:
			var baseline = _baselines[player_id]
			# Check ACK timeout -- fall back to full snapshot
			if _tick - baseline.tick > MessageTypes.ACK_TIMEOUT_TICKS:
				var full_msg = {
					"type": MessageTypes.Binary.FULL_SNAPSHOT,
					"tick": _tick,
					"entities": current_snap.to_entity_array(),
					"enemy_entities": current_snap.to_enemy_entity_array(),
				}
				ws.send(NetMessage.encode(full_msg))
			else:
				var delta = Snapshot.diff(baseline, current_snap)
				var enemy_delta = Snapshot.diff_enemies(baseline, current_snap)
				# Always send deltas, even empty ones, so the client receives a
				# consistent tick stream. Without this, the client can't distinguish
				# "nothing changed" from "packet lost", causing the remote player
				# interpolation to freeze and jump.
				var delta_msg = {
					"type": MessageTypes.Binary.DELTA_SNAPSHOT,
					"tick": _tick,
					"entities": delta,
					"enemy_entities": enemy_delta,
				}
				ws.send(NetMessage.encode(delta_msg))
			# Store sent snapshot; baseline advances on ACK
			_sent_snapshots[player_id][_tick] = snap_copy
			_record_snapshot_send(player_id, _tick)

	# Send queued death events
	for death_event in _death_events:
		var death_msg = NetMessage.encode({
			"type": MessageTypes.Binary.ENEMY_DIED,
			"entity_id": death_event["entity_id"],
			"position": death_event["position"],
			"killer_id": death_event.get("killer_id", 0),
		})
		for peer_id in _peers:
			var ws: WebSocketPeer = _peers[peer_id]
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				ws.send(death_msg)
	_death_events.clear()

	# Broadcast projectile spawn and despawn events collected during this tick.
	# NOTE: These events are broadcast AFTER snapshots in the same tick, so
	# clients must handle events that arrive after the snapshot with the same
	# tick number. This is consistent with how enemy_died events work.
	var broadcast_time_ms: int = Time.get_ticks_msec()
	for spawn_event in queued_spawn_events:
		# Spawns are queued during input processing, but the projectile then
		# advances by tick_dt during _projectile_system.advance() before broadcast.
		# Include that simulation time so the client can fast-forward correctly.
		var wall_clock_age: int = broadcast_time_ms - spawn_event["queue_time_ms"]
		var tick_age_ms: int = clampi(wall_clock_age + int(MessageTypes.TICK_INTERVAL_MS), 0, 255)
		spawn_event["tick_age_ms"] = tick_age_ms
		var spawn_msg: PackedByteArray = NetMessage.encode_projectile_spawned(spawn_event)
		for peer_id in _peers:
			var ws: WebSocketPeer = _peers[peer_id]
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				ws.send(spawn_msg)

	# Broadcast projectile despawn events from this tick's advance().
	for despawn in despawns:
		if despawn["reason"] == ProjectileEntity.DespawnReason.REJECTED:
			continue  # client-only reason, never broadcast
		var despawn_tick_age_ms: int = clampi(broadcast_time_ms - advance_start_ms, 0, 255)
		var despawn_msg: PackedByteArray = NetMessage.encode_projectile_despawned({
			"projectile_id": despawn["id"],
			"reason": despawn["reason"],
			"position": despawn["position"],
			"target_entity_id": despawn["target_entity_id"],
			"tick_age_ms": despawn_tick_age_ms,
		})
		for peer_id in _peers:
			var ws: WebSocketPeer = _peers[peer_id]
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				ws.send(despawn_msg)


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
	for enemy in _enemy_system.get_all_enemies():
		snap.enemy_entities[enemy.entity_id] = enemy.to_snapshot_data()
	return snap


func _on_enemy_died(event: Dictionary) -> void:
	_death_events.append(event)


func _record_snapshot_send(player_id: int, tick: int) -> void:
	if not _pending_snapshot_sends.has(player_id):
		_pending_snapshot_sends[player_id] = {}
	_pending_snapshot_sends[player_id][tick] = Time.get_ticks_msec()


func _record_snapshot_ack(player_id: int, tick: int) -> void:
	if not _pending_snapshot_sends.has(player_id):
		return
	var sends: Dictionary = _pending_snapshot_sends[player_id]
	if not sends.has(tick):
		return
	var send_ms: int = sends[tick]
	var rtt_ms: int = Time.get_ticks_msec() - send_ms
	sends.erase(tick)

	if not _rtt_samples.has(player_id):
		_rtt_samples[player_id] = []
	var samples: Array = _rtt_samples[player_id]
	samples.append(rtt_ms)
	while samples.size() > _RTT_SAMPLE_WINDOW:
		samples.pop_front()


func get_rtt_ms(player_id: int) -> int:
	if not _rtt_samples.has(player_id):
		return 0
	var samples: Array = _rtt_samples[player_id]
	if samples.is_empty():
		return 0
	var sum: int = 0
	for s in samples:
		sum += s
	return sum / samples.size()


func get_enemy_system() -> EnemySystem:
	return _enemy_system
