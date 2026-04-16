# Shooting Juice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add camera kick, sprite recoil, launch streak, and brighter muzzle light to frost bolt firing.

**Architecture:** Effects are parameterized per projectile type via ProjectileEffectParams. Camera kick is local-player only, triggered from spawn_local_muzzle_flash. Sprite recoil and launch streak work for all players, triggered via projectile_spawned event. Muzzle light is already per-projectile (scene values).

**Tech Stack:** Godot 4, GDScript, existing EventBus and ProjectileEffects systems

---

## File Structure

| File | Change |
|------|--------|
| `view/projectiles/projectile_effect_params.gd` | Add 3 new exports |
| `view/world/camera_rig.gd` | Add `add_kick()`, kick offset + decay |
| `view/world/player_view.gd` | Add `apply_recoil()`, recoil offset + decay |
| `view/world/world_view.gd` | Wire recoil to projectile_spawned |
| `view/effects/frost_bolt_streak.gd` | New script |
| `view/effects/frost_bolt_streak.tscn` | New scene |
| `view/projectiles/projectile_effects.gd` | Trigger kick + spawn streak |
| `view/projectiles/frost_bolt_muzzle.tscn` | Bump light values |
| `shared/projectiles/frost_bolt_effect_params.tres` | Set new param values |

---

## Task 1: Add new exports to ProjectileEffectParams

**Files:**
- Modify: `godot/view/projectiles/projectile_effect_params.gd`

- [ ] **Step 1: Add the three new export properties**

After `enemy_cling_scene` (around line 28), add:

```gdscript
## Camera kick amplitude on fire. 0 = no kick. Local player only.
@export var camera_kick_amplitude: float = 0.0

## Sprite recoil distance in pixels. 0 = no recoil.
@export var sprite_recoil_distance: float = 0.0

## Scene for launch streak effect. Null = no streak.
@export var launch_streak_scene: PackedScene = null
```

- [ ] **Step 2: Verify no syntax errors**

Run:
```bash
cd /Users/jacob/Repos/hexvael/godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s view/projectiles/projectile_effect_params.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 3: Commit**

```bash
cd /Users/jacob/Repos/hexvael && git add godot/view/projectiles/projectile_effect_params.gd
git commit -m "$(cat <<'EOF'
Add shooting juice params to ProjectileEffectParams

camera_kick_amplitude, sprite_recoil_distance, launch_streak_scene.
All default to 0/null for backwards compatibility.
EOF
)"
```

---

## Task 2: Implement camera kick in CameraRig

**Files:**
- Modify: `godot/view/world/camera_rig.gd`

- [ ] **Step 1: Add kick state variables**

After `var _shake_offset: Vector2 = Vector2.ZERO` (around line 17), add:

```gdscript
var _kick_offset: Vector2 = Vector2.ZERO
const KICK_DECAY: float = 20.0  ## Fast snap-back rate
```

- [ ] **Step 2: Add the add_kick method**

After `add_shake()` (around line 58), add:

```gdscript
## Apply directional camera kick (recoil opposite to shot direction).
## Local player only — called from ProjectileEffects.spawn_local_muzzle_flash().
func add_kick(direction: Vector2, amplitude: float) -> void:
	if amplitude <= 0.0:
		return
	_kick_offset = -direction.normalized() * amplitude
```

- [ ] **Step 3: Add kick decay and application in _process**

In `_process()`, after the shake decay block (around line 91), add:

```gdscript
	# Kick: directional offset, exponential decay (faster than shake)
	if _kick_offset.length_squared() > 0.001:
		_kick_offset *= exp(-KICK_DECAY * delta)
	else:
		_kick_offset = Vector2.ZERO
```

- [ ] **Step 4: Add kick to target calculation**

Change the target calculation line (around line 94) from:

```gdscript
	var target = _target_position + lookahead + _shake_offset
```

To:

```gdscript
	var target = _target_position + lookahead + _shake_offset + _kick_offset
```

- [ ] **Step 5: Verify no syntax errors**

Run:
```bash
cd /Users/jacob/Repos/hexvael/godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s view/world/camera_rig.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 6: Commit**

```bash
cd /Users/jacob/Repos/hexvael && git add godot/view/world/camera_rig.gd
git commit -m "$(cat <<'EOF'
Add camera kick to CameraRig

Directional recoil opposite to shot direction with fast exponential
snap-back. Called via add_kick(direction, amplitude).
EOF
)"
```

---

## Task 3: Implement sprite recoil in PlayerView

**Files:**
- Modify: `godot/view/world/player_view.gd`

- [ ] **Step 1: Add recoil constants and state**

After `var _base_color: Color` (around line 11), add:

