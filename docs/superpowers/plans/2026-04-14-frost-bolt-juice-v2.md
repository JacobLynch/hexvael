# Frost Bolt Juice V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add enemy knockback + visual polish (frost cling, crack lines, muzzle vapor) to frost bolt.

**Architecture:** Knockback is simulation-layer: enemies gain mass property and stagger state, projectile_system applies knockback on hit. Visual effects are view-layer: new frost_cling scene, modifications to existing impact/muzzle scenes, wired through projectile_effects.

**Tech Stack:** Godot 4, GDScript, existing EventBus signal system

---

## File Structure

### Simulation (knockback)

| File | Change |
|------|--------|
| `simulation/entities/enemy_params.gd` | Add `mass` export |
| `simulation/entities/enemy_entity.gd` | Add knockback state, modify `advance()` |
| `shared/projectiles/projectile_params.gd` | Add `knockback_force`, `knockback_stagger` |
| `shared/projectiles/frost_bolt_params.tres` | Set knockback values |
| `simulation/systems/projectile_system.gd` | Apply knockback on enemy hit |

### View (visual effects)

| File | Change |
|------|--------|
| `view/effects/frost_cling.tscn` | New scene |
| `view/effects/frost_cling.gd` | New script |
| `view/projectiles/frost_bolt_impact.gd` | Add crack line spawning |
| `view/projectiles/frost_bolt_muzzle.tscn` | Add vapor particles |
| `view/projectiles/frost_bolt_muzzle.gd` | Trigger vapor emission |
| `view/projectiles/projectile_effect_params.gd` | Add `enemy_cling_scene` |
| `view/projectiles/projectile_effects.gd` | Pass cling scene through event |
| `view/world/world_view.gd` | Spawn frost cling on enemy hit |

---

## Task 1: Add mass to EnemyParams

**Files:**
- Modify: `godot/simulation/entities/enemy_params.gd:17` (end of file)

- [ ] **Step 1: Add mass export property**

```gdscript
# In enemy_params.gd, add at end of exports (line 17):
@export var mass: float = 1.0  ## Knockback resistance. 1.0 = light, 3.0+ = immune
```

- [ ] **Step 2: Verify no syntax errors**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s simulation/entities/enemy_params.gd 2>&1 | head -5
```
Expected: No errors (script check passes or empty output)

- [ ] **Step 3: Commit**

```bash
git add godot/simulation/entities/enemy_params.gd
git commit -m "$(cat <<'EOF'
Add mass property to EnemyParams for knockback resistance

Light enemies (mass 1.0) get full knockback, heavy enemies (mass 3.0+)
are immune. Part of frost bolt juice v2.
EOF
)"
```

---

## Task 2: Add knockback state to EnemyEntity

**Files:**
- Modify: `godot/simulation/entities/enemy_entity.gd:13` (after existing vars)

- [ ] **Step 1: Add knockback state variables**

After line 13 (`var _params: EnemyParams = null`), add:

```gdscript
# Knockback state
var knockback_velocity: Vector2 = Vector2.ZERO
var stagger_timer: float = 0.0
```

- [ ] **Step 2: Add knockback constants**

After the `State` enum (line 5), add:

```gdscript
const KNOCKBACK_FRICTION: float = 12.0  ## Velocity decay rate during stagger
```

- [ ] **Step 3: Add apply_knockback method**

Add before `to_snapshot_data()` (around line 210):

```gdscript
## Apply knockback impulse. Direction should be normalized.
## TODO(TCE): Migrate to effect system. This should become:
##   - "knockback" effect type in TCE
##   - Trigger data in projectile/gear params instead of hardcoded values
##   - Effect executor calls apply_knockback() with params from trigger
func apply_knockback(direction: Vector2, force: float, stagger: float) -> void:
	if _params == null or _params.mass >= 3.0:
		return  # Heavy enemies immune
	var actual_force: float = force / _params.mass
	var actual_stagger: float = stagger / _params.mass
	knockback_velocity = direction.normalized() * actual_force
	stagger_timer = actual_stagger
```

- [ ] **Step 4: Verify no syntax errors**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s simulation/entities/enemy_entity.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/entities/enemy_entity.gd
git commit -m "$(cat <<'EOF'
Add knockback state and apply_knockback() to EnemyEntity

Enemies gain knockback_velocity and stagger_timer state. The
apply_knockback() method respects mass-based resistance.
Includes TODO marker for future TCE migration.
EOF
)"
```

---

## Task 3: Modify EnemyEntity.advance() for stagger

**Files:**
- Modify: `godot/simulation/entities/enemy_entity.gd:28-36` (advance function)

