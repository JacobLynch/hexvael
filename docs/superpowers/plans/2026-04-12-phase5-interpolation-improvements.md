# Phase 5 Interpolation Improvements

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve remote entity interpolation to handle network jitter better by extending extrapolation window, adding a 3-snapshot buffer, and implementing intentional buffer delay.

**Architecture:** Currently, `net_client.gd` stores only 2 snapshots (`_snapshot_prev`, `_snapshot_curr`) and interpolates with no buffer delay. We'll extend to a 3-snapshot ring buffer, add a ~2-tick buffer delay so we're always interpolating between known positions rather than extrapolating, and extend `MAX_REMOTE_INTERP` for jitter tolerance.

**Tech Stack:** GDScript, GUT test framework

**Test command:**
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdline.gd -gtest=res://tests/network/test_net_client_movement.gd
```

---

## File Structure

| File | Responsibility |
|------|----------------|
| `godot/simulation/network/net_client.gd` | All interpolation logic, snapshot buffering |
| `godot/tests/network/test_net_client_movement.gd` | Interpolation and extrapolation tests |

---

## Task 1: Extend Extrapolation Window (Quick Win)

**Files:**
- Modify: `godot/simulation/network/net_client.gd:40`
- Modify: `godot/tests/network/test_net_client_movement.gd`

This is a one-line change with minimal risk. Extends extrapolation from 0.5 ticks (~16ms) to 2 ticks (~66ms) to handle typical network jitter.

- [ ] **Step 1: Update the existing extrapolation cap test to expect new value**

In `godot/tests/network/test_net_client_movement.gd`, find `test_remote_extrapolation_capped_at_max` and update the expected calculation. The test currently expects `MAX_REMOTE_INTERP = 1.5`. Change to expect `3.0`.

```gdscript
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

	# t capped at MAX_REMOTE_INTERP (3.0): extrapolation = curr + vel * 2 ticks
	# vel = (210-200)/TICK_S = 10/TICK_S px/s, extra_time = 2*TICK_S
	# result = 210 + (10/TICK_S) * 2*TICK_S = 210 + 20 = 230
	var expected_x: float = 210.0 + (10.0 / TICK_S) * (2.0 * TICK_S)
	assert_almost_eq(pos.x, expected_x, 0.01,
		"Remote extrapolation should cap at MAX_REMOTE_INTERP (3.0)")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdline.gd -gtest=res://tests/network/test_net_client_movement.gd::test_remote_extrapolation_capped_at_max
```

Expected: FAIL — current `MAX_REMOTE_INTERP = 1.5` produces 215, not 230.

- [ ] **Step 3: Change MAX_REMOTE_INTERP from 1.5 to 3.0**

In `godot/simulation/network/net_client.gd`, line 40:

```gdscript
# Max remote interpolation t — allows brief extrapolation past the latest snapshot
# to cover network jitter, preventing the freeze-then-jump stutter.
# 3.0 = up to 2 ticks of extrapolation (~66ms at 30Hz).
const MAX_REMOTE_INTERP: float = 3.0
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdline.gd -gtest=res://tests/network/test_net_client_movement.gd::test_remote_extrapolation_capped_at_max
```

Expected: PASS

- [ ] **Step 5: Run all movement tests to check for regressions**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdline.gd -gtest=res://tests/network/test_net_client_movement.gd
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add godot/simulation/network/net_client.gd godot/tests/network/test_net_client_movement.gd
git commit -m "$(cat <<'EOF'
net_client: extend extrapolation window from 0.5 to 2 ticks

MAX_REMOTE_INTERP 1.5 → 3.0. Allows ~66ms of extrapolation (up from
~16ms) to handle typical network jitter without freezing remote
entities.
EOF
)"
```

---

## Task 2: Add 3-Snapshot Ring Buffer

**Files:**
- Modify: `godot/simulation/network/net_client.gd:30-35, 189-237, 362-414`
- Modify: `godot/tests/network/test_net_client_movement.gd`

Replace `_snapshot_prev`/`_snapshot_curr` with a ring buffer of 3 snapshots. This provides resilience against single packet loss — with 3 snapshots, losing one still leaves 2 to interpolate between.

