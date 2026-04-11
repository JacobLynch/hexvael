class_name MovementSystem
extends Node

# player_id -> PlayerEntity
var _players: Dictionary = {}


func register_player(player: PlayerEntity) -> void:
	_players[player.player_id] = player


func unregister_player(player_id: int) -> void:
	_players.erase(player_id)


func has_player(player_id: int) -> bool:
	return _players.has(player_id)


func get_player(player_id: int) -> PlayerEntity:
	return _players.get(player_id)


func process_inputs_for_player(player_id: int, inputs: Array) -> void:
	if not _players.has(player_id):
		return
	var player: PlayerEntity = _players[player_id]
	for input in inputs:
		player.apply_input(input)


func advance_all(dt: float) -> void:
	for player_id in _players:
		_players[player_id].advance(dt)
