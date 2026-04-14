# Muzzle Flash at Player Position Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spawn muzzle flash at the player's position (not the projectile's spawn offset) with zero latency for local player and correct positioning for remote players.

**Architecture:** Local player muzzle flash spawns directly from input handling in client_main.gd for instant feedback. Remote player muzzle flash uses a new `source_position` field in the network message, spawned by ProjectileEffects only for non-local players.

**Tech Stack:** GDScript, existing ProjectileEffects and FrostBoltMuzzle systems

---

## File Structure

| File | Responsibility |
|------|----------------|
| `godot/client_main.gd` | Spawn muzzle flash instantly for local player on fire input |
| `godot/view/projectiles/projectile_effects.gd` | Spawn muzzle flash for remote players only, using source_position |
| `godot/simulation/systems/projectile_spawn_router.gd` | Include source_position in spawn_events |
| `godot/simulation/network/net_message.gd` | Encode/decode source_position in PROJECTILE_SPAWNED |
| `godot/shared/network/message_types.gd` | Update PROJECTILE_SPAWNED_SIZE constant |
| `godot/tests/network/test_projectile_network.gd` | Test source_position encoding |
| `godot/tests/view/test_muzzle_flash_positioning.gd` | Integration test for muzzle flash behavior |

---

### Task 1: Add source_position to Network Message

**Files:**
- Modify: `godot/shared/network/message_types.gd:61`
- Modify: `godot/simulation/network/net_message.gd:254-284`
- Modify: `godot/tests/network/test_projectile_network.gd`

- [ ] **Step 1: Write failing test for source_position in message**

Add test to `godot/tests/network/test_projectile_network.gd`:

```gdscript
func test_projectile_spawned_preserves_source_position():
	var event := {
		"projectile_id": 999,
		"type_id": 1,
		"owner_player_id": 42,
		"origin": Vector2(150.0, 250.0),
		"direction": Vector2(0.707, 0.707),
		"input_seq": 88,
		"source_position": Vector2(110.0, 210.0),
	}
	var bytes: PackedByteArray = NetMessage.encode_projectile_spawned(event)
	var decoded: Dictionary = NetMessage.decode_projectile_spawned(bytes)
	assert_eq(decoded["source_position"], Vector2(110.0, 210.0))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script godot/tests/network/test_projectile_network.gd`

Expected: FAIL with key error or missing source_position

- [ ] **Step 3: Update message size constant**

In `godot/shared/network/message_types.gd`, change line 61:

```gdscript
	const PROJECTILE_SPAWNED_SIZE = 35  # was 27, added 8 bytes for source_position (2 floats)
```

- [ ] **Step 4: Update encode function**

In `godot/simulation/network/net_message.gd`, replace `_encode_projectile_spawned`:

```gdscript
static func _encode_projectile_spawned(event: Dictionary) -> PackedByteArray:
	var buf = PackedByteArray()
	buf.resize(MessageTypes.Layout.PROJECTILE_SPAWNED_SIZE)
	var origin: Vector2 = event["origin"]
	var direction: Vector2 = event["direction"]
	var source_pos: Vector2 = event.get("source_position", origin)
	buf.encode_u8(0, MessageTypes.Binary.PROJECTILE_SPAWNED)
	buf.encode_u16(1, event["projectile_id"])
	buf.encode_u8(3, event["type_id"])
	buf.encode_u16(4, event["owner_player_id"])
	buf.encode_float(6, origin.x)
	buf.encode_float(10, origin.y)
	buf.encode_float(14, direction.x)
	buf.encode_float(18, direction.y)
	buf.encode_u32(22, event["input_seq"])
	buf.encode_u8(26, event.get("tick_age_ms", 0))
	buf.encode_float(27, source_pos.x)
	buf.encode_float(31, source_pos.y)
	return buf
```

- [ ] **Step 5: Update decode function**

In `godot/simulation/network/net_message.gd`, replace `_decode_projectile_spawned`:

