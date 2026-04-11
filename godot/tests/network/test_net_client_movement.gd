extends GutTest
## Regression tests for local client movement smoothness.
## Verifies frame-rate prediction, visual offset continuity, framerate-independent
## blend, remote extrapolation past t=1.0, and reconciliation correctness.

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


func _make_snapshot(player_id: int, pos: Vector2, last_seq: int,
		velocity: Vector2 = Vector2.ZERO, aim: Vector2 = Vector2.RIGHT,
		state: int = 0, dodge_tr: float = 0.0) -> Snapshot:
	var snap = SnapshotScript.new()
	snap.tick = 1
	snap.entities[player_id] = {
		"entity_id": player_id,
		"position": pos,
		"flags": 0,
		"last_input_seq": last_seq,
		"velocity": velocity,
		"aim_direction": aim,
		"state": state,
		"dodge_time_remaining": dodge_tr,
	}
	return snap


# --- Frame-rate prediction basics ---


func test_get_local_player_position_returns_current_position():
	_player.position = Vector2(150.0, 200.0)
	var pos = _client.get_local_player_position()
	assert_eq(pos, Vector2(150.0, 200.0),
		"get_local_player_position should return player.position directly")


func test_interpolation_returns_null_without_player():
	_client._local_player = null
	assert_null(_client.get_local_player_position(),
		"Should return null when no local player is set")


# --- Visual offset and reconciliation ---


func test_reconciliation_visual_continuity_no_pending():
	# Player predicted to (110, 100) via frame-rate movement
	_player.position = Vector2(110.0, 100.0)
	_client._visual_offset = Vector2.ZERO
	_client._pending_inputs = []

	var visual_before = _player.position + _client._visual_offset  # (110, 100)

	# Server says player is at (108, 100), all inputs acknowledged
	var snap = _make_snapshot(1, Vector2(108.0, 100.0), 999)
	_client._reconcile_local_player(snap)

	# After reconciliation: player.position = (108, 100)
	# offset should bridge the gap: (110, 100) - (108, 100) = (2, 0)
	var view_pos = _player.position + _client._visual_offset

	assert_almost_eq(view_pos.x, visual_before.x, 0.01,
		"Visual position should be continuous through reconciliation")
	assert_almost_eq(view_pos.y, visual_before.y, 0.01)


func test_reconciliation_large_correction_snaps():
	_player.position = Vector2(100.0, 100.0)
	_client._visual_offset = Vector2.ZERO
	_client._pending_inputs = []

	# Server says player is 60px away — beyond SNAP_THRESHOLD
	var snap = _make_snapshot(1, Vector2(160.0, 100.0), 999)
	_client._reconcile_local_player(snap)

	assert_eq(_client._visual_offset, Vector2.ZERO,
		"Large corrections should snap, not blend")


func test_reconciliation_tiny_correction_zeroes_offset():
	_player.position = Vector2(100.0, 100.0)
	_client._visual_offset = Vector2.ZERO
	_client._pending_inputs = []

	# Server says player is 0.005px away — sub-pixel
	var snap = _make_snapshot(1, Vector2(100.005, 100.0), 999)
	_client._reconcile_local_player(snap)

	assert_eq(_client._visual_offset, Vector2.ZERO,
		"Sub-pixel corrections should be zeroed, not blended")


func test_visual_offset_preserved_not_doubled():
	_player.position = Vector2(100.0, 100.0)
	_client._visual_offset = Vector2(3.0, 0.0)
	_client._pending_inputs = []

	# Server agrees with prediction — no correction needed
	var snap = _make_snapshot(1, Vector2(100.0, 100.0), 999)
	_client._reconcile_local_player(snap)

	# visual_before = (100,100) + (3,0) = (103, 100)
	# After: player.position = (100,100), offset = (103,100) - (100,100) = (3, 0)
	assert_almost_eq(_client._visual_offset.x, 3.0, 0.01,
		"Offset should be preserved correctly, not doubled")


func test_reconciliation_with_existing_offset():
	# Player predicted to (110, 100), already has offset from previous reconciliation
	_player.position = Vector2(110.0, 100.0)
	_client._visual_offset = Vector2(2.0, 0.0)
	_client._pending_inputs = []

	# visual_before = (110, 100) + (2, 0) = (112, 100)
	# Server says (108, 100)
	var snap = _make_snapshot(1, Vector2(108.0, 100.0), 999)
	_client._reconcile_local_player(snap)

	# After: player.position = (108, 100)
	# offset = (112, 100) - (108, 100) = (4, 0)
	var view_pos = _player.position + _client._visual_offset

	assert_almost_eq(view_pos.x, 112.0, 0.01,
		"Reconciliation should preserve visual continuity including existing offset")


# --- Framerate-independent blend (exponential decay) ---


func test_blend_visual_offset_converges_to_zero():
	_client._visual_offset = Vector2(10.0, 0.0)

	for i in range(60):
		_client.blend_visual_offset(1.0 / 60.0)

	assert_eq(_client._visual_offset, Vector2.ZERO,
		"Visual offset should converge to zero after sufficient blending")


