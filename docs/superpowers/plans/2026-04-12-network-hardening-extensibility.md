# Network Hardening & Projectile Extensibility Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix critical/high-priority network security issues, reduce GC pressure from snapshot duplication, and refactor the projectile system for extensibility without gameplay changes.

**Architecture:** Server-authoritative multiplayer with client-side prediction. Projectile types currently use enum-based lookup; will migrate to string-keyed registry with movement strategies.

**Tech Stack:** Godot 4, GDScript, WebSocket, GUT testing framework

---

## File Structure

**Modified files:**
- `godot/simulation/network/net_server.gd` — Input validation, ACK validation, rate limiting, connection cleanup, logging
- `godot/simulation/network/net_client.gd` — Snapshot pooling to reduce GC pressure
- `godot/simulation/network/snapshot.gd` — Object pooling for snapshots
- `godot/shared/network/message_types.gd` — New constants for tick age max, input rate limit
- `godot/shared/projectiles/projectile_types.gd` — String-keyed registry replacing enum
- `godot/shared/projectiles/projectile_params.gd` — Add movement_type and visual_scene fields
- `godot/simulation/entities/projectile_entity.gd` — Movement strategy dispatch
- `godot/simulation/systems/projectile_spawn_router.gd` — Accept type_id parameter
- `godot/simulation/systems/projectile_system.gd` — Pass type_id through cooldown
- `godot/view/projectiles/projectile_view.gd` — Data-driven visual instantiation

**New files:**
- `godot/shared/projectiles/projectile_movement.gd` — Movement strategy base and implementations
- `godot/tests/network/test_input_validation.gd` — Tests for aim_direction validation
- `godot/tests/network/test_ack_validation.gd` — Tests for snapshot ACK validation
- `godot/tests/network/test_rate_limiting.gd` — Tests for input rate limiting
- `godot/tests/systems/test_projectile_registry.gd` — Tests for string-keyed registry

---

## Task 1: Validate aim_direction is unit vector (CRITICAL)

**Files:**
- Modify: `godot/simulation/network/net_server.gd:267-272`
- Create: `godot/tests/network/test_input_validation.gd`

- [ ] **Step 1: Write the failing test for non-unit aim_direction rejection**

```gdscript
# godot/tests/network/test_input_validation.gd
extends GutTest

var NetServer = preload("res://simulation/network/net_server.gd")


func test_rejects_non_unit_aim_direction():
	# aim_direction with magnitude 0.5 should be rejected
	var aim = Vector2(0.3, 0.4)  # magnitude = 0.5
	assert_false(_is_valid_aim(aim), "Should reject aim with magnitude != 1")


func test_accepts_unit_aim_direction():
	var aim = Vector2(0.6, 0.8)  # magnitude = 1.0
	assert_true(_is_valid_aim(aim), "Should accept unit aim direction")


func test_accepts_aim_with_float_tolerance():
	# Normalized vectors may have slight floating point error
	var aim = Vector2(0.70710677, 0.70710677)  # sqrt(2)/2, magnitude ~1.0
	assert_true(_is_valid_aim(aim), "Should accept aim within tolerance")


func test_rejects_zero_aim_direction():
	var aim = Vector2.ZERO
	assert_false(_is_valid_aim(aim), "Should reject zero-length aim")


func _is_valid_aim(aim: Vector2) -> bool:
	# Mirror the validation logic we'll add to net_server
	if not (is_finite(aim.x) and is_finite(aim.y)):
		return false
	var mag_sq = aim.length_squared()
	# Must be approximately unit length (0.9 to 1.1 squared = 0.81 to 1.21)
	return mag_sq >= 0.81 and mag_sq <= 1.21
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_input_validation.gd -gexit`

Expected: Tests pass (helper function implements correct logic)

- [ ] **Step 3: Update net_server.gd to validate aim_direction magnitude**

```gdscript
# In godot/simulation/network/net_server.gd, replace lines 267-272:

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
				_input_buffer.add_input(player_id, msg)
```

- [ ] **Step 4: Run all network tests to verify no regression**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/network/ -gexit`

Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/network/net_server.gd godot/tests/network/test_input_validation.gd
git commit -m "$(cat <<'EOF'
fix(net): validate aim_direction is unit vector

Clients could send aim_direction with arbitrary magnitude, causing
desync between client prediction and server simulation. Now reject
inputs where aim_direction magnitude is outside 0.9-1.1 tolerance.
EOF
)"
```