### Step 2.1: Add test for 3-snapshot buffer behavior

- [ ] **Step 1: Write failing test for 3-snapshot packet loss resilience**

Add to `godot/tests/network/test_net_client_movement.gd`:

```gdscript
func test_snapshot_buffer_survives_single_packet_loss():
	# Simulate receiving snapshots 1, 2, 4 (packet 3 lost)
	# With 3-snapshot buffer, we should still have snap 1 and 2 to interpolate
	
	# Receive snapshot 1
	var snap1 = {"tick": 1, "entities": [
		{"entity_id": 2, "position": Vector2(100.0, 100.0), "flags": 0, "last_input_seq": 0,
		 "velocity": Vector2.ZERO, "aim_direction": Vector2.RIGHT, "state": 0,
		 "dodge_time_remaining": 0.0, "collision_count": 0, "last_collision_normal": Vector2.ZERO}
	], "enemy_entities": []}
	_client._apply_full_snapshot(snap1)
	
	# Receive snapshot 2
	var snap2 = {"tick": 2, "entities": [
		{"entity_id": 2, "position": Vector2(110.0, 100.0), "flags": 0, "last_input_seq": 0,
		 "velocity": Vector2.ZERO, "aim_direction": Vector2.RIGHT, "state": 0,
		 "dodge_time_remaining": 0.0, "collision_count": 0, "last_collision_normal": Vector2.ZERO}
	]}
	_client._apply_delta_snapshot(snap2)
	
	# Snapshot 3 is lost — receive snapshot 4
	var snap4 = {"tick": 4, "entities": [
		{"entity_id": 2, "position": Vector2(130.0, 100.0), "flags": 0, "last_input_seq": 0,
		 "velocity": Vector2.ZERO, "aim_direction": Vector2.RIGHT, "state": 0,
		 "dodge_time_remaining": 0.0, "collision_count": 0, "last_collision_normal": Vector2.ZERO}
	]}
	_client._apply_delta_snapshot(snap4)
	
	# Buffer should have 3 snapshots: ticks 1, 2, 4
	assert_eq(_client.get_snapshot_buffer_size(), 3,
		"Buffer should hold 3 snapshots after receiving 3")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdline.gd -gtest=res://tests/network/test_net_client_movement.gd::test_snapshot_buffer_survives_single_packet_loss
```

Expected: FAIL — `get_snapshot_buffer_size()` method doesn't exist.

### Step 2.2: Implement snapshot ring buffer

- [ ] **Step 3: Replace _snapshot_prev/_snapshot_curr with ring buffer**

In `godot/simulation/network/net_client.gd`, replace lines 30-35:

```gdscript
# Interpolation state: ring buffer of recent snapshots for remote entities
# 3 snapshots provides resilience against single packet loss
const SNAPSHOT_BUFFER_SIZE: int = 3
var _snapshot_buffer: Array = []  # Array of Snapshot, newest at end
var _snapshot_time: float = 0.0   # Time since newest snapshot arrived
var _enemy_prev: Dictionary = {}  # entity_id -> snapshot data
var _enemy_curr: Dictionary = {}  # entity_id -> snapshot data
```

- [ ] **Step 4: Add get_snapshot_buffer_size() helper**

Add after the variable declarations:

```gdscript
func get_snapshot_buffer_size() -> int:
	return _snapshot_buffer.size()
```

- [ ] **Step 5: Update _apply_full_snapshot to use ring buffer**

Replace `_apply_full_snapshot` function:

```gdscript
func _apply_full_snapshot(msg: Dictionary):
	var snap = Snapshot.new()
	snap.tick = msg["tick"]
	for ent in msg["entities"]:
		snap.entities[ent["entity_id"]] = ent
	
	# Reset buffer with this snapshot duplicated (need 2 for interpolation)
	_snapshot_buffer = [snap.duplicate_snapshot(), snap]
	_snapshot_time = 0.0
	_server_tick = msg["tick"]

	_reconcile_local_player(snap)
	_send_ack(msg["tick"])

	# Enemy entities
	_enemy_prev = {}
	_enemy_curr = {}
	for ent in msg.get("enemy_entities", []):
		var eid = ent["entity_id"]
		_enemy_prev[eid] = ent.duplicate()
		_enemy_curr[eid] = ent.duplicate()
	enemy_snapshot_updated.emit(_enemy_curr)

	snapshot_received.emit(snap.tick, msg["entities"])
```

