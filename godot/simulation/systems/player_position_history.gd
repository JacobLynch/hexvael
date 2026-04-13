class_name PlayerPositionHistory
extends RefCounted

const MAX_SAMPLES = 32

var _samples_per_player: Dictionary = {}  # player_id -> Array[{tick: int, pos: Vector2}]


func record(player_id: int, tick: int, pos: Vector2) -> void:
	if not _samples_per_player.has(player_id):
		_samples_per_player[player_id] = []
	var samples: Array = _samples_per_player[player_id]
	samples.append({"tick": tick, "pos": pos})
	while samples.size() > MAX_SAMPLES:
		samples.pop_front()


func lookup(player_id: int, target_tick: int) -> Vector2:
	if not _samples_per_player.has(player_id):
		return Vector2.ZERO
	var samples: Array = _samples_per_player[player_id]
	if samples.is_empty():
		return Vector2.ZERO
	if target_tick <= samples[0]["tick"]:
		return samples[0]["pos"]
	if target_tick >= samples[-1]["tick"]:
		return samples[-1]["pos"]
	# Linear scan — 32 samples max, no need for binary search
	var best = samples[0]
	for s in samples:
		if s["tick"] <= target_tick:
			best = s
		else:
			break
	return best["pos"]


func drop_player(player_id: int) -> void:
	_samples_per_player.erase(player_id)
