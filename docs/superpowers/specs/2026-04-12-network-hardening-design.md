# Network Hardening Fixes Design

**Date:** 2026-04-12  
**Status:** Approved  
**Scope:** Tier 1 critical fixes + major issues from multiplayer audit

## Context

A comprehensive audit of the multiplayer foundation identified several potential issues. After detailed analysis, some were confirmed as real issues requiring fixes, while others were false positives where the existing implementation was correct.

## Audit Results Summary

| Issue | Verdict | Action |
|-------|---------|--------|
| EventBus signal leaks | Real issue | Fix |
| Unbounded _connection_attempts | False positive | No change |
| ProjectileView null check | Real issue | Fix |
| Reconciliation race condition | False positive | No change |
| _pending_inputs GC pressure | Minor issue | Fix |
| Unbounded _sent_snapshots | Real issue | Fix |
| Client projectile validation | False positive | No change |
| God class NetServer | Deferred | Tech debt |

## False Positives Explained

### Unbounded _connection_attempts
The dictionary IS bounded at `MAX_TRACKED_IPS = 1000` with LRU eviction in `_prune_oldest_connection_attempts()`. The while loop at line 170 removes oldest IPs until under the limit.

### Reconciliation race condition
GDScript is single-threaded. Multiple snapshots in one frame result in sequential reconciliations, each self-contained and correct. The second snapshot's `server_seq` >= first, so we discard more inputs and replay fewer.

### Client projectile validation
Server validates cooldown (`can_fire()`), input vectors (normalized, finite), and spawns authoritative projectiles. Client predictions without server confirmation auto-despawn via REJECTED reason. Server authority is maintained.

### client_main.gd signal connections
The connections at lines 42-47 are to `_net_client` instance signals, not EventBus singleton. When `client_main` is freed, `_net_client` (a child) is freed too, taking its signals with it. No leak.

## Fixes Required

### Fix 1: EventBus Signal Cleanup

**Problem:** Nodes connecting to EventBus (singleton) signals without disconnecting in `_exit_tree()` cause memory leaks and potential crashes.

**Files affected:**
- `net_server.gd:80` — connects `EventBus.enemy_died`
- `world_view.gd:39` — connects `EventBus.player_dodge_started` (partial fix exists at 235-237)
- `projectile_view.gd:26-28` — connects 3 EventBus signals

**Solution:** Add `_exit_tree()` with guard-and-disconnect pattern:

```gdscript
func _exit_tree():
    if EventBus.<signal>.is_connected(_handler):
        EventBus.<signal>.disconnect(_handler)
```

### Fix 2: ProjectileView Null Guard

**Problem:** `_projectile_system` accessed in `_process()` without null check. If freed before ProjectileView, causes crash.

**File:** `projectile_view.gd:42-46`

**Solution:** Add early return guard:

```gdscript
func _process(_delta: float) -> void:
    if _projectile_system == null:
        return
    for id in _visuals.keys():
        # ...
```

### Fix 3: Pending Inputs GC Pressure

**Problem:** `slice()` creates new array when cap exceeded, causing GC pressure.

**File:** `net_client.gd:308-310`

**Current:**
```gdscript
_pending_inputs.append(input)
if _pending_inputs.size() > MAX_PENDING_INPUTS:
    _pending_inputs = _pending_inputs.slice(-MAX_PENDING_INPUTS)
```

**Solution:** Use `pop_front()` to avoid allocation:
```gdscript
_pending_inputs.append(input)
while _pending_inputs.size() > MAX_PENDING_INPUTS:
    _pending_inputs.pop_front()
```

### Fix 4: Sent Snapshots Cleanup on ACK Timeout

**Problem:** When a client stops ACKing, `_sent_snapshots[player_id]` grows until zombie disconnection (30 seconds = 900 snapshots).

**File:** `net_server.gd:444-451`

**Solution:** Clear stale snapshots when ACK timeout triggers full snapshot fallback:

```gdscript
if _tick - baseline.tick > MessageTypes.ACK_TIMEOUT_TICKS:
    _sent_snapshots[player_id].clear()  # Clear stale unacked snapshots
    var full_msg = {
        # ...
    }
    ws.send(NetMessage.encode(full_msg))
```

This is correct because the full snapshot resets the baseline — old unacked snapshots are no longer useful for delta compression.

## Deferred: NetServer Decomposition

The 586-line `net_server.gd` handles too many responsibilities. This should be decomposed into:
- `ConnectionManager` — TCP/WebSocket, peer lifecycle
- `SnapshotManager` — building, delta compression, ACK tracking
- `RTTTracker` — round-trip measurement

**Reason for deferral:** The file works correctly, tests pass. Refactoring is a separate effort that shouldn't block these targeted fixes.

## Files to Modify

1. **net_server.gd**
   - Add `_exit_tree()` disconnecting `EventBus.enemy_died`
   - Clear `_sent_snapshots[player_id]` on ACK timeout

2. **world_view.gd**
   - Extend existing `_exit_tree()` to disconnect all NetClient signals connected in `initialize()`

3. **projectile_view.gd**
   - Add `_exit_tree()` disconnecting all 3 EventBus signals
   - Add null guard at start of `_process()`

4. **net_client.gd**
   - Replace `slice()` with `pop_front()` loop

## Testing

- Run existing test suite to verify no regressions
- Manual test: connect/disconnect multiple times, verify no memory growth
- Manual test: simulate high-latency client (pause ACKs), verify server memory stable
