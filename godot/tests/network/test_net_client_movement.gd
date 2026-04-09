extends GutTest
## Regression tests for local client movement smoothness.
## Verifies prediction interpolation (between two physics-valid predicted positions)
## and visual offset continuity during server reconciliation.

var NetClientScript = preload("res://simulation/network/net_client.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
var SnapshotScript = preload("res://simulation/network/snapshot.gd")

var _client: NetClient
var _player: PlayerEntity

const TICK_S: float = MessageTypes.TICK_INTERVAL_MS / 1000.0


func before_each():
	_player = PlayerEntityScene.instantiate()
	add_child_autofree(_player)
	_player.initialize(1, Vector2(100.0, 100.0))

	_client = NetClientScript.new()
	add_child_autofree(_client)
	_client._local_player_id = 1
	_client.set_local_player(_player)


# --- Prediction interpolation basics ---


func test_set_local_player_initializes_predicted_positions():
	assert_eq(_client._prev_predicted_pos, Vector2(100.0, 100.0))
	assert_eq(_client._curr_predicted_pos, Vector2(100.0, 100.0))


func test_interpolation_at_t0_returns_prev_position():
	_client._prev_predicted_pos = Vector2(100.0, 100.0)
	_client._curr_predicted_pos = Vector2(110.0, 100.0)
	_client._prediction_time = 0.0

	var pos = _client.get_local_player_position()
	assert_eq(pos, Vector2(100.0, 100.0),
		"At t=0, should show previous predicted position")


func test_interpolation_at_half_tick_returns_midpoint():
	_client._prev_predicted_pos = Vector2(100.0, 100.0)
	_client._curr_predicted_pos = Vector2(110.0, 100.0)
	_client._prediction_time = TICK_S / 2.0

	var pos = _client.get_local_player_position()
	assert_almost_eq(pos.x, 105.0, 0.01,
		"At t=0.5, should be halfway between prev and curr")
	assert_almost_eq(pos.y, 100.0, 0.01)


func test_interpolation_at_full_tick_returns_curr_position():
	_client._prev_predicted_pos = Vector2(100.0, 100.0)
	_client._curr_predicted_pos = Vector2(110.0, 100.0)
	_client._prediction_time = TICK_S

	var pos = _client.get_local_player_position()
	assert_almost_eq(pos.x, 110.0, 0.01,
		"At t=1.0, should show current predicted position")


func test_interpolation_clamps_past_tick_boundary():
	# If prediction_time overshoots (e.g., frame timing), t should clamp to 1.0
	_client._prev_predicted_pos = Vector2(100.0, 100.0)
	_client._curr_predicted_pos = Vector2(110.0, 100.0)
	_client._prediction_time = TICK_S * 1.5  # 50% past tick

	var pos = _client.get_local_player_position()
	assert_almost_eq(pos.x, 110.0, 0.01,
		"Should clamp to curr position, not overshoot")


func test_interpolation_stationary_player():
	_client._prev_predicted_pos = Vector2(100.0, 100.0)
	_client._curr_predicted_pos = Vector2(100.0, 100.0)
	_client._prediction_time = TICK_S / 2.0

	var pos = _client.get_local_player_position()
	assert_eq(pos, Vector2(100.0, 100.0),
		"Stationary player should stay in place regardless of time")


func test_interpolation_returns_null_without_player():
	_client._local_player = null
	assert_null(_client.get_local_player_position(),
		"Should return null when no local player is set")


# --- Visual offset and reconciliation ---


func _make_snapshot(player_id: int, pos: Vector2, last_seq: int) -> Snapshot:
	var snap = SnapshotScript.new()
	snap.tick = 1
	snap.entities[player_id] = {
		"entity_id": player_id,
		"position": pos,
		"flags": 0,
		"last_input_seq": last_seq,
	}
	return snap


func test_reconciliation_visual_continuity_no_pending():
	# Setup: prev=(100,100), curr=(110,100), halfway through tick
	_client._prev_predicted_pos = Vector2(100.0, 100.0)
	_client._curr_predicted_pos = Vector2(110.0, 100.0)
	_client._prediction_time = TICK_S / 2.0
	_client._visual_offset = Vector2.ZERO
	_client._pending_inputs = []

	# View is showing: lerp(100, 110, 0.5) + offset = (105, 100)
	var visual_before = Vector2(105.0, 100.0)

	# Server says player is at (108, 100), all inputs acknowledged
	var snap = _make_snapshot(1, Vector2(108.0, 100.0), 999)
	_client._reconcile_local_player(snap)

	# After reconciliation with no pending: prev=curr=server_pos=(108,100)
	# View will show: prev + offset = (108, 100) + offset
	# For continuity: (108, 100) + offset = (105, 100)
	var view_pos = _client._prev_predicted_pos + _client._visual_offset

	assert_almost_eq(view_pos.x, visual_before.x, 0.01,
		"Visual position should be continuous through reconciliation")
	assert_almost_eq(view_pos.y, visual_before.y, 0.01)


func test_reconciliation_large_correction_snaps():
	_client._prev_predicted_pos = Vector2(100.0, 100.0)
	_client._curr_predicted_pos = Vector2(100.0, 100.0)
	_client._prediction_time = 0.0
	_client._visual_offset = Vector2.ZERO
	_client._pending_inputs = []

	# Server says player is 60px away (> SNAP_THRESHOLD of 50)
	var snap = _make_snapshot(1, Vector2(160.0, 100.0), 999)
	_client._reconcile_local_player(snap)

	assert_eq(_client._visual_offset, Vector2.ZERO,
		"Large corrections should snap, not blend")


func test_reconciliation_tiny_correction_zeroes_offset():
	_client._prev_predicted_pos = Vector2(100.0, 100.0)
	_client._curr_predicted_pos = Vector2(100.0, 100.0)
	_client._prediction_time = 0.0
	_client._visual_offset = Vector2.ZERO
	_client._pending_inputs = []

	var snap = _make_snapshot(1, Vector2(100.005, 100.0), 999)
	_client._reconcile_local_player(snap)

	assert_eq(_client._visual_offset, Vector2.ZERO,
		"Sub-pixel corrections should be zeroed, not blended")


func test_visual_offset_preserved_not_doubled():
	# Existing offset from prior reconciliation, no prediction error this time
	_client._prev_predicted_pos = Vector2(100.0, 100.0)
	_client._curr_predicted_pos = Vector2(100.0, 100.0)
	_client._prediction_time = 0.0
	_client._visual_offset = Vector2(3.0, 0.0)
	_client._pending_inputs = []

	# Server agrees with player position
	var snap = _make_snapshot(1, Vector2(100.0, 100.0), 999)
	_client._reconcile_local_player(snap)

	# visual_before = lerp(100,100, 0) + (3,0) = (103, 100)
	# After: prev = (100, 100), offset should be (3, 0)
	assert_almost_eq(_client._visual_offset.x, 3.0, 0.01,
		"Offset should be preserved correctly, not doubled")


func test_blend_visual_offset_converges_to_zero():
	_client._visual_offset = Vector2(10.0, 0.0)

	for i in range(60):
		_client.blend_visual_offset(1.0 / 60.0)

	assert_eq(_client._visual_offset, Vector2.ZERO,
		"Visual offset should converge to zero after sufficient blending")


# --- Prediction position rotation (wall-safety regression) ---


func test_interpolation_between_identical_positions_stays_put():
	# When player is against a wall, both prev and curr are at the wall.
	# Interpolation should stay exactly at the wall, not push through.
	_client._prev_predicted_pos = Vector2(50.0, 100.0)
	_client._curr_predicted_pos = Vector2(50.0, 100.0)
	_client._prediction_time = TICK_S * 0.75

	var pos = _client.get_local_player_position()
	assert_eq(pos, Vector2(50.0, 100.0),
		"Against a wall, interpolation between identical positions should stay put")