```gdscript
static func _decode_projectile_spawned(bytes: PackedByteArray) -> Variant:
	if bytes.size() < MessageTypes.Layout.PROJECTILE_SPAWNED_SIZE:
		return null
	return {
		"type": MessageTypes.Binary.PROJECTILE_SPAWNED,
		"projectile_id": bytes.decode_u16(1),
		"type_id": bytes.decode_u8(3),
		"owner_player_id": bytes.decode_u16(4),
		"origin": Vector2(bytes.decode_float(6), bytes.decode_float(10)),
		"direction": Vector2(bytes.decode_float(14), bytes.decode_float(18)),
		"input_seq": bytes.decode_u32(22),
		"tick_age_ms": bytes.decode_u8(26),
		"source_position": Vector2(bytes.decode_float(27), bytes.decode_float(31)),
	}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script godot/tests/network/test_projectile_network.gd`

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add godot/shared/network/message_types.gd godot/simulation/network/net_message.gd godot/tests/network/test_projectile_network.gd
git commit -m "$(cat <<'EOF'
feat(network): add source_position to PROJECTILE_SPAWNED message

The muzzle flash effect should appear at the player's position, not
the projectile's spawn offset. This adds source_position (player pos)
to the network message so remote clients can spawn effects correctly.
EOF
)"
```

---

### Task 2: Include source_position in Spawn Events

**Files:**
- Modify: `godot/simulation/systems/projectile_spawn_router.gd:35-43`
- Modify: `godot/tests/systems/test_projectile_spawn_router.gd`

- [ ] **Step 1: Write failing test for source_position in spawn event**

Add test to `godot/tests/systems/test_projectile_spawn_router.gd`:

```gdscript
func test_authoritative_spawn_event_includes_source_position():
	var history := PlayerPositionHistory.new()
	var sys := _make_system()
	var player := _make_player(42, Vector2(100, 100))
	# Record position at tick 100
	history.record(player.player_id, Vector2(100, 100), 100)
	
	var spawn_events: Array = []
	var context := {
		"authoritative": true,
		"rtt_ms": 0,
		"position_history": history,
		"tick": 100,
		"spawn_events": spawn_events,
		"projectile_type": "test",
	}
	var input := {
		"action_flags": MessageTypes.InputActionFlags.FIRE,
		"input_seq": 99,
	}
	ProjectileSpawnRouter.handle_fire(player, input, sys, context)
	
	assert_eq(spawn_events.size(), 1)
	assert_true(spawn_events[0].has("source_position"), "spawn event must include source_position")
	assert_eq(spawn_events[0]["source_position"], Vector2(100, 100))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script godot/tests/systems/test_projectile_spawn_router.gd`

Expected: FAIL with missing source_position key

- [ ] **Step 3: Add source_position to spawn event**

In `godot/simulation/systems/projectile_spawn_router.gd`, modify the spawn_events.append block (lines 35-43):

```gdscript
		context["spawn_events"].append({
			"projectile_id": proj.projectile_id,
			"type_id": type_id,
			"owner_player_id": player.player_id,
			"origin": proj.position,   # server-now, post fast-forward
			"direction": aim,
			"input_seq": input["input_seq"],
			"queue_time_ms": Time.get_ticks_msec(),
			"source_position": rewound_pos,  # player position for muzzle flash
		})
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script godot/tests/systems/test_projectile_spawn_router.gd`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/systems/projectile_spawn_router.gd godot/tests/systems/test_projectile_spawn_router.gd
git commit -m "feat(spawn): include source_position in authoritative spawn events"
```

---

### Task 3: Spawn Local Player Muzzle Flash from Input

**Files:**
- Modify: `godot/client_main.gd:106-116`

- [ ] **Step 1: Add muzzle flash spawning for local player**

In `godot/client_main.gd`, modify the fire press handling section (around line 106):

```gdscript
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
```