- [ ] **Step 1: Add stagger handling at start of advance()**

Replace the current `advance()` function (starting at line 28) with:

```gdscript
func advance(dt: float, players: Array, neighbors: Array) -> void:
	# Handle knockback stagger first — skip normal AI while staggered
	if stagger_timer > 0.0:
		position += knockback_velocity * dt
		knockback_velocity *= exp(-KNOCKBACK_FRICTION * dt)
		stagger_timer -= dt
		if stagger_timer <= 0.0:
			knockback_velocity = Vector2.ZERO
			stagger_timer = 0.0
		return

	match state:
		State.SPAWNING:
			_advance_spawning(dt)
		State.IDLE:
			_advance_idle(dt, players)
		State.CHASING:
			_advance_chasing(dt, players, neighbors)
```

- [ ] **Step 2: Verify no syntax errors**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s simulation/entities/enemy_entity.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add godot/simulation/entities/enemy_entity.gd
git commit -m "$(cat <<'EOF'
Handle knockback stagger in EnemyEntity.advance()

Enemies now pause normal AI during stagger, applying knockback velocity
with exponential friction decay. Smooth slide instead of teleport.
EOF
)"
```

---

## Task 4: Add knockback params to ProjectileParams

**Files:**
- Modify: `godot/shared/projectiles/projectile_params.gd:16` (end of file)

- [ ] **Step 1: Add knockback export properties**

Add at end of file:

```gdscript
## Knockback force applied to enemies on hit. 0 = no knockback.
@export var knockback_force: float = 0.0
## Stagger duration in seconds. Enemy pauses AI during this time.
@export var knockback_stagger: float = 0.0
```

- [ ] **Step 2: Verify no syntax errors**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s shared/projectiles/projectile_params.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add godot/shared/projectiles/projectile_params.gd
git commit -m "$(cat <<'EOF'
Add knockback_force and knockback_stagger to ProjectileParams

Projectiles can now specify knockback behavior. Defaults to 0 (no knockback)
for backwards compatibility.
EOF
)"
```

---

## Task 5: Update frost_bolt_params.tres with knockback values

**Files:**
- Modify: `godot/shared/projectiles/frost_bolt_params.tres`

- [ ] **Step 1: Add knockback values to resource**

Add these lines before the closing of the resource (after `visual_scene`):

```
knockback_force = 200.0
knockback_stagger = 0.1
```

The full file should look like:

```
[gd_resource type="Resource" script_class="ProjectileParams" load_steps=2 format=3 uid="uid://frost_bolt_params"]

[ext_resource type="Script" path="res://shared/projectiles/projectile_params.gd" id="1_script"]

[resource]
script = ExtResource("1_script")
speed = 500.0
lifetime = 1.5
radius = 6.0
spawn_offset = 0.0
spawn_grace = 0.10
fire_cooldown = 0.25
impact_force = 0.0
movement_type = 0
visual_scene = "res://view/projectiles/frost_bolt_visual.tscn"
knockback_force = 200.0
knockback_stagger = 0.1
```

- [ ] **Step 2: Commit**

```bash
git add godot/shared/projectiles/frost_bolt_params.tres
git commit -m "$(cat <<'EOF'
Set knockback values for frost bolt

Light knockback: 200 force, 0.1s stagger. Punchy feedback without
drastically changing combat spacing.
EOF
)"
```

---

## Task 6: Apply knockback in projectile_system

**Files:**
- Modify: `godot/simulation/systems/projectile_system.gd:130-163` (advance function)

- [ ] **Step 1: Modify advance() to apply knockback on enemy hits**

Replace the `advance()` function with this version that applies knockback:

```gdscript
func advance(dt: float, players: Array, enemies: Array) -> Array:
	var despawned: Array = []
	var rejection_timeout_s: float = 2.0 * (_current_rtt_ms / 1000.0) + 0.1

	# Build enemy lookup for knockback application
	var enemy_lookup: Dictionary = {}
	for enemy in enemies:
		enemy_lookup[enemy.entity_id] = enemy

	for id in projectiles.keys():
		var p: ProjectileEntity = projectiles[id]
		var reason: int = p.advance(dt, _walls, players, enemies)

		# Rejection timeout for predicted projectiles (client-side only).
		# Lives here, not in ProjectileEntity.advance(), because only the system
		# holds the current RTT estimate.
		if reason == ProjectileEntity.DespawnReason.ALIVE and p.is_predicted:
			if p.time_since_spawn > rejection_timeout_s:
				reason = ProjectileEntity.DespawnReason.REJECTED

		if reason != ProjectileEntity.DespawnReason.ALIVE:
			# Apply knockback on enemy hit
			if reason == ProjectileEntity.DespawnReason.ENEMY:
				var enemy: EnemyEntity = enemy_lookup.get(p.last_hit_entity_id)
				if enemy != null and p.params.knockback_force > 0.0:
					enemy.apply_knockback(
						p.direction,
						p.params.knockback_force,
						p.params.knockback_stagger
					)

			despawned.append({
				"id": id,
				"reason": reason,
				"position": p.position,
				"target_entity_id": p.last_hit_entity_id,
			})

	for entry in despawned:
		var dead_id: int = entry["id"]
		projectiles.erase(dead_id)
		EventBus.projectile_despawned.emit({
			"projectile_id": dead_id,
			"reason": entry["reason"],
			"position": entry["position"],
			"target_entity_id": entry["target_entity_id"],
		})

	return despawned
```