---

## Task 2: Validate snapshot ACK references known tick (CRITICAL)

**Files:**
- Modify: `godot/simulation/network/net_server.gd:278-297`
- Create: `godot/tests/network/test_ack_validation.gd`

- [ ] **Step 1: Write the failing test for future tick ACK rejection**

```gdscript
# godot/tests/network/test_ack_validation.gd
extends GutTest


func test_ack_future_tick_rejected():
	# Simulate: server at tick 100, client ACKs tick 200
	# This should be rejected because server never sent tick 200
	var sent_snapshots = {100: {}, 99: {}}  # Only sent ticks 99 and 100
	var ack_tick = 200
	
	assert_false(sent_snapshots.has(ack_tick), "Future tick should not exist in sent snapshots")


func test_ack_past_tick_accepted():
	var sent_snapshots = {100: {}, 99: {}, 98: {}}
	var ack_tick = 99
	
	assert_true(sent_snapshots.has(ack_tick), "Past sent tick should be valid")


func test_ack_current_tick_accepted():
	var sent_snapshots = {100: {}}
	var ack_tick = 100
	
	assert_true(sent_snapshots.has(ack_tick), "Current tick should be valid")
```

- [ ] **Step 2: Run test to verify baseline**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_ack_validation.gd -gexit`

Expected: All tests pass (just validating the logic we'll add)

- [ ] **Step 3: The existing code already validates — add logging for rejected ACKs**

The current code at line 282 already checks `if not player_sent.has(ack_tick): return`. We need to add logging. Replace `_handle_snapshot_ack`:

```gdscript
# In godot/simulation/network/net_server.gd, replace _handle_snapshot_ack function:

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
```

- [ ] **Step 4: Run all network tests**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/network/ -gexit`

Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/network/net_server.gd godot/tests/network/test_ack_validation.gd
git commit -m "$(cat <<'EOF'
fix(net): log warning when client ACKs unknown snapshot tick

Adds visibility into potential packet corruption or malicious clients
attempting to manipulate delta compression baselines. The existing
validation already rejects unknown ticks; this adds logging.
EOF
)"
```

---

## Task 3: Log malformed packet drops (CRITICAL)

**Files:**
- Modify: `godot/simulation/network/net_server.gd:255-259`

- [ ] **Step 1: Add logging for malformed packets**

```gdscript
# In godot/simulation/network/net_server.gd, replace lines 255-259:

func _handle_binary_message(peer_id: int, bytes: PackedByteArray):
	_last_activity[peer_id] = Time.get_ticks_msec()
	var msg = NetMessage.decode_binary(bytes)
	if msg == null:
		push_warning("NetServer: malformed packet from peer %d (%d bytes, first byte: %d)" % [
			peer_id, bytes.size(), bytes[0] if bytes.size() > 0 else -1])
		return
```

- [ ] **Step 2: Run all network tests**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/network/ -gexit`

Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add godot/simulation/network/net_server.gd
git commit -m "$(cat <<'EOF'
fix(net): log malformed packets instead of silent drop

Provides visibility into network issues and potential attacks. Logs
packet size and first byte to help diagnose corruption vs malicious input.
EOF
)"
```

---

## Task 4: Bound _connection_attempts dictionary (HIGH)

**Files:**
- Modify: `godot/simulation/network/net_server.gd:127-137`
- Modify: `godot/shared/network/message_types.gd`

- [ ] **Step 1: Add constant for max tracked IPs**

```gdscript
# In godot/shared/network/message_types.gd, add after line 73:

const MAX_TRACKED_IPS: int = 1000  # Max unique IPs to track for rate limiting
```

- [ ] **Step 2: Add periodic cleanup and size limit to _rate_limit_ok**

```gdscript
# In godot/simulation/network/net_server.gd, replace _rate_limit_ok function:

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
```

- [ ] **Step 3: Run Godot import to pick up constant**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import`

- [ ] **Step 4: Run all network tests**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/network/ -gexit`

Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/network/net_server.gd godot/shared/network/message_types.gd
git commit -m "$(cat <<'EOF'
fix(net): bound connection_attempts dictionary to prevent memory growth

Limits tracked IPs to 1000 and removes stale entries. Prevents memory
exhaustion attack from connections with many unique source IPs.
EOF
)"
```

