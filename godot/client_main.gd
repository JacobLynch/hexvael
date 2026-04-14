extends Node

var _net_client: NetClient
var _input_provider: InputProvider
var _world_view: Node2D
var _connection_ui: CanvasLayer
var _local_player: PlayerEntity = null
var _remote_proxies: Dictionary = {}  # player_id -> StaticBody2D
var _enemy_proxies: Dictionary = {}  # entity_id -> StaticBody2D
var _projectile_system: ProjectileSystem = null
var _projectile_view: ProjectileView = null
var _projectile_effects: ProjectileEffects = null
var _dev_mode: bool = false
var _auto_fire: bool = false
var _auto_fire_timer: float = 0.0
const AUTO_FIRE_INTERVAL: float = 0.3


func _ready():
	_net_client = $NetClient
	_world_view = $WorldView
	_connection_ui = $ConnectionUI
	_input_provider = KeyboardMouseInputProvider.new(get_viewport())

	# Client-side projectile simulation — advances predictions and handles
	# server reconciliation messages. Uses empty player/enemy arrays so only
	# wall collisions are checked (remote entity positions are interpolated
	# and don't match the server's authoritative positions).
	_projectile_system = ProjectileSystem.new()
	add_child(_projectile_system)
	var arena := get_node_or_null("Arena")
	if arena != null:
		_projectile_system.set_walls(WallGeometry.extract_aabbs(arena))
	else:
		push_warning("client_main: Arena node not found — projectiles will have no wall collisions")
	_net_client.set_projectile_system(_projectile_system)

	# View-layer projectile renderer — instanced from code so it can reference
	# the dynamically added _projectile_system node directly without a NodePath.
	# Assign _projectile_system BEFORE add_child so ProjectileView._ready() sees it.
	_projectile_view = ProjectileView.new()
	_projectile_view._projectile_system = _projectile_system
	_projectile_view._net_client = _net_client
	add_child(_projectile_view)

	# Projectile effects system — spawns muzzle flashes, trails, and impacts.
	_projectile_effects = ProjectileEffects.new()
	_projectile_effects.initialize(_projectile_system)
	# Register frost bolt effects
	var frost_effect_params = preload("res://shared/projectiles/frost_bolt_effect_params.tres")
	_projectile_effects.register_effect_params(ProjectileType.Id.FROST_BOLT, frost_effect_params)
	add_child(_projectile_effects)
	_projectile_effects.set_net_client(_net_client)

	_world_view.initialize(_net_client)
	_connection_ui.connect_requested.connect(_on_connect_requested)
	_net_client.connected.connect(_on_connected)
	_net_client.disconnected.connect(_on_disconnected)
	_net_client.player_joined.connect(_on_player_joined)
	_net_client.player_left.connect(_on_player_left)
	_net_client.snapshot_received.connect(_on_snapshot)

	# Auto-connect if CLI args provided: -- --server localhost --port 9050 --dev
	var address := ""
	var port := 0
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--server" and i + 1 < args.size():
			address = args[i + 1]
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
		if args[i] == "--dev":
			_dev_mode = true
			print("Dev mode enabled — F2 toggles auto-fire")
	if not address.is_empty():
		if port <= 0:
			port = 9050
		_on_connect_requested(address, port)


func _on_connect_requested(address: String, port: int):
	var err = _net_client.connect_to_server(address, port)
	if err != OK:
		_connection_ui.set_status("Connection failed")


func _on_connected(player_id: int):
	_connection_ui.set_connected()

	# Spawn local player entity for prediction (simulation layer, no visuals)
	var player_scene = preload("res://simulation/entities/player_entity.tscn")
	_local_player = player_scene.instantiate()
	_local_player.initialize(player_id, MessageTypes.SPAWN_POSITION)
	add_child(_local_player)
	_net_client.set_local_player(_local_player)
	_net_client.enemy_snapshot_updated.connect(_on_enemy_snapshot)

	# Now that we know the local player id, tell the projectile view so it can
	# colour-code local vs remote projectiles differently.
	if _projectile_view != null:
		_projectile_view.set_local_player_id(player_id)