- [ ] **Step 2: Verify no syntax errors**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s simulation/systems/projectile_system.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add godot/simulation/systems/projectile_system.gd
git commit -m "$(cat <<'EOF'
Apply knockback to enemies on projectile hit

When a projectile despawns due to enemy collision, apply knockback using
the projectile's direction and knockback params. Enemy mass affects the
actual displacement.
EOF
)"
```

---

## Task 7: Create frost cling effect

**Files:**
- Create: `godot/view/effects/frost_cling.gd`
- Create: `godot/view/effects/frost_cling.tscn`

- [ ] **Step 1: Create the frost cling script**

Create `godot/view/effects/frost_cling.gd`:

```gdscript
class_name FrostCling
extends Node2D
## Ice crystals that cling to an enemy after being hit by frost bolt.
## Follows the target entity and fades out.

const LIFETIME: float = 0.3
const CRYSTAL_COUNT: int = 4
const DRIFT_SPEED: float = 15.0

var target_node: Node2D = null
var _crystals: Array[Polygon2D] = []
var _crystal_velocities: Array[Vector2] = []


func _ready() -> void:
	_spawn_crystals()
	_start_fade()


func _spawn_crystals() -> void:
	for i in CRYSTAL_COUNT:
		var crystal := Polygon2D.new()
		var size: float = 3.0 + randf() * 4.0
		# Small angular shard shape
		crystal.polygon = PackedVector2Array([
			Vector2(-size, 0),
			Vector2(0, -size * 0.6),
			Vector2(size * 0.8, 0),
			Vector2(0, size * 0.5),
		])
		crystal.color = Color(0.85, 0.95, 1.0, 0.9)
		crystal.rotation = randf() * TAU
		# Random offset from center
		var offset_angle: float = randf() * TAU
		var offset_dist: float = 8.0 + randf() * 12.0
		crystal.position = Vector2.from_angle(offset_angle) * offset_dist
		add_child(crystal)
		_crystals.append(crystal)
		# Drift outward slowly
		_crystal_velocities.append(Vector2.from_angle(offset_angle) * DRIFT_SPEED)


func _start_fade() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, LIFETIME)
	tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	# Follow target if valid
	if is_instance_valid(target_node):
		global_position = target_node.global_position

	# Drift crystals outward
	for i in _crystals.size():
		if i < _crystal_velocities.size():
			_crystals[i].position += _crystal_velocities[i] * delta
			_crystals[i].rotation += (randf() - 0.5) * 3.0 * delta
```

- [ ] **Step 2: Create the frost cling scene**

Create `godot/view/effects/frost_cling.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://frost_cling"]

[ext_resource type="Script" path="res://view/effects/frost_cling.gd" id="1_script"]

[node name="FrostCling" type="Node2D"]
script = ExtResource("1_script")
```

- [ ] **Step 3: Rebuild class cache**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 4: Verify no syntax errors**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s view/effects/frost_cling.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add godot/view/effects/frost_cling.gd godot/view/effects/frost_cling.tscn
git commit -m "$(cat <<'EOF'
Add frost cling particle effect

Ice crystals that attach to enemies on hit and drift outward while fading.
Provides visual confirmation of hits beyond the white flash.
EOF
)"
```

---

## Task 8: Add impact crack lines to FrostBoltImpact

**Files:**
- Modify: `godot/view/projectiles/frost_bolt_impact.gd`

- [ ] **Step 1: Add crack line constants**

After the existing constants (line 6), add:

```gdscript
const CRACK_LINE_COUNT: int = 5
const CRACK_LINE_MIN_LENGTH: float = 20.0
const CRACK_LINE_MAX_LENGTH: float = 40.0
const CRACK_LINE_FADE_TIME: float = 0.15
```