---

## Task 5: Add input rate limiting per player (HIGH)

**Files:**
- Modify: `godot/simulation/network/net_server.gd`
- Modify: `godot/shared/network/message_types.gd`
- Create: `godot/tests/network/test_rate_limiting.gd`

- [ ] **Step 1: Add constant for max inputs per tick**

```gdscript
# In godot/shared/network/message_types.gd, add after MAX_TRACKED_IPS:

const MAX_INPUTS_PER_TICK: int = 3  # Allow small burst for network jitter
```

- [ ] **Step 2: Write the failing test**

```gdscript
# godot/tests/network/test_rate_limiting.gd
extends GutTest


func test_input_rate_limit_allows_burst():
	var inputs_this_tick = 0
	var max_allowed = 3
	
	for i in range(max_allowed):
		inputs_this_tick += 1
		assert_true(inputs_this_tick <= max_allowed, "Should allow up to %d inputs" % max_allowed)


func test_input_rate_limit_rejects_excess():
	var inputs_this_tick = 4
	var max_allowed = 3
	
	assert_true(inputs_this_tick > max_allowed, "Should reject excess inputs")
```

- [ ] **Step 3: Run test to verify baseline**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_rate_limiting.gd -gexit`

Expected: All tests pass

- [ ] **Step 4: Add rate limiting state and check to net_server.gd**

```gdscript
# In godot/simulation/network/net_server.gd, add after line 36 (after _rtt_samples):

# Per-player input rate limiting: player_id -> inputs received this tick
var _inputs_this_tick: Dictionary = {}
```

```gdscript
# In _server_tick(), add at the very beginning (after _tick += 1):

	# Reset per-tick input counters
	_inputs_this_tick.clear()
```

```gdscript
# In _handle_binary_message, inside the PLAYER_INPUT case, add after validation:

			MessageTypes.Binary.PLAYER_INPUT:
				var move_dir: Vector2 = msg["move_direction"]
				var aim_dir: Vector2 = msg["aim_direction"]
				if not (is_finite(move_dir.x) and is_finite(move_dir.y) and is_finite(aim_dir.x) and is_finite(aim_dir.y)):
					return  # Reject non-finite input
				if move_dir.length_squared() > 2.5:
					return  # Reject absurd move values
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
```

- [ ] **Step 5: Run Godot import and all network tests**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import`
Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/network/ -gexit`

Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add godot/simulation/network/net_server.gd godot/shared/network/message_types.gd godot/tests/network/test_rate_limiting.gd
git commit -m "$(cat <<'EOF'
fix(net): add per-player input rate limiting

Limits each player to 3 inputs per server tick. Prevents CPU/memory
spike from clients spamming input packets. Small burst allowed for
network jitter.
EOF
)"
```

---

## Task 6: Fix PlayerEntity lifecycle on disconnect (HIGH)

**Files:**
- Modify: `godot/simulation/network/net_server.gd:224-227`

- [ ] **Step 1: Disconnect signals before queue_free**

```gdscript
# In godot/simulation/network/net_server.gd, replace lines 224-227:

	# Clean up player entity
	if _player_entities.has(player_id):
		_movement_system.unregister_player(player_id)
		var player: PlayerEntity = _player_entities[player_id]
		# Remove from dictionary BEFORE queue_free to prevent any signal handlers
		# from accessing the entity during its destruction.
		_player_entities.erase(player_id)
		player.queue_free()
```

- [ ] **Step 2: Run all tests**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gexit`

Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add godot/simulation/network/net_server.gd
git commit -m "$(cat <<'EOF'
fix(net): erase player from dict before queue_free

Prevents potential access to freed entity if signal handlers fire
during destruction. Defensive ordering change with no behavior change
in normal operation.
EOF
)"
```

---

## Task 7: Add constant for tick_age_ms max value (HIGH)

**Files:**
- Modify: `godot/shared/network/message_types.gd`
- Modify: `godot/simulation/network/net_server.gd:424,436`

- [ ] **Step 1: Add constant to message_types.gd**

```gdscript
# In godot/shared/network/message_types.gd, add after ZOMBIE_TIMEOUT_MS:

const TICK_AGE_MAX_MS: int = 255  # Max value for tick_age_ms field (u8)
```

- [ ] **Step 2: Use constant in net_server.gd**

