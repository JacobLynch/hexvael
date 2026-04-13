# Network Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix memory leaks from EventBus signal connections, add defensive null guards, and optimize memory usage in network code.

**Architecture:** Four targeted fixes to existing files. No new files created. Each fix is independent and can be tested/committed separately.

**Tech Stack:** GDScript, Godot 4

**Spec:** `docs/superpowers/specs/2026-04-12-network-hardening-design.md`

---

## File Changes Overview

| File | Changes |
|------|---------|
| `godot/simulation/network/net_server.gd` | Add `_exit_tree()`, clear sent snapshots on ACK timeout |
| `godot/view/world/world_view.gd` | Extend `_exit_tree()` to disconnect NetClient signals |
| `godot/view/projectiles/projectile_view.gd` | Add `_exit_tree()`, add null guard in `_process()` |
| `godot/simulation/network/net_client.gd` | Replace `slice()` with `pop_front()` loop |

---

### Task 1: Add EventBus Signal Cleanup to NetServer

**Files:**
- Modify: `godot/simulation/network/net_server.gd`

**Context:** Line 80 connects `EventBus.enemy_died.connect(_on_enemy_died)` but never disconnects.

- [ ] **Step 1: Add _exit_tree function**

Add at end of file, before closing (after `get_enemy_system()` function):

```gdscript
func _exit_tree():
	if EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.disconnect(_on_enemy_died)
```

- [ ] **Step 2: Run tests to verify no regression**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script tests/test_runner.gd -- --filter=network
```

Expected: All network tests pass.

- [ ] **Step 3: Commit**

```bash
git add godot/simulation/network/net_server.gd
git commit -m "fix(net_server): disconnect EventBus.enemy_died on exit