- [ ] **Step 2: Add crack line spawning method**

Add before `_animate()`:

```gdscript
func _spawn_crack_lines() -> void:
	for i in CRACK_LINE_COUNT:
		var line := Line2D.new()
		var angle: float = (float(i) / CRACK_LINE_COUNT) * TAU + randf() * 0.5
		var length: float = CRACK_LINE_MIN_LENGTH + randf() * (CRACK_LINE_MAX_LENGTH - CRACK_LINE_MIN_LENGTH)
		var end_point: Vector2 = Vector2.from_angle(angle) * length

		line.points = PackedVector2Array([Vector2.ZERO, end_point])
		line.width = 1.5
		line.default_color = Color(1.0, 1.0, 1.0, 0.9)
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(line)

		# Fade out
		var tween := create_tween()
		tween.tween_property(line, "modulate:a", 0.0, CRACK_LINE_FADE_TIME)
```

- [ ] **Step 3: Call crack line spawning in _ready()**

Modify `_ready()` to also spawn crack lines:

```gdscript
func _ready() -> void:
	_spawn_fragments()
	_spawn_crack_lines()
	_animate()
```

- [ ] **Step 4: Verify no syntax errors**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s view/projectiles/frost_bolt_impact.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add godot/view/projectiles/frost_bolt_impact.gd
git commit -m "$(cat <<'EOF'
Add impact crack lines to frost bolt

Thin white lines radiate from impact point, adding visual weight.
5 lines, 20-40px length, fade over 150ms.
EOF
)"
```

---

## Task 9: Add muzzle vapor to FrostBoltMuzzle

**Files:**
- Modify: `godot/view/projectiles/frost_bolt_muzzle.tscn`
- Modify: `godot/view/projectiles/frost_bolt_muzzle.gd`

- [ ] **Step 1: Add vapor particles node to scene**

Add a new CPUParticles2D node to `frost_bolt_muzzle.tscn`. Insert before the closing of the scene (after the Light node):

```
[node name="Vapor" type="CPUParticles2D" parent="."]
emitting = false
amount = 6
lifetime = 0.25
one_shot = true
explosiveness = 0.6
direction = Vector2(1, 0)
spread = 45.0
gravity = Vector2(0, 0)
initial_velocity_min = 15.0
initial_velocity_max = 35.0
scale_amount_min = 3.0
scale_amount_max = 6.0
color = Color(0.85, 0.92, 1.0, 0.4)
```

- [ ] **Step 2: Add vapor reference to script**

In `frost_bolt_muzzle.gd`, after the existing `@onready` vars (line 11), add:

```gdscript
@onready var vapor: CPUParticles2D = $Vapor
```

- [ ] **Step 3: Trigger vapor emission**

In `_ready()`, after `particles.emitting = true` (line 17), add:

```gdscript
	if vapor:
		vapor.emitting = true
```

- [ ] **Step 4: Verify no syntax errors**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s view/projectiles/frost_bolt_muzzle.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add godot/view/projectiles/frost_bolt_muzzle.tscn godot/view/projectiles/frost_bolt_muzzle.gd
git commit -m "$(cat <<'EOF'
Add muzzle vapor to frost bolt

Soft white/blue particles puff outward on fire, selling the cold element.
6 particles, 250ms lifetime, subtle opacity.
EOF
)"
```

---

## Task 10: Wire frost cling to projectile_effects and WorldView

**Files:**
- Modify: `godot/view/projectiles/projectile_effect_params.gd`
- Modify: `godot/shared/projectiles/frost_bolt_effect_params.tres`
- Modify: `godot/view/projectiles/projectile_effects.gd`
- Modify: `godot/view/world/world_view.gd`

- [ ] **Step 1: Add enemy_cling_scene to ProjectileEffectParams**

In `godot/view/projectiles/projectile_effect_params.gd`, add after `enemy_flash_duration` (line 25):

```gdscript
## Scene to spawn attached to enemy on hit (e.g., frost crystals). Null = none.
@export var enemy_cling_scene: PackedScene = null
```

- [ ] **Step 2: Update frost_bolt_effect_params.tres**

Add an ext_resource for the frost cling scene. Update the file to:

