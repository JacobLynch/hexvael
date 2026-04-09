class_name InputBuffer

# player_id -> Array of input dicts
var _buffers: Dictionary = {}
# player_id -> Dictionary of seen sequence numbers (for dedup)
var _seen_seqs: Dictionary = {}


func add_input(player_id: int, input: Dictionary) -> void:
	var seq: int = input["input_seq"]
	if not _seen_seqs.has(player_id):
		_seen_seqs[player_id] = {}
	if _seen_seqs[player_id].has(seq):
		return  # duplicate
	_seen_seqs[player_id][seq] = true
	if not _buffers.has(player_id):
		_buffers[player_id] = []
	_buffers[player_id].append(input)


func drain_inputs_for_player(player_id: int) -> Array:
	if not _buffers.has(player_id):
		return []
	var inputs: Array = _buffers[player_id]
	inputs.sort_custom(func(a, b): return a["input_seq"] < b["input_seq"])
	_buffers[player_id] = []
	_seen_seqs[player_id] = {}
	return inputs


func remove_player(player_id: int) -> void:
	_buffers.erase(player_id)
	_seen_seqs.erase(player_id)