```gdscript
const RECOIL_ENABLED: bool = true  ## Easy toggle to disable sprite recoil
const RECOIL_DECAY: float = 20.0

var _recoil_offset: Vector2 = Vector2.ZERO
```

- [ ] **Step 2: Add apply_recoil method**

After `update_visual_state()` (around line 63), add:

```gdscript
## Apply visual recoil nudge opposite to shot direction.
## Called by WorldView on projectile_spawned for this player.
func apply_recoil(direction: Vector2, distance: float) -> void:
	if not RECOIL_ENABLED or distance <= 0.0:
		return
	_recoil_offset = -direction.normalized() * distance
```

- [ ] **Step 3: Update _process to apply recoil offset with decay**

Replace the current `_process()` function:

```gdscript
func _process(delta: float) -> void:
	# Decay recoil
	if _recoil_offset.length_squared() > 0.001:
		_recoil_offset *= exp(-RECOIL_DECAY * delta)
	else:
		_recoil_offset = Vector2.ZERO
	
	position = _target_position + _recoil_offset
```

- [ ] **Step 4: Verify no syntax errors**

Run:
```bash
cd /Users/jacob/Repos/hexvael/godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s view/world/player_view.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 5: Commit**

```bash
cd /Users/jacob/Repos/hexvael && git add godot/view/world/player_view.gd
git commit -m "$(cat <<'EOF'
Add sprite recoil to PlayerView

Visual nudge opposite to shot direction with fast decay.
RECOIL_ENABLED constant for easy toggle.
EOF
)"
```

---

## Task 4: Wire sprite recoil in WorldView

**Files:**
- Modify: `godot/view/world/world_view.gd`

- [ ] **Step 1: Add ProjectileEffectParams lookup**

WorldView needs access to effect params to get recoil distance. Add a variable after `_prev_remote_collision_count` (around line 17):

```gdscript
var _effect_params_cache: Dictionary = {}  ## type_id -> ProjectileEffectParams
```

- [ ] **Step 2: Add method to register effect params**

After `get_player_view_position()` (around line 46), add:

```gdscript
## Register effect params for a projectile type (called during setup).
func register_effect_params(type_id: int, params: ProjectileEffectParams) -> void:
	_effect_params_cache[type_id] = params
```

- [ ] **Step 3: Connect to projectile_spawned in initialize**

In `initialize()`, after the existing signal connections (around line 40), add:

```gdscript
	EventBus.projectile_spawned.connect(_on_projectile_spawned_for_recoil)
```

- [ ] **Step 4: Add handler for sprite recoil**

After `_on_enemy_hit()` (around line 254), add:

```gdscript
func _on_projectile_spawned_for_recoil(event: Dictionary) -> void:
	var owner_id: int = event.get("owner_player_id", -1)
	var type_id: int = event.get("type_id", -1)
	var direction: Vector2 = event.get("direction", Vector2.RIGHT)
	
	if owner_id < 0 or type_id < 0:
		return
	
	var params: ProjectileEffectParams = _effect_params_cache.get(type_id)
	if params == null or params.sprite_recoil_distance <= 0.0:
		return
	
	var player_view = _player_views.get(owner_id)
	if player_view != null and player_view.has_method("apply_recoil"):
		player_view.apply_recoil(direction, params.sprite_recoil_distance)
```

- [ ] **Step 5: Disconnect in _exit_tree**

In `_exit_tree()`, add after the existing disconnects:

```gdscript
	if EventBus.projectile_spawned.is_connected(_on_projectile_spawned_for_recoil):
		EventBus.projectile_spawned.disconnect(_on_projectile_spawned_for_recoil)
```

- [ ] **Step 6: Verify no syntax errors**

Run:
```bash
cd /Users/jacob/Repos/hexvael/godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s view/world/world_view.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 7: Commit**

```bash
cd /Users/jacob/Repos/hexvael && git add godot/view/world/world_view.gd
git commit -m "$(cat <<'EOF'
Wire sprite recoil to projectile_spawned in WorldView

Looks up player view by owner_id and applies recoil based on
effect params. Works for both local and remote players.
EOF
)"
```

---

## Task 5: Create launch streak scene and script

**Files:**
- Create: `godot/view/effects/frost_bolt_streak.gd`
- Create: `godot/view/effects/frost_bolt_streak.tscn`

- [ ] **Step 1: Create the streak script**

Create `godot/view/effects/frost_bolt_streak.gd`:

```gdscript
class_name FrostBoltStreak
extends Node2D
## Launch streak that trails behind frost bolt for first few frames.
## Tracks projectile position briefly, then fades out.

const TRACK_DURATION: float = 0.08  ## How long to follow bolt
const FADE_DURATION: float = 0.1
const LINE_WIDTH: float = 2.5
const LINE_COLOR: Color = Color(0.7, 0.9, 1.0, 0.9)

var _line: Line2D
var _track_timer: float = 0.0
var _fading: bool = false
var _projectile_id: int = -1
var _projectile_system: ProjectileSystem


func initialize(start_pos: Vector2, proj_id: int, proj_system: ProjectileSystem) -> void:
	_projectile_id = proj_id
	_projectile_system = proj_system
	global_position = start_pos
	_create_line()


func _create_line() -> void:
	_line = Line2D.new()
	_line.width = LINE_WIDTH
	_line.default_color = LINE_COLOR
	_line.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_line)


func _process(delta: float) -> void:
	if _fading:
		return
	
	if _track_timer < TRACK_DURATION:
		# Update endpoint to projectile position
		if _projectile_system != null:
			var proj = _projectile_system.projectiles.get(_projectile_id)
			if proj != null:
				_line.points[1] = proj.position - global_position
		_track_timer += delta
	else:
		_start_fade()


func _start_fade() -> void:
	_fading = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(queue_free)
```

- [ ] **Step 2: Create the streak scene**

Create `godot/view/effects/frost_bolt_streak.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://frost_bolt_streak"]

[ext_resource type="Script" path="res://view/effects/frost_bolt_streak.gd" id="1_script"]

[node name="FrostBoltStreak" type="Node2D"]
script = ExtResource("1_script")
```

- [ ] **Step 3: Rebuild class cache**

Run:
```bash
cd /Users/jacob/Repos/hexvael/godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 4: Verify no syntax errors**

Run:
```bash
cd /Users/jacob/Repos/hexvael/godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s view/effects/frost_bolt_streak.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 5: Commit**

```bash
cd /Users/jacob/Repos/hexvael && git add godot/view/effects/frost_bolt_streak.gd godot/view/effects/frost_bolt_streak.tscn
git commit -m "$(cat <<'EOF'
Add frost bolt launch streak effect

Line2D that tracks projectile for 80ms then fades. Creates
dramatic acceleration feel on fire.
EOF
)"
```

---

## Task 6: Wire launch streak in ProjectileEffects

**Files:**
- Modify: `godot/view/projectiles/projectile_effects.gd`

- [ ] **Step 1: Spawn streak in _on_projectile_spawned**

In `_on_projectile_spawned()`, after tracking the projectile (around line 74), add:

```gdscript
	# Spawn launch streak if configured
	if params != null and params.launch_streak_scene != null:
		var streak = params.launch_streak_scene.instantiate()
		if streak.has_method("initialize"):
			streak.initialize(pos, proj_id, _projectile_system)
		else:
			streak.global_position = pos
		add_child(streak)
```

- [ ] **Step 2: Verify no syntax errors**

Run:
```bash
cd /Users/jacob/Repos/hexvael/godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s view/projectiles/projectile_effects.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 3: Commit**

```bash
cd /Users/jacob/Repos/hexvael && git add godot/view/projectiles/projectile_effects.gd
git commit -m "$(cat <<'EOF'
Spawn launch streak on projectile_spawned

If launch_streak_scene is set in effect params, instantiate and
initialize it at spawn position.
EOF
)"
```

---

## Task 7: Trigger camera kick in ProjectileEffects

**Files:**
- Modify: `godot/view/projectiles/projectile_effects.gd`

- [ ] **Step 1: Add camera_rig reference**

After `var _net_client: NetClient` (around line 15), add:

```gdscript
var _camera_rig: CameraRig
```

- [ ] **Step 2: Add setter for camera_rig**

After `set_net_client()` (around line 21), add:

```gdscript
func set_camera_rig(camera_rig: CameraRig) -> void:
	_camera_rig = camera_rig
```

- [ ] **Step 3: Trigger camera kick in spawn_local_muzzle_flash**

In `spawn_local_muzzle_flash()`, after spawning the muzzle (around line 59), add:

```gdscript
	# Camera kick for local player
	if _camera_rig != null and params != null and params.camera_kick_amplitude > 0.0:
		_camera_rig.add_kick(dir, params.camera_kick_amplitude)
```

- [ ] **Step 4: Verify no syntax errors**

Run:
```bash
cd /Users/jacob/Repos/hexvael/godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s view/projectiles/projectile_effects.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 5: Commit**

```bash
cd /Users/jacob/Repos/hexvael && git add godot/view/projectiles/projectile_effects.gd
git commit -m "$(cat <<'EOF'
Trigger camera kick on local player fire

Uses camera_kick_amplitude from effect params. Local player only
via spawn_local_muzzle_flash path.
EOF
)"
```

---

## Task 8: Wire camera_rig and effect_params in client_main