func _process(delta: float):
	if _net_client.is_server_connected():
		var player_pos = _net_client.get_local_player_position()
		if player_pos == null:
			player_pos = Vector2.ZERO
		_input_provider.poll(player_pos)
		_net_client.input_direction = _input_provider.move_direction
		_net_client.aim_direction = _input_provider.aim_direction
		if _input_provider.consume_dodge_press():
			_net_client.dodge_pressed_latch = true
		if _input_provider.consume_fire_press():
			_net_client.fire_pressed_latch = true
			# Spawn muzzle flash immediately at player position for instant feedback.
			# This happens before projectile spawn so the flash appears at the player,
			# not offset to the projectile origin.
			if _local_player != null and _projectile_effects != null:
				var aim_dir: Vector2 = _local_player.aim_direction
				_projectile_effects.spawn_local_muzzle_flash(
					_local_player.position, aim_dir, ProjectileType.Id.FROST_BOLT)

			# Spawn a predicted projectile immediately for responsive feel.
			# The input_seq used here must match what _send_input will stamp on
			# the FIRE packet: _input_seq increments at the START of _send_input,
			# so the next sent seq is _input_seq + 1.
			if _local_player != null and _projectile_system != null:
				ProjectileSpawnRouter.handle_fire(_local_player, {
					"action_flags": MessageTypes.InputActionFlags.FIRE,
					"input_seq": _net_client._input_seq + 1,
				}, _projectile_system, {"authoritative": false})

		# Tick cooldowns and advance client-side projectile simulation.
		# Empty player/enemy arrays: client checks walls only.
		if _projectile_system != null:
			_projectile_system.tick_cooldowns(delta)
			_projectile_system._current_rtt_ms = _net_client.get_rtt_ms()
			_projectile_system.advance(delta, [], [])

		_update_remote_proxies()
		_update_enemy_proxies()


func _unhandled_input(event: InputEvent) -> void:
	if not _dev_mode:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_auto_fire = not _auto_fire
		if _auto_fire:
			_auto_fire_timer = 0.0  # Fire immediately on enable
			print("Auto-fire ON")
		else:
			print("Auto-fire OFF")


func _on_player_joined(player_id: int, spawn_position: Vector2):
	_add_remote_proxy(player_id, spawn_position)


func _on_player_left(player_id: int):
	_remove_remote_proxy(player_id)


func _on_snapshot(_tick: int, entities: Array):
	for ent in entities:
		var eid: int = ent["entity_id"]
		if eid == _net_client.get_local_player_id():
			continue
		if ent.get("flags", 0) & MessageTypes.EntityFlags.REMOVED:
			_remove_remote_proxy(eid)
		elif not _remote_proxies.has(eid):
			_add_remote_proxy(eid, ent["position"])


func _on_disconnected():
	_connection_ui.set_disconnected()
	if _local_player != null:
		_local_player.queue_free()
		_local_player = null
	for proxy in _remote_proxies.values():
		proxy.queue_free()
	_remote_proxies.clear()
	for proxy in _enemy_proxies.values():
		proxy.queue_free()
	_enemy_proxies.clear()


func _add_remote_proxy(player_id: int, pos: Vector2) -> void:
	if player_id == _net_client.get_local_player_id():
		return
	if _remote_proxies.has(player_id):
		return
	var body = StaticBody2D.new()
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(12, 12)  # Must match PlayerEntity collision shape
	collision.shape = shape
	body.add_child(collision)
	body.position = pos
	add_child(body)
	_remote_proxies[player_id] = body


func _remove_remote_proxy(player_id: int) -> void:
	if _remote_proxies.has(player_id):
		_remote_proxies[player_id].queue_free()
		_remote_proxies.erase(player_id)


func _update_remote_proxies() -> void:
	for player_id in _remote_proxies:
		var pos = _net_client.get_interpolated_position(player_id)
		if pos != null:
			_remote_proxies[player_id].position = pos


func _on_enemy_snapshot(enemy_entities: Dictionary) -> void:
	for eid in enemy_entities:
		var ent = enemy_entities[eid]
		if ent["state"] == 0:  # SPAWNING — no collision
			continue
		if not _enemy_proxies.has(eid):
			_add_enemy_proxy(eid, ent["position"])

	for eid in _enemy_proxies.keys():
		if not enemy_entities.has(eid) or enemy_entities[eid]["state"] == 0:
			_remove_enemy_proxy(eid)


func _add_enemy_proxy(entity_id: int, pos: Vector2) -> void:
	if _enemy_proxies.has(entity_id):
		return
	var body = StaticBody2D.new()
	body.collision_layer = 4  # layer 3 (enemy)
	body.collision_mask = 0   # proxies don't detect anything
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(12, 12)
	collision.shape = shape
	body.add_child(collision)
	body.position = pos
	add_child(body)
	_enemy_proxies[entity_id] = body


func _remove_enemy_proxy(entity_id: int) -> void:
	if _enemy_proxies.has(entity_id):
		_enemy_proxies[entity_id].queue_free()
		_enemy_proxies.erase(entity_id)


func _update_enemy_proxies() -> void:
	for eid in _enemy_proxies:
		var data = _net_client.get_interpolated_enemy(eid)
		if data != null:
			_enemy_proxies[eid].position = data["position"]
