extends Node

var _net_client: NetClient
var _world_view: Node2D
var _connection_ui: CanvasLayer
var _local_player: PlayerEntity = null
var _remote_proxies: Dictionary = {}  # player_id -> StaticBody2D


func _ready():
	_net_client = $NetClient
	_world_view = $WorldView
	_connection_ui = $ConnectionUI

	_world_view.initialize(_net_client)
	_connection_ui.connect_requested.connect(_on_connect_requested)
	_net_client.connected.connect(_on_connected)
	_net_client.disconnected.connect(_on_disconnected)
	_net_client.player_joined.connect(_on_player_joined)
	_net_client.player_left.connect(_on_player_left)
	_net_client.snapshot_received.connect(_on_snapshot)

	# Auto-connect if CLI args provided: -- --server localhost --port 9050
	var address := ""
	var port := 0
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--server" and i + 1 < args.size():
			address = args[i + 1]
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
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


func _process(_delta: float):
	if _net_client.is_server_connected():
		_net_client.input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		_update_remote_proxies()


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