- [ ] **Step 6: Update _apply_delta_snapshot to use ring buffer**

Replace `_apply_delta_snapshot` function:

```gdscript
func _apply_delta_snapshot(msg: Dictionary):
	if _snapshot_buffer.is_empty():
		return  # Need a full snapshot first

	# Create new snapshot by copying latest and applying delta
	var newest = _snapshot_buffer[-1]
	var snap = newest.duplicate_snapshot()
	snap.apply_delta(msg["tick"], msg["entities"])
	
	# Push to buffer, maintain max size
	_snapshot_buffer.append(snap)
	while _snapshot_buffer.size() > SNAPSHOT_BUFFER_SIZE:
		_snapshot_buffer.pop_front()
	
	_snapshot_time = 0.0
	_server_tick = msg["tick"]

	_reconcile_local_player(snap)
	_send_ack(msg["tick"])

	# Enemy delta
	_enemy_prev = _enemy_curr.duplicate()
	for ent in msg.get("enemy_entities", []):
		var eid: int = ent["entity_id"]
		if ent["state"] == MessageTypes.EnemyFlags.REMOVED:
			_enemy_curr.erase(eid)
		else:
			_enemy_curr[eid] = ent.duplicate()
	enemy_snapshot_updated.emit(_enemy_curr)

	snapshot_received.emit(snap.tick, msg["entities"])
```

- [ ] **Step 7: Run the new test**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdline.gd -gtest=res://tests/network/test_net_client_movement.gd::test_snapshot_buffer_survives_single_packet_loss
```

Expected: PASS

### Step 2.3: Update interpolation to use ring buffer

- [ ] **Step 8: Update get_interpolated_position to use buffer**

Replace `get_interpolated_position` function:

```gdscript
func get_interpolated_position(entity_id: int) -> Variant:
	if entity_id == _local_player_id:
		return null

	if _snapshot_buffer.size() < 2:
		return null
	
	# Use the two most recent snapshots for interpolation
	var snap_prev: Snapshot = _snapshot_buffer[-2]
	var snap_curr: Snapshot = _snapshot_buffer[-1]

	if not snap_curr.entities.has(entity_id):
		return null

	var curr = snap_curr.entities[entity_id]
	var curr_pos: Vector2 = curr["position"]

	if not snap_prev.entities.has(entity_id):
		return curr_pos

	var prev = snap_prev.entities[entity_id]
	var prev_pos: Vector2 = prev["position"]

	var tick_interval = MessageTypes.TICK_INTERVAL_MS / 1000.0
	var t = clampf(_snapshot_time / tick_interval, 0.0, MAX_REMOTE_INTERP)

	if t <= 1.0:
		# Within interpolation window — lerp between snapshots
		return prev_pos.lerp(curr_pos, t)
	else:
		# Extrapolate forward using current snapshot velocity.
		# Fall back to positional delta as implied velocity when the snapshot
		# does not carry an explicit velocity field.
		var snap_vel: Vector2 = curr.get("velocity", (curr_pos - prev_pos) / tick_interval)
		var extra_time = (t - 1.0) * tick_interval
		return curr_pos + snap_vel * extra_time
```

- [ ] **Step 9: Update get_interpolated_enemy to use buffer**

The enemy interpolation uses separate `_enemy_prev`/`_enemy_curr` which we're keeping. No change needed.

- [ ] **Step 10: Run all movement tests**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdline.gd -gtest=res://tests/network/test_net_client_movement.gd
```

Expected: All tests pass.

- [ ] **Step 11: Commit**

```bash
git add godot/simulation/network/net_client.gd godot/tests/network/test_net_client_movement.gd
git commit -m "$(cat <<'EOF'
net_client: replace 2-snapshot pair with 3-snapshot ring buffer

Provides resilience against single packet loss. With 3 snapshots, losing
one packet still leaves 2 known positions to interpolate between rather
than forcing extrapolation.
EOF
)"
```

---