- [ ] **Step 2: Commit (method doesn't exist yet, will add in next task)**

```bash
git add godot/client_main.gd
git commit -m "feat(client): spawn muzzle flash at player position on fire input"
```

---

### Task 4: Update ProjectileEffects for Remote-Only Muzzle Flash

**Files:**
- Modify: `godot/view/projectiles/projectile_effects.gd`

- [ ] **Step 1: Add NetClient reference and local player tracking**

In `godot/view/projectiles/projectile_effects.gd`, add after line 14:

```gdscript
## Reference to net client for local player check
var _net_client: NetClient

## Set by client_main after connection
func set_net_client(net_client: NetClient) -> void:
	_net_client = net_client
```

- [ ] **Step 2: Add spawn_local_muzzle_flash method**

Add method after `_on_projectile_adopted` (after line 38):

```gdscript
## Spawns muzzle flash for local player. Called directly from input handling
## for instant feedback, bypassing the event system.
func spawn_local_muzzle_flash(pos: Vector2, dir: Vector2, type_id: int) -> void:
	var params: ProjectileEffectParams = _effect_params.get(type_id)
	if params == null or params.muzzle_scene == null:
		return
	var muzzle = params.muzzle_scene.instantiate()
	muzzle.position = pos
	if muzzle.get("direction") != null:
		muzzle.direction = dir
	add_child(muzzle)
```

- [ ] **Step 3: Modify _on_projectile_spawned to skip local player muzzle**

Replace the `_on_projectile_spawned` function:

```gdscript
func _on_projectile_spawned(event: Dictionary) -> void:
	var type_id: int = event["type_id"]
	var proj_id: int = event["projectile_id"]
	var pos: Vector2 = event["position"]
	var dir: Vector2 = event["direction"]
	var owner_id: int = event.get("owner_player_id", -1)

	# Always track projectile so we know type_id on despawn
	_active_projectiles[proj_id] = {
		"type_id": type_id,
		"last_trail": 0.0,
		"direction": dir,
	}

	var params: ProjectileEffectParams = _effect_params.get(type_id)
	if params == null:
		return

	# Skip muzzle flash for local player — handled by spawn_local_muzzle_flash
	# for instant feedback. Only spawn for remote players.
	var local_id: int = -1
	if _net_client != null:
		local_id = _net_client.get_local_player_id()
	
	if owner_id != local_id and params.muzzle_scene != null:
		# Use source_position for muzzle flash (player position, not projectile offset)
		var muzzle_pos: Vector2 = event.get("source_position", pos)
		var muzzle = params.muzzle_scene.instantiate()
		muzzle.position = muzzle_pos
		if muzzle.get("direction") != null:
			muzzle.direction = dir
		add_child(muzzle)
```

- [ ] **Step 4: Commit**

```bash
git add godot/view/projectiles/projectile_effects.gd
git commit -m "feat(effects): spawn muzzle at source_position, skip local player"
```

---

### Task 5: Wire Up NetClient Reference in client_main

**Files:**
- Modify: `godot/client_main.gd:42-48`

- [ ] **Step 1: Pass NetClient to ProjectileEffects**

In `godot/client_main.gd`, after line 48 (after `add_child(_projectile_effects)`), add:

```gdscript
	_projectile_effects.set_net_client(_net_client)
```

The full block should read:

```gdscript
	# Projectile effects system — spawns muzzle flashes, trails, and impacts.
	_projectile_effects = ProjectileEffects.new()
	_projectile_effects.initialize(_projectile_system)
	# Register frost bolt effects
	var frost_effect_params = preload("res://shared/projectiles/frost_bolt_effect_params.tres")
	_projectile_effects.register_effect_params(ProjectileType.Id.FROST_BOLT, frost_effect_params)
	add_child(_projectile_effects)
	_projectile_effects.set_net_client(_net_client)
```

- [ ] **Step 2: Commit**

```bash
git add godot/client_main.gd
git commit -m "feat(client): wire NetClient to ProjectileEffects for local player check"
```

---

### Task 6: Add source_position to EventBus projectile_spawned Events

**Files:**
- Modify: `godot/simulation/systems/projectile_system.gd:33-39, 54-60, 106-112`

- [ ] **Step 1: Update spawn_authoritative to include source_position**

The `projectile_spawned` event from `spawn_authoritative` is only used on the server (which has no view), but for consistency we should include source_position. However, `spawn_authoritative` doesn't have access to the player position — it only gets the `origin` which is already offset.

For server-side events this doesn't matter (no muzzle flash rendered). Skip this change.

- [ ] **Step 2: Update spawn_predicted to include source_position**

In `godot/simulation/systems/projectile_system.gd`, the `spawn_predicted` function also doesn't have access to the original player position — it receives `origin` which is already offset.

The cleanest fix: pass source_position through the spawn call, OR have the client_main spawn the muzzle flash before calling handle_fire (which we already do in Task 3).

Since local player muzzle flash is handled by `spawn_local_muzzle_flash` in Task 3, and remote players get `source_position` from the network message, we don't need to modify the EventBus events for `spawn_predicted`.

Skip this step — the architecture handles local via direct call, remote via network message.

- [ ] **Step 3: Update adopt_authoritative to include source_position**

In `godot/simulation/systems/projectile_system.gd`, modify the `projectile_spawned` emit in `adopt_authoritative` (line 106-112) to include `source_position`. The event already has `origin` but we need to back-calculate the player position.

Actually, `adopt_authoritative` receives `origin` which is post-fast-forward projectile position. We need to pass `source_position` as a parameter.

Modify `adopt_authoritative` signature and call sites:

In `godot/simulation/systems/projectile_system.gd`, change function signature:

```gdscript
func adopt_authoritative(
		projectile_id: int, owner_id: int, type_id: int,
		origin: Vector2, direction: Vector2,
		input_seq: int, current_rtt_ms: int, tick_age_ms: int = 0,
		source_position: Vector2 = Vector2.ZERO) -> void:
```

And update the fresh spawn event emit (around line 106):

```gdscript
	EventBus.projectile_spawned.emit({
		"projectile_id": projectile_id,
		"type_id": type_id,
		"owner_player_id": owner_id,
		"position": spawn_pos,
		"direction": direction,
		"source_position": source_position,
	})
```

- [ ] **Step 4: Update NetClient to pass source_position to adopt_authoritative**

In `godot/simulation/network/net_client.gd`, find `_handle_projectile_spawned` and update the call:

```gdscript
func _handle_projectile_spawned(bytes: PackedByteArray) -> void:
	if _projectile_system == null:
		return
	var event = NetMessage.decode_projectile_spawned(bytes)
	if event.is_empty():
		return
	_projectile_system.adopt_authoritative(
		event["projectile_id"],
		event["owner_player_id"],
		event["type_id"],
		event["origin"],
		event["direction"],
		event["input_seq"],
		get_rtt_ms(),
		event.get("tick_age_ms", 0),
		event.get("source_position", event["origin"]))
```

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/systems/projectile_system.gd godot/simulation/network/net_client.gd
git commit -m "feat(projectile): pass source_position through adopt_authoritative"
```

---

### Task 7: Update Existing Tests

**Files:**
- Modify: `godot/tests/network/test_fire_round_trip.gd`
- Modify: `godot/tests/network/test_projectile_determinism.gd`

- [ ] **Step 1: Update test_fire_round_trip event assertions**

In `godot/tests/network/test_fire_round_trip.gd`, the tests create spawn events that now need source_position. The tests mostly check projectile_id and positioning, which should still work. Run the tests to verify:

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script godot/tests/network/test_fire_round_trip.gd`

If tests fail due to message size, update the assertion on line 126:

```gdscript
	assert_eq(spawn_msg.size(), MessageTypes.Layout.PROJECTILE_SPAWNED_SIZE,
		"encoded message must be the expected size")
```

This should pass since we updated the constant.

- [ ] **Step 2: Run all projectile network tests**

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script godot/tests/network/test_projectile_network.gd`

Run: `/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script godot/tests/network/test_projectile_determinism.gd`

- [ ] **Step 3: Fix any failing tests**

If tests fail due to missing source_position in spawn_events, the `projectile_spawn_router.gd` changes from Task 2 should provide it for authoritative spawns.

- [ ] **Step 4: Commit if changes needed**

```bash
git add godot/tests/network/
git commit -m "test: update projectile network tests for source_position field"
```

---

### Task 8: Manual Testing

**Files:** None (manual verification)

- [ ] **Step 1: Rebuild class cache**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 2: Start server**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --main-pack exports/server.pck
```

Or run the server scene directly if no export exists.

- [ ] **Step 3: Connect two clients and verify**

1. Open client in browser or Godot
2. Fire frost bolt — muzzle flash should appear at player position instantly
3. Connect second client
4. Fire from first client — second client should see muzzle flash at first player's position
5. Move while firing — muzzle flash should track player position, not projectile spawn offset

- [ ] **Step 4: Verify no double muzzle flash**

For local player: only one muzzle flash should appear (from input handling, not from event)

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: muzzle flash at player position with instant local feedback

Local player: muzzle flash spawns directly from input handling for zero latency
Remote players: muzzle flash uses source_position from network message

Closes muzzle flash positioning issue."
```

---

## Summary

| Task | Description | Key Files |
|------|-------------|-----------|
| 1 | Add source_position to network message | message_types.gd, net_message.gd |
| 2 | Include source_position in spawn events | projectile_spawn_router.gd |
| 3 | Spawn local muzzle flash from input | client_main.gd |
| 4 | Update ProjectileEffects for remote-only | projectile_effects.gd |
| 5 | Wire NetClient reference | client_main.gd |
| 6 | Pass source_position through adopt | projectile_system.gd, net_client.gd |
| 7 | Update existing tests | test_fire_round_trip.gd |
| 8 | Manual testing | — |