Prevents memory leak when NetServer node is freed while
EventBus singleton retains reference to freed handler."
```

---

### Task 2: Clear Sent Snapshots on ACK Timeout

**Files:**
- Modify: `godot/simulation/network/net_server.gd:444-451`

**Context:** When ACK timeout triggers, we send a full snapshot but don't clear stale unacked snapshots. This can accumulate 900 snapshots (30s of zombie timeout × 30Hz) per non-responding client.

- [ ] **Step 1: Locate the ACK timeout block**

Find the block starting at line 444:
```gdscript
if _tick - baseline.tick > MessageTypes.ACK_TIMEOUT_TICKS:
    var full_msg = {
```

- [ ] **Step 2: Add clear before sending full snapshot**

Modify the block to clear stale snapshots:

```gdscript
			if _tick - baseline.tick > MessageTypes.ACK_TIMEOUT_TICKS:
				# Client stopped ACKing — clear stale unacked snapshots.
				# The full snapshot below resets the baseline, so old deltas
				# are no longer useful for compression.
				_sent_snapshots[player_id].clear()
				var full_msg = {
					"type": MessageTypes.Binary.FULL_SNAPSHOT,
					"tick": _tick,
					"entities": current_snap.to_entity_array(),
					"enemy_entities": current_snap.to_enemy_entity_array(),
				}
				ws.send(NetMessage.encode(full_msg))
```

- [ ] **Step 3: Run tests to verify no regression**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script tests/test_runner.gd -- --filter=network
```

Expected: All network tests pass.

- [ ] **Step 4: Commit**

```bash
git add godot/simulation/network/net_server.gd
git commit -m "fix(net_server): clear stale snapshots on ACK timeout

When a client stops ACKing, unacked snapshots accumulate until
zombie timeout (30s = 900 snapshots). Now we clear them when
falling back to full snapshot mode, since the baseline resets
and old deltas become useless anyway."
```

---

### Task 3: Add EventBus Signal Cleanup to ProjectileView

**Files:**
- Modify: `godot/view/projectiles/projectile_view.gd`

**Context:** Lines 26-28 connect three EventBus signals but never disconnect.

- [ ] **Step 1: Add _exit_tree function**

Add at end of file:

```gdscript
func _exit_tree() -> void:
	if EventBus.projectile_spawned.is_connected(_on_spawned):
		EventBus.projectile_spawned.disconnect(_on_spawned)
	if EventBus.projectile_despawned.is_connected(_on_despawned):
		EventBus.projectile_despawned.disconnect(_on_despawned)
	if EventBus.projectile_adopted.is_connected(_on_adopted):
		EventBus.projectile_adopted.disconnect(_on_adopted)
```

- [ ] **Step 2: Run tests to verify no regression**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script tests/test_runner.gd -- --filter=projectile
```

Expected: All projectile tests pass.

- [ ] **Step 3: Commit**

```bash
git add godot/view/projectiles/projectile_view.gd
git commit -m "fix(projectile_view): disconnect EventBus signals on exit

Prevents memory leak when ProjectileView node is freed while
EventBus singleton retains references to freed handlers."
```

---

### Task 4: Add Null Guard to ProjectileView._process

**Files:**
- Modify: `godot/view/projectiles/projectile_view.gd:42-46`

**Context:** `_projectile_system` is accessed without null check. Defensive guard prevents crash if tree structure changes.

- [ ] **Step 1: Add null guard at start of _process**

Modify the function:

```gdscript
func _process(_delta: float) -> void:
	if _projectile_system == null:
		return
	for id in _visuals.keys():
		var proj: ProjectileEntity = _projectile_system.projectiles.get(id)
		if proj != null:
			_visuals[id].position = proj.position
```

- [ ] **Step 2: Run tests to verify no regression**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script tests/test_runner.gd -- --filter=projectile
```

Expected: All projectile tests pass.

- [ ] **Step 3: Commit**

```bash
git add godot/view/projectiles/projectile_view.gd
git commit -m "fix(projectile_view): add null guard in _process

Defensive check prevents crash if _projectile_system is freed
before ProjectileView (e.g., manual free or tree restructure)."
```

---

### Task 5: Extend WorldView _exit_tree for NetClient Signals

**Files:**
- Modify: `godot/view/world/world_view.gd:235-237`

**Context:** `_exit_tree()` exists and disconnects `EventBus.player_dodge_started`, but the `initialize()` function at lines 22-27 connects to multiple `_net_client` signals that should also be disconnected.

Note: These are instance signals (not EventBus), so they'd be cleaned up when `_net_client` is freed. However, `WorldView` might outlive `_net_client` in some scenarios (e.g., if `_net_client` is manually freed). Adding cleanup is defensive.

- [ ] **Step 1: Extend _exit_tree to disconnect NetClient signals**

Replace the existing `_exit_tree()` function:

```gdscript
func _exit_tree():
	if EventBus.player_dodge_started.is_connected(_on_any_dodge_started):
		EventBus.player_dodge_started.disconnect(_on_any_dodge_started)
	if _net_client != null:
		if _net_client.connected.is_connected(_on_connected):
			_net_client.connected.disconnect(_on_connected)
		if _net_client.disconnected.is_connected(_on_disconnected):
			_net_client.disconnected.disconnect(_on_disconnected)
		if _net_client.player_joined.is_connected(_on_player_joined):
			_net_client.player_joined.disconnect(_on_player_joined)
		if _net_client.player_left.is_connected(_on_player_left):
			_net_client.player_left.disconnect(_on_player_left)
		if _net_client.snapshot_received.is_connected(_on_snapshot):
			_net_client.snapshot_received.disconnect(_on_snapshot)
		if _net_client.enemy_died_received.is_connected(_on_enemy_died):
			_net_client.enemy_died_received.disconnect(_on_enemy_died)
```

- [ ] **Step 2: Run tests to verify no regression**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script tests/test_runner.gd
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add godot/view/world/world_view.gd
git commit -m "fix(world_view): disconnect all signals on exit

Extends _exit_tree to disconnect NetClient signals connected
in initialize(). Defensive cleanup for edge cases where
WorldView outlives NetClient."
```

---

### Task 6: Optimize Pending Inputs Array

**Files:**
- Modify: `godot/simulation/network/net_client.gd:308-310`

**Context:** `slice()` creates a new array when cap exceeded, causing GC pressure. Replace with `pop_front()` which modifies in-place.

- [ ] **Step 1: Locate the pending inputs cap logic**

Find lines 308-310:
```gdscript
_pending_inputs.append(input)
if _pending_inputs.size() > MAX_PENDING_INPUTS:
    _pending_inputs = _pending_inputs.slice(-MAX_PENDING_INPUTS)
```

- [ ] **Step 2: Replace slice with pop_front loop**

```gdscript
	_pending_inputs.append(input)
	while _pending_inputs.size() > MAX_PENDING_INPUTS:
		_pending_inputs.pop_front()
```

- [ ] **Step 3: Run tests to verify no regression**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script tests/test_runner.gd -- --filter=network
```

Expected: All network tests pass.

- [ ] **Step 4: Commit**

```bash
git add godot/simulation/network/net_client.gd
git commit -m "perf(net_client): use pop_front instead of slice for pending inputs

slice() allocates a new array when cap exceeded, causing GC
pressure during server stalls. pop_front() modifies in-place.
O(n) cost is negligible for 60-element cap."
```

---

### Task 7: Final Verification

- [ ] **Step 1: Run full test suite**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script tests/test_runner.gd
```

Expected: All tests pass.

- [ ] **Step 2: Manual smoke test**

1. Start server: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless scenes/server.tscn`
2. Start client: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot scenes/client.tscn -- --server localhost --port 9050`
3. Move around, fire projectiles, verify no errors in console
4. Disconnect client, reconnect, verify no crashes

- [ ] **Step 3: Update plan status**

Mark this plan as complete in the file header if all tasks succeeded.