## Task 3: Add Buffer Delay for Interpolation

**Files:**
- Modify: `godot/simulation/network/net_client.gd`
- Modify: `godot/tests/network/test_net_client_movement.gd`

Add a ~2-tick buffer delay so we're always rendering remote entities ~66ms behind real-time. This means we're almost always interpolating between known positions rather than extrapolating, which eliminates jitter-induced visual pops.

### Step 3.1: Add test for buffer delay

- [ ] **Step 1: Write failing test for buffer delay**

Add to `godot/tests/network/test_net_client_movement.gd`:

```gdscript
func test_buffer_delay_renders_behind_latest_snapshot():
	# With BUFFER_DELAY_TICKS = 2, when we have snapshots at t=1,2,3
	# and _snapshot_time = 0, we should be rendering at t=1 (2 ticks behind t=3)
	
	# Simulate receiving 3 snapshots
	var snap1 = {"tick": 1, "entities": [
		{"entity_id": 2, "position": Vector2(100.0, 100.0), "flags": 0, "last_input_seq": 0,
		 "velocity": Vector2.ZERO, "aim_direction": Vector2.RIGHT, "state": 0,
		 "dodge_time_remaining": 0.0, "collision_count": 0, "last_collision_normal": Vector2.ZERO}
	], "enemy_entities": []}
	_client._apply_full_snapshot(snap1)
	
	var snap2 = {"tick": 2, "entities": [
		{"entity_id": 2, "position": Vector2(110.0, 100.0), "flags": 0, "last_input_seq": 0,
		 "velocity": Vector2.ZERO, "aim_direction": Vector2.RIGHT, "state": 0,
		 "dodge_time_remaining": 0.0, "collision_count": 0, "last_collision_normal": Vector2.ZERO}
	]}
	_client._apply_delta_snapshot(snap2)
	
	var snap3 = {"tick": 3, "entities": [
		{"entity_id": 2, "position": Vector2(120.0, 100.0), "flags": 0, "last_input_seq": 0,
		 "velocity": Vector2.ZERO, "aim_direction": Vector2.RIGHT, "state": 0,
		 "dodge_time_remaining": 0.0, "collision_count": 0, "last_collision_normal": Vector2.ZERO}
	]}
	_client._apply_delta_snapshot(snap3)
	
	# Right after snap3 arrives, _snapshot_time = 0
	# With 2-tick buffer delay, we should render at the position from 2 ticks ago
	# snap1.position = 100, snap2.position = 110, snap3.position = 120
	# render_time = snap3.tick - 2 = tick 1, so position should be 100
	_client._snapshot_time = 0.0
	var pos = _client.get_interpolated_position(2)
	
	assert_almost_eq(pos.x, 100.0, 1.0,
		"With 2-tick buffer delay and _snapshot_time=0, should render at oldest snapshot")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdline.gd -gtest=res://tests/network/test_net_client_movement.gd::test_buffer_delay_renders_behind_latest_snapshot
```

Expected: FAIL — without buffer delay, pos.x will be ~120 (latest snapshot).

### Step 3.2: Implement buffer delay

- [ ] **Step 3: Add BUFFER_DELAY_TICKS constant**

In `godot/simulation/network/net_client.gd`, add after `SNAPSHOT_BUFFER_SIZE`:

```gdscript
const SNAPSHOT_BUFFER_SIZE: int = 3
const BUFFER_DELAY_TICKS: int = 2  # Render 2 ticks behind latest snapshot (~66ms at 30Hz)
```

- [ ] **Step 4: Update get_interpolated_position with buffer delay logic**

Replace `get_interpolated_position` function:

```gdscript
func get_interpolated_position(entity_id: int) -> Variant:
	if entity_id == _local_player_id:
		return null

	if _snapshot_buffer.size() < 2:
		return null
	
	var tick_interval = MessageTypes.TICK_INTERVAL_MS / 1000.0
	var newest_tick: int = _snapshot_buffer[-1].tick
	
	# Calculate render time: newest_tick minus buffer delay, plus elapsed time
	# render_tick is a float representing where we are in the timeline
	var render_tick: float = float(newest_tick) - BUFFER_DELAY_TICKS + (_snapshot_time / tick_interval)
	
	# Find the two snapshots that bracket render_tick
	var snap_a: Snapshot = null
	var snap_b: Snapshot = null
	for i in range(_snapshot_buffer.size() - 1):
		var s0: Snapshot = _snapshot_buffer[i]
		var s1: Snapshot = _snapshot_buffer[i + 1]
		if float(s0.tick) <= render_tick and render_tick <= float(s1.tick):
			snap_a = s0
			snap_b = s1
			break
	
	# Fallback: if render_tick is before all snapshots, use oldest two
	if snap_a == null:
		if render_tick < float(_snapshot_buffer[0].tick):
			snap_a = _snapshot_buffer[0]
			snap_b = _snapshot_buffer[min(1, _snapshot_buffer.size() - 1)]
		else:
			# render_tick is past all snapshots — extrapolate from newest two
			snap_a = _snapshot_buffer[-2]
			snap_b = _snapshot_buffer[-1]

	if not snap_b.entities.has(entity_id):
		return null

	var curr = snap_b.entities[entity_id]
	var curr_pos: Vector2 = curr["position"]

	if not snap_a.entities.has(entity_id):
		return curr_pos

	var prev = snap_a.entities[entity_id]
	var prev_pos: Vector2 = prev["position"]
	
	# Compute interpolation parameter between snap_a and snap_b
	var tick_span: float = float(snap_b.tick - snap_a.tick)
	if tick_span <= 0.0:
		return curr_pos
	
	var t: float = (render_tick - float(snap_a.tick)) / tick_span
	t = clampf(t, 0.0, MAX_REMOTE_INTERP)

	if t <= 1.0:
		# Within interpolation window — lerp between snapshots
		return prev_pos.lerp(curr_pos, t)
	else:
		# Extrapolate forward using current snapshot velocity.
		var snap_vel: Vector2 = curr.get("velocity", (curr_pos - prev_pos) / (tick_span * tick_interval))
		var extra_time = (t - 1.0) * tick_span * tick_interval
		return curr_pos + snap_vel * extra_time
```

- [ ] **Step 5: Run the buffer delay test**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdline.gd -gtest=res://tests/network/test_net_client_movement.gd::test_buffer_delay_renders_behind_latest_snapshot
```

Expected: PASS

### Step 3.3: Add test for smooth interpolation with buffer delay

- [ ] **Step 6: Write test for mid-buffer interpolation**

Add to `godot/tests/network/test_net_client_movement.gd`:

```gdscript
func test_buffer_delay_interpolates_smoothly():
	# With buffer delay, verify smooth interpolation mid-tick
	var snap1 = {"tick": 1, "entities": [
		{"entity_id": 2, "position": Vector2(100.0, 100.0), "flags": 0, "last_input_seq": 0,
		 "velocity": Vector2.ZERO, "aim_direction": Vector2.RIGHT, "state": 0,
		 "dodge_time_remaining": 0.0, "collision_count": 0, "last_collision_normal": Vector2.ZERO}
	], "enemy_entities": []}
	_client._apply_full_snapshot(snap1)
	
	var snap2 = {"tick": 2, "entities": [
		{"entity_id": 2, "position": Vector2(110.0, 100.0), "flags": 0, "last_input_seq": 0,
		 "velocity": Vector2.ZERO, "aim_direction": Vector2.RIGHT, "state": 0,
		 "dodge_time_remaining": 0.0, "collision_count": 0, "last_collision_normal": Vector2.ZERO}
	]}
	_client._apply_delta_snapshot(snap2)
	
	var snap3 = {"tick": 3, "entities": [
		{"entity_id": 2, "position": Vector2(120.0, 100.0), "flags": 0, "last_input_seq": 0,
		 "velocity": Vector2.ZERO, "aim_direction": Vector2.RIGHT, "state": 0,
		 "dodge_time_remaining": 0.0, "collision_count": 0, "last_collision_normal": Vector2.ZERO}
	]}
	_client._apply_delta_snapshot(snap3)
	
	# Half a tick after snap3 arrives: render_tick = 3 - 2 + 0.5 = 1.5
	# Should interpolate between snap1 (100) and snap2 (110) at t=0.5 → 105
	_client._snapshot_time = TICK_S * 0.5
	var pos = _client.get_interpolated_position(2)
	
	assert_almost_eq(pos.x, 105.0, 1.0,
		"Should interpolate smoothly between buffered snapshots")
