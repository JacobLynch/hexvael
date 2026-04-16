# Hold-to-Fire Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automatic firing when the fire button is held, using existing cooldown to gate fire rate.

**Architecture:** InputProvider exposes `is_fire_held()` to report held state. client_main checks this each frame and fires when held AND cooldown allows.

**Tech Stack:** GDScript, Godot 4 Input system

---

## File Structure

| File | Change | Responsibility |
|------|--------|----------------|
| `godot/simulation/input/input_provider.gd` | Modify | Add `is_fire_held()` stub returning false |
| `godot/simulation/input/keyboard_mouse_input_provider.gd` | Modify | Override `is_fire_held()` to return `Input.is_action_pressed("fire")` |
| `godot/client_main.gd` | Modify | Check `is_fire_held()` in `_process()`, fire when held and cooldown ready |

---

### Task 1: Add is_fire_held() to InputProvider base class

**Files:**
- Modify: `godot/simulation/input/input_provider.gd:20-27`

- [ ] **Step 1: Add is_fire_held() method to base class**

Add after `consume_dodge_press()`:

```gdscript
## Returns true if the fire button is currently held down.
## Used for hold-to-fire automatic firing.
func is_fire_held() -> bool:
	return false
```

- [ ] **Step 2: Commit**

```bash
git add godot/simulation/input/input_provider.gd
git commit -m "feat(input): add is_fire_held() stub to InputProvider"
```

---

### Task 2: Implement is_fire_held() in KeyboardMouseInputProvider

**Files:**
- Modify: `godot/simulation/input/keyboard_mouse_input_provider.gd:46-50`

- [ ] **Step 1: Override is_fire_held() to check held state**

Add after `consume_fire_press()`:

```gdscript
func is_fire_held() -> bool:
	return Input.is_action_pressed("fire")
```

- [ ] **Step 2: Commit**

```bash
git add godot/simulation/input/keyboard_mouse_input_provider.gd
git commit -m "feat(input): implement is_fire_held() for keyboard/mouse"
```

---

### Task 3: Add hold-to-fire logic in client_main

**Files:**
- Modify: `godot/client_main.gd:119-139`

- [ ] **Step 1: Add hold-to-fire check after existing fire press handling**

After the `if _input_provider.consume_fire_press():` block (around line 139), add:

```gdscript
		# Hold-to-fire: continuously fire while held and cooldown allows
		if _input_provider.is_fire_held():
			if _local_player != null and _projectile_system.can_player_fire(_local_player):
				_net_client.fire_pressed_latch = true
				if _projectile_effects != null:
					var aim_dir: Vector2 = _local_player.aim_direction
					_projectile_effects.spawn_local_muzzle_flash(
						_local_player.position, aim_dir, ProjectileType.Id.FROST_BOLT)
				if _projectile_system != null:
					ProjectileSpawnRouter.handle_fire(_local_player, {
						"action_flags": MessageTypes.InputActionFlags.FIRE,
						"input_seq": _net_client._input_seq + 1,
					}, _projectile_system, {"authoritative": false})
```

- [ ] **Step 2: Commit**

```bash
git add godot/client_main.gd
git commit -m "feat(client): add hold-to-fire automatic firing"
```

---

### Task 4: Manual Testing

**Files:** None (manual verification)

- [ ] **Step 1: Start server**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -- --server
```

- [ ] **Step 2: Start client and connect**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot -- --server localhost --port 9050
```

- [ ] **Step 3: Test click-to-fire**

Click fire button once. Verify single projectile fires. Behavior should be unchanged from before.

- [ ] **Step 4: Test hold-to-fire**

Hold fire button. Verify:
- First shot fires immediately on press
- Subsequent shots fire at cooldown rate (~5/sec)
- Releasing stops firing

- [ ] **Step 5: Test ghost state blocking**

Get killed (if possible) or wait for ghost state. Hold fire button. Verify no projectiles fire during ghost state.

- [ ] **Step 6: Commit verification complete**

```bash
git commit --allow-empty -m "test: verify hold-to-fire works correctly"
```