```
[gd_resource type="Resource" script_class="ProjectileEffectParams" load_steps=6 format=3 uid="uid://frost_bolt_effect_params"]

[ext_resource type="Script" path="res://view/projectiles/projectile_effect_params.gd" id="1_script"]
[ext_resource type="PackedScene" path="res://view/projectiles/frost_bolt_muzzle.tscn" id="2_muzzle"]
[ext_resource type="PackedScene" path="res://view/projectiles/frost_bolt_impact.tscn" id="3_impact"]
[ext_resource type="PackedScene" path="res://view/projectiles/frost_bolt_shard.tscn" id="4_shard"]
[ext_resource type="PackedScene" path="res://view/effects/frost_cling.tscn" id="5_cling"]

[resource]
script = ExtResource("1_script")
muzzle_scene = ExtResource("2_muzzle")
impact_scene = ExtResource("3_impact")
expire_scene = null
trail_interval = 0.1
trail_scene = ExtResource("4_shard")
enemy_flash_color = Color(0.8, 0.95, 1, 1)
enemy_flash_duration = 0.1
enemy_cling_scene = ExtResource("5_cling")
```

- [ ] **Step 3: Pass cling_scene through enemy_hit event**

In `godot/view/projectiles/projectile_effects.gd`, modify `_flash_enemy()` (around line 140) to also pass cling scene:

```gdscript
func _flash_enemy(entity_id: int, color: Color, duration: float, cling_scene: PackedScene = null) -> void:
	EventBus.enemy_hit.emit({
		"entity_id": entity_id,
		"flash_color": color,
		"flash_duration": duration,
		"cling_scene": cling_scene,
	})
```

- [ ] **Step 4: Update _flash_enemy call to include cling_scene**

In `_on_projectile_despawned()`, change the `_flash_enemy` call (around line 132) to:

```gdscript
				_flash_enemy(target_id, params.enemy_flash_color, params.enemy_flash_duration, params.enemy_cling_scene)
```

- [ ] **Step 5: Handle cling_scene in WorldView**

In `godot/view/world/world_view.gd`, modify `_on_enemy_hit()` (around line 236) to spawn cling effect:

```gdscript
func _on_enemy_hit(event: Dictionary) -> void:
	var entity_id: int = event.get("entity_id", -1)
	var flash_color: Color = event.get("flash_color", Color.WHITE)
	var flash_duration: float = event.get("flash_duration", 0.1)
	var cling_scene: PackedScene = event.get("cling_scene", null)

	if entity_id < 0:
		return

	var enemy_view = _enemy_views.get(entity_id)
	if enemy_view != null:
		if enemy_view.has_method("flash_hit"):
			enemy_view.flash_hit(flash_color, flash_duration)
		# Spawn cling effect attached to enemy
		if cling_scene != null:
			var cling = cling_scene.instantiate()
			cling.target_node = enemy_view
			cling.global_position = enemy_view.global_position
			add_child(cling)
```

- [ ] **Step 6: Verify no syntax errors**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s view/projectiles/projectile_effects.gd 2>&1 | head -5
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --check-only -s view/world/world_view.gd 2>&1 | head -5
```
Expected: No errors

- [ ] **Step 7: Commit**

```bash
git add godot/view/projectiles/projectile_effect_params.gd godot/shared/projectiles/frost_bolt_effect_params.tres godot/view/projectiles/projectile_effects.gd godot/view/world/world_view.gd
git commit -m "$(cat <<'EOF'
Wire frost cling effect to enemy hits

ProjectileEffectParams gains enemy_cling_scene. When a frost bolt hits
an enemy, WorldView spawns ice crystals that follow the enemy while fading.
EOF
)"
```

---

## Task 11: Manual integration test

**Files:** None (testing only)

- [ ] **Step 1: Rebuild class cache**

Run:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 2: Start server**

Run in terminal 1:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless -s simulation/network/net_server.gd
```

- [ ] **Step 3: Start client and test**

Run in terminal 2:
```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot
```

Test checklist:
- [ ] Fire frost bolt at a light enemy — enemy should bump backward in bolt direction
- [ ] Enemy resumes movement after ~100ms stagger
- [ ] Frost cling particles appear on hit enemy and follow briefly
- [ ] Impact shows crack lines radiating outward
- [ ] Muzzle flash includes vapor puff
- [ ] All effects work for both local and remote projectiles

- [ ] **Step 4: Final commit (if any fixes needed)**

If any issues found, fix and commit with:
```bash
git add -A
git commit -m "Fix integration issues in frost bolt juice v2"
```

---

## Summary

| Task | Component | Type |
|------|-----------|------|
| 1-3 | Enemy knockback state | Simulation |
| 4-6 | Projectile knockback params + application | Simulation |
| 7 | Frost cling effect scene | View |
| 8 | Impact crack lines | View |
| 9 | Muzzle vapor | View |
| 10 | Wire frost cling (effect params + WorldView) | View |
| 11 | Integration test | Testing |

Total: 11 tasks, ~45-60 minutes estimated.
