extends Node

var _net_client: NetClient
var _world_view: Node2D
var _connection_ui: CanvasLayer
var _local_player: PlayerEntity = null


func _ready():
	_net_client = $NetClient
	_world_view = $WorldView
	_connection_ui = $ConnectionUI

	_world_view.initialize(_net_client)
	_connection_ui.connect_requested.connect(_on_connect_requested)
	_net_client.connected.connect(_on_connected)
	_net_client.disconnected.connect(_on_disconnected)


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


func _on_disconnected():
	_connection_ui.set_disconnected()
	if _local_player != null:
		_local_player.queue_free()
		_local_player = null
