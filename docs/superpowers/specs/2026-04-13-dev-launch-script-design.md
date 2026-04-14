# Dev Launch Script & Debug Hotkeys

## Problem

Testing multiplayer features requires manually:
1. Starting the server
2. Starting client 1, resizing and repositioning the window
3. Starting client 2, resizing and repositioning the window
4. Switching between windows to control each player

This friction slows down iteration on movement, projectiles, and interaction testing.

## Solution

Two small additions:

### 1. `dev.sh` Launch Script

A shell script in the project root that launches server + two clients with correct window positioning:

```bash
#!/bin/bash
GODOT="${GODOT:-godot}"
PROJECT="$(cd "$(dirname "$0")" && pwd)/godot"

trap "kill 0" EXIT

$GODOT --headless --path "$PROJECT" res://server.tscn -- --port 9050 &
sleep 0.5

$GODOT --path "$PROJECT" --resolution 640x720 --position 0,25 -- --server localhost --port 9050 --dev &
$GODOT --path "$PROJECT" --resolution 640x720 --position 640,25 -- --server localhost --port 9050 --dev &

wait
```

- Single command to start everything: `./dev.sh`
- Windows positioned side-by-side (640x720 each)
- Ctrl+C kills all three processes
- Portable: uses `$GODOT` env var or `godot` from PATH

### 2. `--dev` Flag with F2 Auto-Fire

When client is launched with `--dev` CLI arg:

- F2 toggles auto-fire mode
- Auto-fire shoots at the current aim direction every 0.3s (slightly longer than the 0.25s frost bolt cooldown)
- Console message confirms "Auto-fire ON" / "Auto-fire OFF"

This enables the typical test workflow:
1. Run `./dev.sh`
2. Position player 2 where needed
3. Press F2 on player 2's window to enable auto-fire
4. Switch to player 1 and test interactions

## Implementation

### Files Changed

- **New:** `dev.sh` (project root)
- **Modified:** `godot/client_main.gd` — add `--dev` parsing and F2 handler

### client_main.gd Changes

1. Add variables:
   - `_dev_mode: bool = false`
   - `_auto_fire: bool = false`
   - `_auto_fire_timer: float = 0.0`

2. In `_ready()`: parse `--dev` from CLI args

3. In `_process()`: when `_dev_mode` and `_auto_fire` are true, decrement timer and fire when it hits zero

4. Add `_input()` or `_unhandled_input()`: on F2 press, toggle `_auto_fire` and print status

## Testing

1. Run `./dev.sh` — verify server and two clients launch side-by-side
2. Press F2 in client 2 — verify console shows "Auto-fire ON"
3. Client 2 should fire automatically every 0.5s
4. Press F2 again — verify it stops and console shows "Auto-fire OFF"
5. Ctrl+C in terminal — verify all three processes terminate