```

- [ ] **Step 7: Run the smooth interpolation test**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdline.gd -gtest=res://tests/network/test_net_client_movement.gd::test_buffer_delay_interpolates_smoothly
```

Expected: PASS

### Step 3.4: Update existing tests for new behavior

- [ ] **Step 8: Update test_remote_interpolation_normal_range**

The existing test expects t=0.5 to give position 205 (midpoint of 200→210). With buffer delay, the math changes. Update the test:

```gdscript
func test_remote_interpolation_normal_range():
	# Build a 3-snapshot buffer: ticks 1, 2, 3
	_client._snapshot_buffer = []
	
	var snap1 = SnapshotScript.new()
	snap1.tick = 1
	snap1.entities[2] = {
		"entity_id": 2, "position": Vector2(190.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	_client._snapshot_buffer.append(snap1)
	
	var snap2 = SnapshotScript.new()
	snap2.tick = 2
	snap2.entities[2] = {
		"entity_id": 2, "position": Vector2(200.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	_client._snapshot_buffer.append(snap2)
	
	var snap3 = SnapshotScript.new()
	snap3.tick = 3
	snap3.entities[2] = {
		"entity_id": 2, "position": Vector2(210.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	_client._snapshot_buffer.append(snap3)
	
	# Half tick elapsed: render_tick = 3 - 2 + 0.5 = 1.5
	# Interpolates between snap1 (190) and snap2 (200) at t=0.5 → 195
	_client._snapshot_time = TICK_S / 2.0

	var pos = _client.get_interpolated_position(2)
	assert_almost_eq(pos.x, 195.0, 0.01,
		"Remote player should interpolate at render_tick 1.5")
```

- [ ] **Step 9: Update test_remote_extrapolation_past_tick**

```gdscript
func test_remote_extrapolation_past_tick():
	# When time exceeds buffer delay catchup, extrapolation kicks in
	_client._snapshot_buffer = []
	
	var snap1 = SnapshotScript.new()
	snap1.tick = 1
	snap1.entities[2] = {
		"entity_id": 2, "position": Vector2(190.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	_client._snapshot_buffer.append(snap1)
	
	var snap2 = SnapshotScript.new()
	snap2.tick = 2
	snap2.entities[2] = {
		"entity_id": 2, "position": Vector2(200.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	_client._snapshot_buffer.append(snap2)
	
	var snap3 = SnapshotScript.new()
	snap3.tick = 3
	snap3.entities[2] = {
		"entity_id": 2, "position": Vector2(210.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	_client._snapshot_buffer.append(snap3)
	
	# 3 ticks elapsed: render_tick = 3 - 2 + 3 = 4, which is past snap3
	# Should extrapolate beyond 210
	_client._snapshot_time = TICK_S * 3.0

	var pos = _client.get_interpolated_position(2)

	assert_gt(pos.x, 210.0,
		"Remote player should extrapolate past newest when render_tick exceeds buffer")
```

- [ ] **Step 10: Update test_remote_extrapolation_capped_at_max**

```gdscript
func test_remote_extrapolation_capped_at_max():
	_client._snapshot_buffer = []
	
	var snap1 = SnapshotScript.new()
	snap1.tick = 1
	snap1.entities[2] = {
		"entity_id": 2, "position": Vector2(190.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	_client._snapshot_buffer.append(snap1)
	
	var snap2 = SnapshotScript.new()
	snap2.tick = 2
	snap2.entities[2] = {
		"entity_id": 2, "position": Vector2(200.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	_client._snapshot_buffer.append(snap2)
	
	var snap3 = SnapshotScript.new()
	snap3.tick = 3
	snap3.entities[2] = {
		"entity_id": 2, "position": Vector2(210.0, 100.0), "flags": 0, "last_input_seq": 0,
	}
	_client._snapshot_buffer.append(snap3)
	
	# Way past tick boundary — extrapolation should cap at MAX_REMOTE_INTERP
	_client._snapshot_time = TICK_S * 10.0

	var pos = _client.get_interpolated_position(2)

	# render_tick = 3 - 2 + 10 = 11, snap_b.tick = 3, snap_a.tick = 2
	# t = (11 - 2) / 1 = 9, clamped to MAX_REMOTE_INTERP (3.0)
	# extra_time = (3.0 - 1.0) * 1 * TICK_S = 2 * TICK_S
	# vel = (210 - 200) / TICK_S
	# result = 210 + vel * extra_time = 210 + 10/TICK_S * 2*TICK_S = 230
	assert_almost_eq(pos.x, 230.0, 1.0,
		"Remote extrapolation should cap at MAX_REMOTE_INTERP (3.0)")
```