**Files:**
- Modify: `godot/client_main.gd`

- [ ] **Step 1: Find where ProjectileEffects is initialized**

Search for where `_projectile_effects` is set up and effect params are registered.

- [ ] **Step 2: Pass camera_rig to ProjectileEffects**

After `_projectile_effects.set_net_client(_net_client)`, add:

```gdscript
	_projectile_effects.set_camera_rig(_world_view._camera_rig)
```

- [ ] **Step 3: Register effect params with WorldView**

After registering effect params with ProjectileEffects, also register with WorldView:

```gdscript
	_world_view.register_effect_params(ProjectileType.Id.FROST_BOLT, frost_bolt_effect_params)
```

- [ ] **Step 4: Verify no syntax errors**

Run:
```bash
cd /Users/jacob/Repos/hexvael/godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s client_main.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 5: Commit**

```bash
cd /Users/jacob/Repos/hexvael && git add godot/client_main.gd
git commit -m "$(cat <<'EOF'
Wire camera_rig and effect_params for shooting juice

ProjectileEffects gets camera_rig for kick.
WorldView gets effect_params for sprite recoil lookup.
EOF
)"
```

---

## Task 9: Update frost_bolt_effect_params.tres

**Files:**
- Modify: `godot/shared/projectiles/frost_bolt_effect_params.tres`

- [ ] **Step 1: Add ext_resource for streak scene**

Update load_steps from 6 to 7, and add after the cling resource:

```
[ext_resource type="PackedScene" path="res://view/effects/frost_bolt_streak.tscn" id="6_streak"]
```

- [ ] **Step 2: Add the new parameter values**

At the end of the [resource] section, add:

```
camera_kick_amplitude = 3.0
sprite_recoil_distance = 2.0
launch_streak_scene = ExtResource("6_streak")
```

- [ ] **Step 3: Commit**

```bash
cd /Users/jacob/Repos/hexvael && git add godot/shared/projectiles/frost_bolt_effect_params.tres
git commit -m "$(cat <<'EOF'
Set shooting juice values for frost bolt

camera_kick_amplitude = 3.0, sprite_recoil_distance = 2.0,
launch_streak_scene = frost_bolt_streak.tscn
EOF
)"
```

---

## Task 10: Update muzzle light values

**Files:**
- Modify: `godot/view/projectiles/frost_bolt_muzzle.tscn`

- [ ] **Step 1: Update Light node properties**

Find the `[node name="Light"` section and change:

```
energy = 2.5
texture_scale = 0.18
```

(Was energy = 1.5, texture_scale = 0.12)

- [ ] **Step 2: Commit**

```bash
cd /Users/jacob/Repos/hexvael && git add godot/view/projectiles/frost_bolt_muzzle.tscn
git commit -m "$(cat <<'EOF'
Bump frost bolt muzzle light for better visibility

energy 1.5 -> 2.5, texture_scale 0.12 -> 0.18
Subtle but noticeable improvement.
EOF
)"
```

---

## Task 11: Integration test

**Files:** None (testing only)

- [ ] **Step 1: Rebuild class cache**

Run:
```bash
cd /Users/jacob/Repos/hexvael/godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 2: Run test suite**

Run:
```bash
cd /Users/jacob/Repos/hexvael && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd 2>&1 | tail -15
```
Expected: All tests pass

- [ ] **Step 3: Manual testing**

Start server and client, test checklist:
- [ ] Fire frost bolt — camera kicks back briefly
- [ ] Fire frost bolt — player sprite visibly recoils
- [ ] Fire frost bolt — launch streak appears and fades
- [ ] Muzzle flash is brighter/larger than before
- [ ] Remote player's shots show their sprite recoil + streak (no camera kick for you)
- [ ] Set RECOIL_ENABLED = false in player_view.gd — sprite recoil stops

- [ ] **Step 4: Final commit if fixes needed**

```bash
cd /Users/jacob/Repos/hexvael && git add -A
git commit -m "Fix integration issues in shooting juice"
```

---

## Summary

| Task | Component | Type |
|------|-----------|------|
| 1 | ProjectileEffectParams exports | Foundation |
| 2 | Camera kick in CameraRig | Effect |
| 3 | Sprite recoil in PlayerView | Effect |
| 4 | Wire recoil in WorldView | Wiring |
| 5 | Launch streak scene/script | Effect |
| 6 | Wire streak in ProjectileEffects | Wiring |
| 7 | Wire camera kick in ProjectileEffects | Wiring |
| 8 | Wire in client_main | Wiring |
| 9 | frost_bolt_effect_params values | Config |
| 10 | Muzzle light bump | Config |
| 11 | Integration test | Testing |

Total: 11 tasks, ~45-60 minutes estimated.