func test_blend_is_framerate_independent():
	# Blend at 60fps for 100ms vs 120fps for 100ms should produce same result
	var offset_60 = Vector2(20.0, 0.0)
	var offset_120 = Vector2(20.0, 0.0)

	# Simulate 60fps for 100ms (6 frames)
	for i in range(6):
		offset_60 *= exp(-NetClient.BLEND_SPEED * (1.0 / 60.0))

	# Simulate 120fps for 100ms (12 frames)
	for i in range(12):
		offset_120 *= exp(-NetClient.BLEND_SPEED * (1.0 / 120.0))

	assert_almost_eq(offset_60.x, offset_120.x, 0.01,
		"Exponential decay should give same result at different framerates")


# --- Remote player interpolation + extrapolation ---


func test_remote_interpolation_normal_range():
	_client._snapshot_prev = SnapshotScript.new()
	_client._snapshot_prev.tick = 1
	_client._snapshot_prev.entities[2] = {
		"entity_id": 2, "position": Vector2(200.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	_client._snapshot_curr = SnapshotScript.new()
	_client._snapshot_curr.tick = 2
	_client._snapshot_curr.entities[2] = {
		"entity_id": 2, "position": Vector2(210.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	_client._snapshot_time = TICK_S / 2.0

	var pos = _client.get_interpolated_position(2)
	assert_almost_eq(pos.x, 205.0, 0.01,
		"Remote player should interpolate normally at t=0.5")


func test_remote_extrapolation_past_tick():
	# When snapshot is late, remote should mildly extrapolate instead of freezing
	_client._snapshot_prev = SnapshotScript.new()
	_client._snapshot_prev.tick = 1
	_client._snapshot_prev.entities[2] = {
		"entity_id": 2, "position": Vector2(200.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	_client._snapshot_curr = SnapshotScript.new()
	_client._snapshot_curr.tick = 2
	_client._snapshot_curr.entities[2] = {
		"entity_id": 2, "position": Vector2(210.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	# 20ms past tick boundary (network jitter)
	_client._snapshot_time = TICK_S + 0.020

	var pos = _client.get_interpolated_position(2)

	# Should extrapolate past 210, not clamp at 210
	assert_gt(pos.x, 210.0,
		"Remote player should extrapolate past curr when snapshot is late")


func test_remote_extrapolation_capped_at_max():
	_client._snapshot_prev = SnapshotScript.new()
	_client._snapshot_prev.tick = 1
	_client._snapshot_prev.entities[2] = {
		"entity_id": 2, "position": Vector2(200.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	_client._snapshot_curr = SnapshotScript.new()
	_client._snapshot_curr.tick = 2
	_client._snapshot_curr.entities[2] = {
		"entity_id": 2, "position": Vector2(210.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	# Way past tick boundary
	_client._snapshot_time = TICK_S * 5.0

	var pos = _client.get_interpolated_position(2)

	# t capped at MAX_REMOTE_INTERP (1.5): lerp(200, 210, 1.5) = 215
	var max_pos = Vector2(200.0, 100.0).lerp(Vector2(210.0, 100.0), NetClient.MAX_REMOTE_INTERP)
	assert_almost_eq(pos.x, max_pos.x, 0.01,
		"Remote extrapolation should cap at MAX_REMOTE_INTERP")


func test_remote_extrapolation_uses_snapshot_velocity():
	# Snapshot velocity (400 px/s) differs from positional delta (10px/tick = 200 px/s).
	# At t = 1.4, extra_time = 0.4 * tick_interval = 0.02s.
	# Velocity-based: 110 + 400 * 0.02 = 118.
	# Delta-based:    110 + 200 * 0.02 = 114.
	# Extrapolation must use snapshot velocity, not re-derive from positional delta.
	var net = NetClientScript.new()
	add_child_autofree(net)

	var prev = SnapshotScript.new()
	prev.tick = 1
	prev.entities[2] = {
		"entity_id": 2, "position": Vector2(100.0, 0.0), "flags": 0, "last_input_seq": 0,
		"velocity": Vector2.ZERO, "aim_direction": Vector2.RIGHT,
		"state": 0, "dodge_time_remaining": 0.0,
	}
	var curr = SnapshotScript.new()
	curr.tick = 2
	curr.entities[2] = {
		"entity_id": 2, "position": Vector2(110.0, 0.0), "flags": 0, "last_input_seq": 0,
		"velocity": Vector2(400.0, 0.0), "aim_direction": Vector2.RIGHT,
		"state": 0, "dodge_time_remaining": 0.0,
	}

	net._snapshot_prev = prev
	net._snapshot_curr = curr
	# t = 1.4 → into extrapolation branch (t > 1.0)
	net._snapshot_time = TICK_S * 1.4

	var result = net.get_interpolated_position(2)
	# Expected: 110 + 400 * (0.4 * TICK_S) = 110 + 400 * 0.02 = 118.0
	assert_almost_eq(result.x, 118.0, 0.5,
		"Extrapolation must use snapshot velocity (400 px/s) not positional delta (200 px/s)")