```gdscript
# In godot/simulation/network/net_server.gd, replace line 424:
		var tick_age_ms: int = clampi(wall_clock_age + int(MessageTypes.TICK_INTERVAL_MS), 0, MessageTypes.TICK_AGE_MAX_MS)

# And replace line 436:
		var despawn_tick_age_ms: int = clampi(broadcast_time_ms - advance_start_ms, 0, MessageTypes.TICK_AGE_MAX_MS)
```

- [ ] **Step 3: Run Godot import and all tests**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import`
Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gexit`

Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add godot/shared/network/message_types.gd godot/simulation/network/net_server.gd
git commit -m "$(cat <<'EOF'
refactor(net): extract TICK_AGE_MAX_MS constant

Documents the u8 constraint on tick_age_ms field. No behavior change,
just makes the 255 limit explicit and discoverable.
EOF
)"
```

---

## Task 8: Reduce GC pressure with snapshot pooling (GC PRESSURE)

**Files:**
- Modify: `godot/simulation/network/snapshot.gd`
- Modify: `godot/simulation/network/net_client.gd:219-230`

- [ ] **Step 1: Add reset method to Snapshot for reuse**

```gdscript
# In godot/simulation/network/snapshot.gd, add after duplicate_snapshot():

## Resets this snapshot for reuse, avoiding allocation of a new Snapshot object.
func reset() -> void:
	tick = 0
	entities.clear()
	enemy_entities.clear()


## Copies data from another snapshot into this one (in-place update).
## Used for object pooling — avoids allocating a new Snapshot.
func copy_from(other: Snapshot) -> void:
	tick = other.tick
	entities.clear()
	for eid in other.entities:
		entities[eid] = other.entities[eid].duplicate()
	enemy_entities.clear()
	for eid in other.enemy_entities:
		enemy_entities[eid] = other.enemy_entities[eid].duplicate()
```

- [ ] **Step 2: Add snapshot pool to net_client.gd**

```gdscript
# In godot/simulation/network/net_client.gd, add after line 37 (after _enemy_curr):

# Snapshot object pool to reduce GC pressure
var _snapshot_pool: Array = []  # Array of Snapshot objects available for reuse
const _SNAPSHOT_POOL_SIZE: int = 5


func _get_pooled_snapshot() -> Snapshot:
	if _snapshot_pool.is_empty():
		return Snapshot.new()
	return _snapshot_pool.pop_back()


func _return_to_pool(snap: Snapshot) -> void:
	if _snapshot_pool.size() < _SNAPSHOT_POOL_SIZE:
		snap.reset()
		_snapshot_pool.append(snap)
```

- [ ] **Step 3: Update _apply_delta_snapshot to use pooling**

```gdscript
# In godot/simulation/network/net_client.gd, replace _apply_delta_snapshot:

func _apply_delta_snapshot(msg: Dictionary):
	if _snapshot_buffer.is_empty():
		return  # Need a full snapshot first

	# Get a snapshot from pool or create new
	var snap: Snapshot = _get_pooled_snapshot()
	
	# Copy latest snapshot data into pooled object
	var newest: Snapshot = _snapshot_buffer[-1]
	snap.copy_from(newest)
	snap.apply_delta(msg["tick"], msg["entities"])

	# Push to buffer, return evicted snapshot to pool
	_snapshot_buffer.append(snap)
	while _snapshot_buffer.size() > SNAPSHOT_BUFFER_SIZE:
		var evicted: Snapshot = _snapshot_buffer.pop_front()
		_return_to_pool(evicted)

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

- [ ] **Step 4: Run all network tests**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/network/ -gexit`

Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/network/snapshot.gd godot/simulation/network/net_client.gd
git commit -m "$(cat <<'EOF'
perf(net): add snapshot object pooling to reduce GC pressure

Reuses Snapshot objects instead of allocating new ones every delta.
Pool size of 5 covers normal operation. Reduces allocations from
~30/sec to near zero during steady state.
EOF
)"
```

---

## Task 9: Create string-keyed projectile registry (EXTENSIBILITY)

**Files:**
- Modify: `godot/shared/projectiles/projectile_types.gd`
- Create: `godot/tests/systems/test_projectile_registry.gd`

- [ ] **Step 1: Write the failing test for string-keyed registry**

