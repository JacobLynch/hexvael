# Dev Launch Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Single-command launch of server + two side-by-side clients with debug hotkeys for testing.

**Architecture:** Shell script launches Godot processes with window positioning flags. Client parses `--dev` flag and enables F2 auto-fire toggle in dev mode.

**Tech Stack:** Bash, GDScript

---

## File Structure

- **Create:** `dev.sh` (project root) — launch script
- **Modify:** `godot/client_main.gd` — add `--dev` parsing and F2 auto-fire logic

---

### Task 1: Create dev.sh Launch Script

**Files:**
- Create: `dev.sh`

- [ ] **Step 1: Create the script**

```bash
#!/bin/bash
# Dev launcher: server + two side-by-side clients
# Usage: ./dev.sh
# Requires: $GODOT env var or 'godot' in PATH

GODOT="${GODOT:-godot}"
PROJECT="$(cd "$(dirname "$0")" && pwd)/godot"

trap "kill 0" EXIT

# Server (headless)
$GODOT --headless --path "$PROJECT" res://server.tscn -- --port 9050 &

sleep 0.5  # Let server bind port

# Client 1 — left half
$GODOT --path "$PROJECT" --resolution 640x720 --position 0,25 -- --server localhost --port 9050 --dev &

# Client 2 — right half
$GODOT --path "$PROJECT" --resolution 640x720 --position 640,25 -- --server localhost --port 9050 --dev &

wait
```

- [ ] **Step 2: Make executable**

Run: `chmod +x dev.sh`

- [ ] **Step 3: Verify script syntax**

Run: `bash -n dev.sh`
Expected: No output (syntax OK)

- [ ] **Step 4: Commit**

```bash
git add dev.sh
git commit -m "feat: add dev.sh launch script for server + two clients"
```

---

### Task 2: Add --dev Flag Parsing to Client

**Files:**
- Modify: `godot/client_main.gd:59-71` (CLI parsing section)

- [ ] **Step 1: Add dev mode variables**

Add these variables after line 12 (after `_projectile_effects`):

```gdscript
var _dev_mode: bool = false
var _auto_fire: bool = false
var _auto_fire_timer: float = 0.0
const AUTO_FIRE_INTERVAL: float = 0.3
```

- [ ] **Step 2: Parse --dev flag**

In the `_ready()` function, within the CLI args parsing loop (around line 67), add a case for `--dev`:

```gdscript
		if args[i] == "--dev":
			_dev_mode = true
			print("Dev mode enabled — F2 toggles auto-fire")
```

The full args parsing block becomes:

```gdscript
	# Auto-connect if CLI args provided: -- --server localhost --port 9050 --dev
	var address := ""
	var port := 0
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--server" and i + 1 < args.size():
			address = args[i + 1]
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
		if args[i] == "--dev":
			_dev_mode = true
			print("Dev mode enabled — F2 toggles auto-fire")
	if not address.is_empty():
		if port <= 0:
			port = 9050
		_on_connect_requested(address, port)
```

- [ ] **Step 3: Commit**

```bash
git add godot/client_main.gd
git commit -m "feat: add --dev flag parsing to client"
```

---

### Task 3: Add F2 Auto-Fire Toggle

**Files:**
- Modify: `godot/client_main.gd` (add _unhandled_input method)

- [ ] **Step 1: Add input handler**

Add this method after the `_process()` function (around line 136):

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if not _dev_mode:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_auto_fire = not _auto_fire
		if _auto_fire:
			_auto_fire_timer = 0.0  # Fire immediately on enable
			print("Auto-fire ON")
		else:
			print("Auto-fire OFF")
```

- [ ] **Step 2: Commit**

```bash
git add godot/client_main.gd
git commit -m "feat: add F2 toggle for auto-fire in dev mode"
```

---

### Task 4: Implement Auto-Fire Logic

**Files:**
- Modify: `godot/client_main.gd:97-133` (_process function)

- [ ] **Step 1: Add auto-fire timer logic**

In `_process()`, after the existing fire handling block (after line 125, before the projectile system tick), add:

```gdscript
		# Dev mode: auto-fire when enabled
		if _dev_mode and _auto_fire:
			_auto_fire_timer -= delta
			if _auto_fire_timer <= 0.0:
				_auto_fire_timer = AUTO_FIRE_INTERVAL
				_net_client.fire_pressed_latch = true
				if _local_player != null and _projectile_effects != null:
					var aim_dir: Vector2 = _local_player.aim_direction
					_projectile_effects.spawn_local_muzzle_flash(
						_local_player.position, aim_dir, ProjectileType.Id.FROST_BOLT)
				if _local_player != null and _projectile_system != null:
					ProjectileSpawnRouter.handle_fire(_local_player, {
						"action_flags": MessageTypes.InputActionFlags.FIRE,
						"input_seq": _net_client._input_seq + 1,
					}, _projectile_system, {"authoritative": false})
```

- [ ] **Step 2: Commit**

```bash
git add godot/client_main.gd
git commit -m "feat: implement auto-fire timer logic in dev mode"
```

---

### Task 5: Manual Testing

**Files:** None (verification only)

- [ ] **Step 1: Set GODOT environment variable**

Run: `export GODOT="/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot"`

(Or add to shell profile for persistence)

- [ ] **Step 2: Launch dev environment**

Run: `./dev.sh`

Expected:
- Server starts (terminal shows "Hexvael server starting on port 9050")
- Two client windows appear side-by-side (640x720 each)
- Both clients auto-connect and show players
- Console shows "Dev mode enabled — F2 toggles auto-fire" for each client

- [ ] **Step 3: Test auto-fire toggle**

In either client window:
1. Press F2
   - Expected: Console shows "Auto-fire ON"
   - Expected: Client fires frost bolts every ~0.3s at aim direction
2. Press F2 again
   - Expected: Console shows "Auto-fire OFF"
   - Expected: Firing stops

- [ ] **Step 4: Test cleanup**

Press Ctrl+C in terminal
Expected: All three processes terminate

- [ ] **Step 5: Commit any fixes if needed**

If issues found, fix and commit with appropriate message.