- [ ] **Step 11: Update test_remote_extrapolation_uses_snapshot_velocity**

```gdscript
func test_remote_extrapolation_uses_snapshot_velocity():
	var net = NetClientScript.new()
	add_child_autofree(net)
	net._snapshot_buffer = []

	var snap1 = SnapshotScript.new()
	snap1.tick = 1
	snap1.entities[2] = {
		"entity_id": 2, "position": Vector2(90.0, 0.0), "flags": 0, "last_input_seq": 0,
		"velocity": Vector2.ZERO, "aim_direction": Vector2.RIGHT,
		"state": 0, "dodge_time_remaining": 0.0,
	}
	net._snapshot_buffer.append(snap1)

	var snap2 = SnapshotScript.new()
	snap2.tick = 2
	snap2.entities[2] = {
		"entity_id": 2, "position": Vector2(100.0, 0.0), "flags": 0, "last_input_seq": 0,
		"velocity": Vector2.ZERO, "aim_direction": Vector2.RIGHT,
		"state": 0, "dodge_time_remaining": 0.0,
	}
	net._snapshot_buffer.append(snap2)

	var snap3 = SnapshotScript.new()
	snap3.tick = 3
	snap3.entities[2] = {
		"entity_id": 2, "position": Vector2(110.0, 0.0), "flags": 0, "last_input_seq": 0,
		"velocity": Vector2(400.0, 0.0), "aim_direction": Vector2.RIGHT,
		"state": 0, "dodge_time_remaining": 0.0,
	}
	net._snapshot_buffer.append(snap3)

	# render_tick = 3 - 2 + 3.4 = 4.4, extrapolating past snap3
	# t = (4.4 - 2) / 1 = 2.4
	# extra_time = (2.4 - 1.0) * 1 * TICK_S = 1.4 * TICK_S
	# result = 110 + 400 * 1.4 * TICK_S
	net._snapshot_time = TICK_S * 3.4

	var result = net.get_interpolated_position(2)
	var expected_x: float = 110.0 + 400.0 * 1.4 * TICK_S
	assert_almost_eq(result.x, expected_x, 0.5,
		"Extrapolation must use snapshot velocity")
```

- [ ] **Step 12: Run all movement tests**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdline.gd -gtest=res://tests/network/test_net_client_movement.gd
```

Expected: All tests pass.

- [ ] **Step 13: Run full test suite to check for regressions**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdline.gd
```

Expected: All tests pass.

- [ ] **Step 14: Commit**

```bash
git add godot/simulation/network/net_client.gd godot/tests/network/test_net_client_movement.gd
git commit -m "$(cat <<'EOF'
net_client: add 2-tick buffer delay for interpolation

Remote entities now render ~66ms behind server time. This ensures we're
almost always interpolating between two known positions rather than
extrapolating, eliminating jitter-induced visual pops.

Combined with the 3-snapshot buffer and extended extrapolation window,
this provides robust handling of typical network conditions.
EOF
)"
```

---

## Summary

After completing all tasks:

1. **MAX_REMOTE_INTERP**: 1.5 → 3.0 (extrapolate up to 2 ticks / ~66ms)
2. **Snapshot buffer**: 2 snapshots → 3 snapshots (single packet loss resilience)
3. **Buffer delay**: 0 → 2 ticks (~66ms behind real-time, always interpolating)

These changes make remote entity rendering significantly smoother on typical residential internet connections while adding only ~66ms of visual latency for remote entities (local player is unaffected).