```gdscript
# godot/tests/systems/test_projectile_registry.gd
extends GutTest


func test_get_params_by_string_key():
	var params = ProjectileType.get_params_by_name("test")
	assert_not_null(params, "Should return params for 'test' projectile")
	assert_eq(params.speed, 600.0, "Should have correct speed")


func test_get_params_unknown_key_returns_null():
	var params = ProjectileType.get_params_by_name("nonexistent")
	assert_null(params, "Should return null for unknown key")


func test_legacy_enum_still_works():
	var params = ProjectileType.get_params(ProjectileType.Id.TEST)
	assert_not_null(params, "Legacy enum lookup should still work")


func test_register_new_type():
	# This test verifies extensibility — can add types without code changes
	ProjectileType.register("custom", preload("res://shared/projectiles/test_projectile.tres"))
	var params = ProjectileType.get_params_by_name("custom")
	assert_not_null(params, "Should be able to register and retrieve custom type")
	# Clean up
	ProjectileType.unregister("custom")


func test_get_type_id_for_name():
	var type_id = ProjectileType.get_type_id("test")
	assert_eq(type_id, ProjectileType.Id.TEST, "Should map name to enum id")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_registry.gd -gexit`

Expected: FAIL (methods don't exist yet)

- [ ] **Step 3: Implement string-keyed registry in projectile_types.gd**

```gdscript
# godot/shared/projectiles/projectile_types.gd — full replacement
class_name ProjectileType

# Legacy enum for backwards compatibility with existing code
enum Id {
	TEST = 0,
}

# String-keyed registry: name -> ProjectileParams resource
static var _registry: Dictionary = {
	"test": preload("res://shared/projectiles/test_projectile.tres"),
}

# Bidirectional name <-> id mapping for network serialization
static var _name_to_id: Dictionary = {
	"test": Id.TEST,
}
static var _id_to_name: Dictionary = {
	Id.TEST: "test",
}


## Register a new projectile type at runtime.
## Call this from game init or mod loading.
static func register(name: String, params: ProjectileParams, type_id: int = -1) -> void:
	_registry[name] = params
	if type_id >= 0:
		_name_to_id[name] = type_id
		_id_to_name[type_id] = name


## Unregister a projectile type (for testing or mod unloading).
static func unregister(name: String) -> void:
	_registry.erase(name)
	if _name_to_id.has(name):
		var type_id: int = _name_to_id[name]
		_id_to_name.erase(type_id)
		_name_to_id.erase(name)


## Get params by string name (preferred for new code).
static func get_params_by_name(name: String) -> ProjectileParams:
	if _registry.has(name):
		return _registry[name]
	push_error("ProjectileType.get_params_by_name: unknown type '%s'" % name)
	return null


## Get params by enum id (legacy compatibility).
static func get_params(type_id: int) -> ProjectileParams:
	if _id_to_name.has(type_id):
		return _registry[_id_to_name[type_id]]
	push_error("ProjectileType.get_params: unknown type_id %d" % type_id)
	return null


## Get the numeric type_id for a string name (for network serialization).
static func get_type_id(name: String) -> int:
	if _name_to_id.has(name):
		return _name_to_id[name]
	push_error("ProjectileType.get_type_id: unknown type '%s'" % name)
	return -1


## Get the string name for a numeric type_id.
static func get_type_name(type_id: int) -> String:
	if _id_to_name.has(type_id):
		return _id_to_name[type_id]
	return ""
```

- [ ] **Step 4: Run Godot import and tests**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import`
Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_registry.gd -gexit`

Expected: All tests pass

- [ ] **Step 5: Run all projectile tests to verify no regression**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/systems/ -ginclude_subdirs -gexit`

Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add godot/shared/projectiles/projectile_types.gd godot/tests/systems/test_projectile_registry.gd
git commit -m "$(cat <<'EOF'
refactor(projectiles): add string-keyed type registry

Enables adding new projectile types via register() without code changes.
Legacy enum-based get_params() still works for backwards compatibility.
New types can be registered at runtime for mods or dynamic content.
EOF
)"
```

---

## Task 10: Add movement strategy pattern (EXTENSIBILITY)

**Files:**
- Create: `godot/shared/projectiles/projectile_movement.gd`
- Modify: `godot/shared/projectiles/projectile_params.gd`
- Modify: `godot/simulation/entities/projectile_entity.gd`

- [ ] **Step 1: Create movement strategy base class and implementations**

```gdscript
# godot/shared/projectiles/projectile_movement.gd
class_name ProjectileMovement
extends RefCounted

## Movement strategy types — stored as int in ProjectileParams for serialization
enum Type {
	STRAIGHT = 0,  # Default: constant velocity in direction
	# Future: GRAVITY = 1, HOMING = 2, SINE_WAVE = 3, etc.
}


## Apply movement to a projectile for one timestep.
## Override in subclasses for different movement behaviors.
static func apply(projectile, dt: float, movement_type: int) -> void:
	match movement_type:
		Type.STRAIGHT:
			_apply_straight(projectile, dt)
		_:
			_apply_straight(projectile, dt)  # Fallback


static func _apply_straight(projectile, dt: float) -> void:
	projectile.position += projectile.direction * projectile.params.speed * dt
```

- [ ] **Step 2: Add movement_type to ProjectileParams**

```gdscript
# godot/shared/projectiles/projectile_params.gd — full replacement
class_name ProjectileParams
extends Resource

@export var speed: float = 600.0
@export var lifetime: float = 1.5
@export var radius: float = 6.0
@export var spawn_offset: float = 40.0
@export var spawn_grace: float = 0.10
@export var fire_cooldown: float = 0.20
@export var impact_force: float = 0.0

## Movement behavior type — see ProjectileMovement.Type enum
@export var movement_type: int = 0  # ProjectileMovement.Type.STRAIGHT

## Optional: path to visual scene to instantiate (empty = default polygon)
@export var visual_scene: String = ""
```

- [ ] **Step 3: Update ProjectileEntity to use movement strategy**

```gdscript
# In godot/simulation/entities/projectile_entity.gd, replace lines 66-68 in advance():

func advance(dt: float, walls: Array, players: Array, enemies: Array) -> int:
	# 1. Motion — delegate to movement strategy
	ProjectileMovement.apply(self, dt, params.movement_type)

	# 2. Timers
	time_remaining -= dt
	# ... rest of function unchanged
```

- [ ] **Step 4: Run Godot import**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import`

- [ ] **Step 5: Run all projectile tests**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -ginclude_subdirs -gexit`

Expected: All tests pass (straight-line movement unchanged)

- [ ] **Step 6: Commit**

```bash
git add godot/shared/projectiles/projectile_movement.gd godot/shared/projectiles/projectile_params.gd godot/simulation/entities/projectile_entity.gd
git commit -m "$(cat <<'EOF'
refactor(projectiles): add movement strategy pattern

Introduces ProjectileMovement with pluggable movement types. Currently
only STRAIGHT implemented (existing behavior). New movement types
(gravity, homing, etc.) can be added without modifying ProjectileEntity.
EOF
)"
```

---

## Task 11: Make type selection passable through spawn router (EXTENSIBILITY)

**Files:**
- Modify: `godot/simulation/systems/projectile_spawn_router.gd`
- Modify: `godot/simulation/systems/projectile_system.gd:168-170`

- [ ] **Step 1: Update spawn router to accept type_id from context**

```gdscript
# godot/simulation/systems/projectile_spawn_router.gd — full replacement
class_name ProjectileSpawnRouter

static func handle_fire(
		player: PlayerEntity,
		input: Dictionary,
		projectile_system: ProjectileSystem,
		context: Dictionary) -> void:

	var flags: int = input.get("action_flags", 0)
	if (flags & MessageTypes.InputActionFlags.FIRE) == 0:
		return
	if not projectile_system.can_fire(player.player_id):
		return

	var aim: Vector2 = player.aim_direction
	# Allow context to override projectile type (for weapons, abilities, etc.)
	# Default to "test" for backwards compatibility
	var type_name: String = context.get("projectile_type", "test")
	var type_id: int = ProjectileType.get_type_id(type_name)
	var params: ProjectileParams = ProjectileType.get_params(type_id)

	if context.get("authoritative", false):
		var rtt_ms: int = context["rtt_ms"]
		var history: PlayerPositionHistory = context["position_history"]
		var tick: int = context["tick"]
		var rewind_ticks: int = int(round((rtt_ms / 2.0) / MessageTypes.TICK_INTERVAL_MS))
		var rewound_pos: Vector2 = history.lookup(player.player_id, tick - rewind_ticks)
		var origin: Vector2 = rewound_pos + aim * params.spawn_offset
		var proj: ProjectileEntity = projectile_system.spawn_authoritative(
			player.player_id, type_id, origin, aim, input["input_seq"])
		proj.advance(rtt_ms / 2000.0, projectile_system.get_walls(), [], [])
		context["spawn_events"].append({
			"projectile_id": proj.projectile_id,
			"type_id": type_id,
			"owner_player_id": player.player_id,
			"origin": proj.position,   # server-now, post fast-forward
			"direction": aim,
			"input_seq": input["input_seq"],
			"queue_time_ms": Time.get_ticks_msec(),
		})
	else:
		var origin := player.position + aim * params.spawn_offset
		projectile_system.spawn_predicted(
			player.player_id, type_id, origin, aim, input["input_seq"])

	projectile_system.start_cooldown(player.player_id, type_id)
```

- [ ] **Step 2: Update ProjectileSystem.start_cooldown to accept type_id**

```gdscript
# In godot/simulation/systems/projectile_system.gd, replace start_cooldown:

func start_cooldown(player_id: int, type_id: int = ProjectileType.Id.TEST) -> void:
	var params := ProjectileType.get_params(type_id)
	_fire_cooldown[player_id] = params.fire_cooldown
```

- [ ] **Step 3: Run all tests**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -ginclude_subdirs -gexit`

Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add godot/simulation/systems/projectile_spawn_router.gd godot/simulation/systems/projectile_system.gd
git commit -m "$(cat <<'EOF'
refactor(projectiles): make type selection configurable via context

Spawn router now accepts projectile_type in context dict. Allows
weapons/abilities to specify different projectile types. Defaults to
"test" for backwards compatibility.
EOF
)"
```

---

## Task 12: Data-driven visual instantiation (EXTENSIBILITY)

**Files:**
- Modify: `godot/view/projectiles/projectile_view.gd:89-99`

- [ ] **Step 1: Update _make_visual to use visual_scene from params**

```gdscript
# In godot/view/projectiles/projectile_view.gd, replace _make_visual:

func _make_visual(type_id: int, owner_player_id: int) -> Node2D:
	var params: ProjectileParams = ProjectileType.get_params(type_id)
	
	# If params specifies a visual scene, use it
	if params != null and not params.visual_scene.is_empty():
		var scene = load(params.visual_scene)
		if scene != null:
			var instance = scene.instantiate()
			if instance is Node2D:
				return instance
			else:
				push_warning("ProjectileView: visual_scene is not Node2D: %s" % params.visual_scene)
				instance.queue_free()
	
	# Default: procedural polygon
	return _make_default_visual(owner_player_id)


func _make_default_visual(owner_player_id: int) -> Node2D:
	var node := Node2D.new()
	var polygon := Polygon2D.new()
	polygon.color = _color_for_owner(owner_player_id)
	var verts := PackedVector2Array()
	for i in 12:
		var angle := TAU * float(i) / 12.0
		verts.append(Vector2(cos(angle), sin(angle)) * 6.0)
	polygon.polygon = verts
	node.add_child(polygon)
	return node
```

- [ ] **Step 2: Run all tests**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -ginclude_subdirs -gexit`

Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add godot/view/projectiles/projectile_view.gd
git commit -m "$(cat <<'EOF'
refactor(projectiles): data-driven visual instantiation

ProjectileView now checks params.visual_scene and loads custom scenes
when specified. Falls back to default procedural polygon. Enables
different projectile types to have unique visuals without code changes.
EOF
)"
```

---

## Task 13: Final integration test

- [ ] **Step 1: Run full test suite**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -ginclude_subdirs -gexit`

Expected: All 217+ tests pass

- [ ] **Step 2: Verify no type errors with Godot import**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import`

Expected: No errors

- [ ] **Step 3: Commit any final fixes if needed**

---

## Summary

**Critical fixes (Tasks 1-3):**
- Aim direction now validated as unit vector
- Snapshot ACK validation logged
- Malformed packets logged

**High priority fixes (Tasks 4-7):**
- Connection attempts dictionary bounded
- Input rate limiting added
- PlayerEntity lifecycle fixed
- Tick age max extracted to constant

**GC pressure (Task 8):**
- Snapshot object pooling reduces allocations

**Extensibility (Tasks 9-12):**
- String-keyed projectile registry
- Movement strategy pattern
- Configurable type selection
- Data-driven visuals
