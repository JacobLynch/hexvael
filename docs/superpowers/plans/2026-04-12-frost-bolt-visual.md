# Frost Bolt Visual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform placeholder projectile into a juicy frost bolt with shaders, dynamic lighting, and satisfying effects.

**Architecture:** Layered effect system — reusable shaders in `view/shaders/`, effect scenes in `view/projectiles/`, coordinated by `ProjectileEffects` node. Keeps `ProjectileView` thin. All view-layer, no simulation changes.

**Tech Stack:** GDScript, Godot shaders (canvas_item), CPUParticles2D, PointLight2D, Tween

---

## File Structure

```
godot/view/shaders/                    # NEW directory
  chromatic_aberration.gdshader        # Shared shader, reusable
  pulse_glow.gdshader                  # Shared shader, reusable

godot/view/projectiles/
  projectile_view.gd                   # MODIFY: delegate to ProjectileEffects
  projectile_effect_params.gd          # NEW: resource class
  projectile_effects.gd                # NEW: spawns muzzle/impact/trail
  frost_bolt_visual.tscn               # NEW: bolt scene
  frost_bolt_visual.gd                 # NEW: light pulse sync
  frost_bolt_muzzle.tscn               # NEW: muzzle flash scene
  frost_bolt_impact.tscn               # NEW: impact shatter scene
  frost_bolt_shard.tscn                # NEW: trail shard scene

godot/shared/projectiles/
  frost_bolt_params.tres               # NEW: ProjectileParams resource
  frost_bolt_effect_params.tres        # NEW: ProjectileEffectParams resource

godot/view/world/
  enemy_view.gd                        # MODIFY: add flash_hit() method
```

---

### Task 1: Create Shared Shaders Directory and Chromatic Aberration Shader

**Files:**
- Create: `godot/view/shaders/chromatic_aberration.gdshader`

- [ ] **Step 1: Create shaders directory**

```bash
mkdir -p godot/view/shaders
```

- [ ] **Step 2: Create chromatic aberration shader**

Create `godot/view/shaders/chromatic_aberration.gdshader`:

```glsl
shader_type canvas_item;

uniform float offset : hint_range(0.0, 10.0) = 2.0;
uniform float strength : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    vec2 center = vec2(0.5, 0.5);
    vec2 dir = normalize(UV - center);
    float edge = length(UV - center) * 2.0;
    
    vec4 col = texture(TEXTURE, UV);
    vec4 r = texture(TEXTURE, UV - dir * offset * TEXTURE_PIXEL_SIZE * edge);
    vec4 b = texture(TEXTURE, UV + dir * offset * TEXTURE_PIXEL_SIZE * edge);
    
    COLOR = vec4(
        mix(col.r, r.r, strength * edge),
        col.g,
        mix(col.b, b.b, strength * edge),
        col.a
    );
}
```

- [ ] **Step 3: Commit**

```bash
git add godot/view/shaders/chromatic_aberration.gdshader
git commit -m "feat(view): add chromatic aberration shader for arcane effects"
```

---

### Task 2: Create Pulse Glow Shader

**Files:**
- Create: `godot/view/shaders/pulse_glow.gdshader`

- [ ] **Step 1: Create pulse glow shader**

Create `godot/view/shaders/pulse_glow.gdshader`:

```glsl
shader_type canvas_item;

uniform float speed : hint_range(1.0, 30.0) = 12.0;
uniform float min_intensity : hint_range(0.0, 1.0) = 0.8;
uniform vec4 glow_color : source_color = vec4(0.55, 0.63, 1.0, 1.0);

void fragment() {
    float pulse = min_intensity + (1.0 - min_intensity) * (0.5 + 0.5 * sin(TIME * speed));
    vec4 col = texture(TEXTURE, UV);
    COLOR = vec4(col.rgb * glow_color.rgb * pulse, col.a * glow_color.a);
}
```

- [ ] **Step 2: Commit**

```bash
git add godot/view/shaders/pulse_glow.gdshader
git commit -m "feat(view): add pulse glow shader for breathing light effects"
```

---

### Task 3: Create ProjectileEffectParams Resource Class

**Files:**
- Create: `godot/view/projectiles/projectile_effect_params.gd`
- Test: Manual verification via editor

- [ ] **Step 1: Create the resource class**

Create `godot/view/projectiles/projectile_effect_params.gd`:

```gdscript
class_name ProjectileEffectParams
extends Resource
## Configuration for projectile visual effects (muzzle flash, impact, trails).
## Each projectile type can have its own effect params resource.

## Scene spawned at player position when projectile fires. Null = no muzzle flash.
@export var muzzle_scene: PackedScene

## Scene spawned at impact point on collision. Null = no impact effect.
@export var impact_scene: PackedScene

## Scene spawned at impact point on lifetime expiry (no collision). Null = no effect.
@export var expire_scene: PackedScene

## Seconds between trail shard spawns while projectile flies. 0 = disabled.
@export var trail_interval: float = 0.0

## Scene to spawn for trail shards. Required if trail_interval > 0.
@export var trail_scene: PackedScene

## Color to flash enemies on hit.
@export var enemy_flash_color: Color = Color(0.8, 0.95, 1.0, 1.0)

## Duration of enemy flash in seconds.
@export var enemy_flash_duration: float = 0.1
```

- [ ] **Step 2: Rebuild Godot class cache**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 3: Commit**

```bash
git add godot/view/projectiles/projectile_effect_params.gd
git commit -m "feat(view): add ProjectileEffectParams resource class"
```

---

### Task 4: Create Frost Bolt Visual Scene

**Files:**
- Create: `godot/view/projectiles/frost_bolt_visual.gd`
- Create: `godot/view/projectiles/frost_bolt_visual.tscn`

- [ ] **Step 1: Create the visual script**

Create `godot/view/projectiles/frost_bolt_visual.gd`:

```gdscript
class_name FrostBoltVisual
extends Node2D
## Visual representation of the frost bolt projectile.
## Handles light pulsing synchronized with the glow shader.

@onready var light: PointLight2D = $Light
@onready var motes: CPUParticles2D = $Motes

const PULSE_SPEED: float = 12.0
const MIN_ENERGY: float = 0.8
const MAX_ENERGY: float = 1.2

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	if light:
		var pulse = MIN_ENERGY + (MAX_ENERGY - MIN_ENERGY) * (0.5 + 0.5 * sin(_time * PULSE_SPEED))
		light.energy = pulse
```

- [ ] **Step 2: Create the visual scene**

Create `godot/view/projectiles/frost_bolt_visual.tscn`:

```
[gd_scene load_steps=5 format=3 uid="uid://frost_bolt_visual"]

[ext_resource type="Script" path="res://view/projectiles/frost_bolt_visual.gd" id="1_script"]
[ext_resource type="Shader" path="res://view/shaders/chromatic_aberration.gdshader" id="2_shader"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_bolt"]
shader = ExtResource("2_shader")
shader_parameter/offset = 2.5
shader_parameter/strength = 0.25

[sub_resource type="Gradient" id="Gradient_motes"]
colors = PackedColorArray(0.7, 0.85, 1, 0.8, 0.5, 0.7, 1, 0)

[sub_resource type="GradientTexture1D" id="GradientTexture_motes"]
gradient = SubResource("Gradient_motes")

[node name="FrostBoltVisual" type="Node2D"]
script = ExtResource("1_script")

[node name="Glow" type="Polygon2D" parent="."]
color = Color(0.4, 0.6, 1, 0.3)
polygon = PackedVector2Array(-30, 0, -18, -10, 24, -8, 36, 0, 24, 8, -18, 10)

[node name="Core" type="Polygon2D" parent="."]
material = SubResource("ShaderMaterial_bolt")
color = Color(0.67, 0.87, 1, 1)
polygon = PackedVector2Array(-25, 0, -15, -7, 20, -5, 30, 0, 20, 5, -15, 7)

[node name="CenterLine" type="Line2D" parent="."]
points = PackedVector2Array(-15, 0, 15, 0)
width = 2.0
default_color = Color(1, 1, 1, 0.9)

[node name="Light" type="PointLight2D" parent="."]
color = Color(0.55, 0.75, 1, 1)
energy = 1.0
texture_scale = 0.15
blend_mode = 1

[node name="Motes" type="CPUParticles2D" parent="."]
emitting = true
amount = 6
lifetime = 0.4
explosiveness = 0.0
emission_shape = 1
emission_sphere_radius = 15.0
direction = Vector2(-1, 0)
spread = 30.0
initial_velocity_min = 20.0
initial_velocity_max = 40.0
scale_amount_min = 1.5
scale_amount_max = 3.0
color = Color(0.7, 0.85, 1, 0.7)
color_ramp = SubResource("GradientTexture_motes")
```

- [ ] **Step 3: Rebuild Godot class cache**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 4: Commit**

```bash
git add godot/view/projectiles/frost_bolt_visual.gd godot/view/projectiles/frost_bolt_visual.tscn
git commit -m "feat(view): add frost bolt visual scene with shader and light"
```

---

### Task 5: Create Frost Bolt Muzzle Flash Scene

**Files:**
- Create: `godot/view/projectiles/frost_bolt_muzzle.gd`
- Create: `godot/view/projectiles/frost_bolt_muzzle.tscn`

- [ ] **Step 1: Create the muzzle flash script**

Create `godot/view/projectiles/frost_bolt_muzzle.gd`:

```gdscript
class_name FrostBoltMuzzle
extends Node2D
## Muzzle flash effect for frost bolt. Self-destructs after animation.

const DURATION: float = 0.15

var direction: Vector2 = Vector2.RIGHT

@onready var flash: Polygon2D = $Flash
@onready var particles: CPUParticles2D = $Particles
@onready var light: PointLight2D = $Light


func _ready() -> void:
	rotation = direction.angle()
	if particles:
		particles.emitting = true
	_animate()


func _animate() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Flash expands and fades
	if flash:
		flash.scale = Vector2(0.5, 0.5)
		tween.tween_property(flash, "scale", Vector2(1.5, 1.5), DURATION)
		tween.tween_property(flash, "modulate:a", 0.0, DURATION)
	
	# Light fades
	if light:
		tween.tween_property(light, "energy", 0.0, DURATION * 0.7)
	
	tween.chain().tween_callback(queue_free)
```

- [ ] **Step 2: Create the muzzle flash scene**

Create `godot/view/projectiles/frost_bolt_muzzle.tscn`:

```
[gd_scene load_steps=3 format=3 uid="uid://frost_bolt_muzzle"]

[ext_resource type="Script" path="res://view/projectiles/frost_bolt_muzzle.gd" id="1_script"]

[sub_resource type="Gradient" id="Gradient_particles"]
colors = PackedColorArray(0.8, 0.9, 1, 0.9, 0.5, 0.7, 1, 0)

[sub_resource type="GradientTexture1D" id="GradientTexture_particles"]
gradient = SubResource("Gradient_particles")

[node name="FrostBoltMuzzle" type="Node2D"]
script = ExtResource("1_script")

[node name="Flash" type="Polygon2D" parent="."]
color = Color(0.9, 0.95, 1, 0.9)
polygon = PackedVector2Array(0, 0, 20, -8, 25, 0, 20, 8)

[node name="Particles" type="CPUParticles2D" parent="."]
emitting = false
one_shot = true
explosiveness = 0.9
amount = 8
lifetime = 0.2
emission_shape = 0
direction = Vector2(1, 0)
spread = 30.0
initial_velocity_min = 100.0
initial_velocity_max = 180.0
scale_amount_min = 2.0
scale_amount_max = 4.0
color = Color(0.75, 0.88, 1, 0.85)
color_ramp = SubResource("GradientTexture_particles")

[node name="Light" type="PointLight2D" parent="."]
color = Color(0.6, 0.8, 1, 1)
energy = 1.5
texture_scale = 0.12
blend_mode = 1
```

- [ ] **Step 3: Rebuild Godot class cache**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 4: Commit**

```bash
git add godot/view/projectiles/frost_bolt_muzzle.gd godot/view/projectiles/frost_bolt_muzzle.tscn
git commit -m "feat(view): add frost bolt muzzle flash effect"
```

---

### Task 6: Create Frost Bolt Impact Shatter Scene

**Files:**
- Create: `godot/view/projectiles/frost_bolt_impact.gd`
- Create: `godot/view/projectiles/frost_bolt_impact.tscn`

- [ ] **Step 1: Create the impact script**

Create `godot/view/projectiles/frost_bolt_impact.gd`:

```gdscript
class_name FrostBoltImpact
extends Node2D
## Impact shatter effect for frost bolt. Spawns angular fragments that scatter.

const DURATION: float = 0.5
const FRAGMENT_COUNT: int = 12

@onready var flash: Polygon2D = $Flash
@onready var light: PointLight2D = $Light

var _fragments: Array[Node2D] = []


func _ready() -> void:
	_spawn_fragments()
	_animate()


func _spawn_fragments() -> void:
	for i in FRAGMENT_COUNT:
		var angle = (float(i) / FRAGMENT_COUNT) * TAU + randf() * 0.3
		var speed = 150.0 + randf() * 200.0
		var frag = _create_fragment()
		frag.set_meta("velocity", Vector2.from_angle(angle) * speed)
		frag.set_meta("rot_speed", (randf() - 0.5) * 10.0)
		frag.rotation = randf() * TAU
		add_child(frag)
		_fragments.append(frag)


func _create_fragment() -> Polygon2D:
	var frag = Polygon2D.new()
	var size = 4.0 + randf() * 6.0
	# Angular shard shape
	frag.polygon = PackedVector2Array([
		Vector2(-size, 0),
		Vector2(-size * 0.3, -size * 0.5),
		Vector2(size, -size * 0.2),
		Vector2(size * 0.6, size * 0.4),
		Vector2(-size * 0.3, size * 0.5),
	])
	frag.color = Color(0.75, 0.9, 1.0, 0.9)
	return frag


func _animate() -> void:
	var tween = create_tween()
	
	# Flash burst
	if flash:
		flash.scale = Vector2(0.3, 0.3)
		flash.modulate.a = 1.0
		var flash_tween = create_tween()
		flash_tween.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.1)
		flash_tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.1)
	
	# Light fade
	if light:
		var light_tween = create_tween()
		light_tween.tween_property(light, "energy", 0.0, 0.15)
	
	# Self-destruct after duration
	tween.tween_interval(DURATION)
	tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	for frag in _fragments:
		if not is_instance_valid(frag):
			continue
		var vel: Vector2 = frag.get_meta("velocity", Vector2.ZERO)
		var rot_speed: float = frag.get_meta("rot_speed", 0.0)
		
		frag.position += vel * delta
		frag.rotation += rot_speed * delta
		
		# Slow down and shrink
		vel *= 0.95
		frag.set_meta("velocity", vel)
		frag.scale *= (1.0 - delta * 2.0)
		frag.modulate.a -= delta * 2.0
```

- [ ] **Step 2: Create the impact scene**

Create `godot/view/projectiles/frost_bolt_impact.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://frost_bolt_impact"]

[ext_resource type="Script" path="res://view/projectiles/frost_bolt_impact.gd" id="1_script"]

[node name="FrostBoltImpact" type="Node2D"]
script = ExtResource("1_script")

[node name="Flash" type="Polygon2D" parent="."]
color = Color(1, 1, 1, 0.9)
polygon = PackedVector2Array(-20, 0, 0, -20, 20, 0, 0, 20)

[node name="Light" type="PointLight2D" parent="."]
color = Color(0.6, 0.8, 1, 1)
energy = 2.0
texture_scale = 0.15
blend_mode = 1
```

- [ ] **Step 3: Rebuild Godot class cache**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 4: Commit**

```bash
git add godot/view/projectiles/frost_bolt_impact.gd godot/view/projectiles/frost_bolt_impact.tscn
git commit -m "feat(view): add frost bolt impact shatter effect"
```

---

### Task 7: Create Frost Bolt Trail Shard Scene

**Files:**
- Create: `godot/view/projectiles/frost_bolt_shard.gd`
- Create: `godot/view/projectiles/frost_bolt_shard.tscn`

- [ ] **Step 1: Create the shard script**

Create `godot/view/projectiles/frost_bolt_shard.gd`:

```gdscript
class_name FrostBoltShard
extends Node2D
## Single trailing ice shard that drifts and fades.

const LIFETIME: float = 0.4

var velocity: Vector2 = Vector2.ZERO
var rot_speed: float = 0.0


func _ready() -> void:
	# Randomize initial rotation
	rotation = randf() * TAU
	rot_speed = (randf() - 0.5) * 8.0
	
	# Tween fade and shrink
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, LIFETIME)
	tween.tween_property(self, "scale", Vector2(0.3, 0.3), LIFETIME)
	tween.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	position += velocity * delta
	rotation += rot_speed * delta
	velocity *= 0.95  # Drag
```

- [ ] **Step 2: Create the shard scene**

Create `godot/view/projectiles/frost_bolt_shard.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://frost_bolt_shard"]

[ext_resource type="Script" path="res://view/projectiles/frost_bolt_shard.gd" id="1_script"]

[node name="FrostBoltShard" type="Node2D"]
script = ExtResource("1_script")

[node name="Shape" type="Polygon2D" parent="."]
color = Color(0.75, 0.9, 1, 0.85)
polygon = PackedVector2Array(-6, 0, -2, -3, 6, 0, -2, 3)

[node name="Glow" type="Polygon2D" parent="."]
color = Color(0.5, 0.7, 1, 0.3)
polygon = PackedVector2Array(-8, 0, -3, -4, 8, 0, -3, 4)
```

- [ ] **Step 3: Rebuild Godot class cache**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 4: Commit**

```bash
git add godot/view/projectiles/frost_bolt_shard.gd godot/view/projectiles/frost_bolt_shard.tscn
git commit -m "feat(view): add frost bolt trail shard effect"
```

---

### Task 8: Create ProjectileEffects System

**Files:**
- Create: `godot/view/projectiles/projectile_effects.gd`

- [ ] **Step 1: Create the effects coordinator**

Create `godot/view/projectiles/projectile_effects.gd`:

```gdscript
class_name ProjectileEffects
extends Node2D
## Coordinates projectile visual effects: muzzle flash, trails, and impacts.
## Listens to EventBus signals and spawns appropriate effect scenes.

## Maps projectile type_id -> ProjectileEffectParams
var _effect_params: Dictionary = {}

## Maps projectile_id -> { "last_trail": float, "position": Vector2 }
var _active_projectiles: Dictionary = {}

## Reference to projectile system for position lookups
var _projectile_system: ProjectileSystem


func initialize(projectile_system: ProjectileSystem) -> void:
	_projectile_system = projectile_system


func register_effect_params(type_id: int, params: ProjectileEffectParams) -> void:
	_effect_params[type_id] = params


func _ready() -> void:
	EventBus.projectile_spawned.connect(_on_projectile_spawned)
	EventBus.projectile_despawned.connect(_on_projectile_despawned)


func _on_projectile_spawned(event: Dictionary) -> void:
	var type_id: int = event["type_id"]
	var proj_id: int = event["projectile_id"]
	var pos: Vector2 = event["position"]
	var dir: Vector2 = event["direction"]
	
	var params: ProjectileEffectParams = _effect_params.get(type_id)
	if params == null:
		return
	
	# Spawn muzzle flash at fire position
	if params.muzzle_scene != null:
		var muzzle = params.muzzle_scene.instantiate()
		muzzle.position = pos
		if muzzle.has_method("set") and "direction" in muzzle:
			muzzle.direction = dir
		elif muzzle.get("direction") != null:
			muzzle.direction = dir
		add_child(muzzle)
	
	# Track for trail spawning
	if params.trail_interval > 0.0 and params.trail_scene != null:
		_active_projectiles[proj_id] = {
			"type_id": type_id,
			"last_trail": 0.0,
			"direction": dir,
		}


func _on_projectile_despawned(event: Dictionary) -> void:
	var type_id: int = event["type_id"]
	var proj_id: int = event["projectile_id"]
	var pos: Vector2 = event["position"]
	var reason: int = event["reason"]
	
	# Stop tracking
	_active_projectiles.erase(proj_id)
	
	var params: ProjectileEffectParams = _effect_params.get(type_id)
	if params == null:
		return
	
	# Spawn impact or expire effect based on reason
	var is_collision = reason in [
		ProjectileEntity.DespawnReason.WALL,
		ProjectileEntity.DespawnReason.ENEMY,
		ProjectileEntity.DespawnReason.PLAYER,
		ProjectileEntity.DespawnReason.SELF,
	]
	
	if is_collision and params.impact_scene != null:
		var impact = params.impact_scene.instantiate()
		impact.position = pos
		add_child(impact)
		
		# Enemy flash
		if reason == ProjectileEntity.DespawnReason.ENEMY:
			var target_id: int = event.get("target_entity_id", -1)
			if target_id >= 0:
				_flash_enemy(target_id, params.enemy_flash_color, params.enemy_flash_duration)
	
	elif reason == ProjectileEntity.DespawnReason.LIFETIME and params.expire_scene != null:
		var expire = params.expire_scene.instantiate()
		expire.position = pos
		add_child(expire)


func _flash_enemy(entity_id: int, color: Color, duration: float) -> void:
	EventBus.enemy_hit.emit({
		"entity_id": entity_id,
		"flash_color": color,
		"flash_duration": duration,
	})


func _process(delta: float) -> void:
	if _projectile_system == null:
		return
	
	for proj_id in _active_projectiles.keys():
		var data: Dictionary = _active_projectiles[proj_id]
		var proj: ProjectileEntity = _projectile_system.projectiles.get(proj_id)
		if proj == null:
			_active_projectiles.erase(proj_id)
			continue
		
		var params: ProjectileEffectParams = _effect_params.get(data["type_id"])
		if params == null or params.trail_scene == null:
			continue
		
		data["last_trail"] += delta
		if data["last_trail"] >= params.trail_interval:
			data["last_trail"] = 0.0
			_spawn_trail_shard(proj.position, data["direction"], params.trail_scene)


func _spawn_trail_shard(pos: Vector2, dir: Vector2, scene: PackedScene) -> void:
	var shard = scene.instantiate()
	shard.position = pos
	# Velocity: backward with slight random spread
	var spread_angle = (randf() - 0.5) * 0.8
	var vel_dir = -dir.rotated(spread_angle)
	if shard.get("velocity") != null:
		shard.velocity = vel_dir * (60.0 + randf() * 40.0)
	add_child(shard)


func _exit_tree() -> void:
	if EventBus.projectile_spawned.is_connected(_on_projectile_spawned):
		EventBus.projectile_spawned.disconnect(_on_projectile_spawned)
	if EventBus.projectile_despawned.is_connected(_on_projectile_despawned):
		EventBus.projectile_despawned.disconnect(_on_projectile_despawned)
```

- [ ] **Step 2: Rebuild Godot class cache**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import
```

- [ ] **Step 3: Commit**

```bash
git add godot/view/projectiles/projectile_effects.gd
git commit -m "feat(view): add ProjectileEffects system for muzzle/trail/impact"
```

---

### Task 9: Add Enemy Flash Method to EnemyView

**Files:**
- Modify: `godot/view/world/enemy_view.gd`

- [ ] **Step 1: Add flash_hit method to EnemyView**

Add this method to the end of `godot/view/world/enemy_view.gd` (before the final closing of the implicit class):

```gdscript
## Flash the enemy visual to indicate a hit.
func flash_hit(color: Color, duration: float) -> void:
	if _visual == null:
		return
	var original_color = ENEMY_COLOR
	_visual.color = color
	var tween = create_tween()
	tween.tween_property(_visual, "color", original_color, duration)
```

- [ ] **Step 2: Commit**

```bash
git add godot/view/world/enemy_view.gd
git commit -m "feat(view): add flash_hit method to EnemyView for hit feedback"
```

---

### Task 10: Update WorldView to Handle Enemy Flash Events

**Files:**
- Modify: `godot/view/world/world_view.gd`

- [ ] **Step 1: Read current world_view.gd to find connection point**

Read `godot/view/world/world_view.gd` to understand its structure.

- [ ] **Step 2: Add enemy_hit signal handler**

In `_ready()`, add connection to `EventBus.enemy_hit`:

```gdscript
EventBus.enemy_hit.connect(_on_enemy_hit)
```

Add the handler method:

```gdscript
func _on_enemy_hit(event: Dictionary) -> void:
	var entity_id: int = event.get("entity_id", -1)
	var flash_color: Color = event.get("flash_color", Color.WHITE)
	var flash_duration: float = event.get("flash_duration", 0.1)
	
	if entity_id < 0:
		return
	
	var enemy_view = _enemy_views.get(entity_id)
	if enemy_view != null and enemy_view.has_method("flash_hit"):
		enemy_view.flash_hit(flash_color, flash_duration)
```

In `_exit_tree()`, add disconnection:

```gdscript
if EventBus.enemy_hit.is_connected(_on_enemy_hit):
	EventBus.enemy_hit.disconnect(_on_enemy_hit)
```

- [ ] **Step 3: Commit**

```bash
git add godot/view/world/world_view.gd
git commit -m "feat(view): wire up enemy flash on hit via EventBus"
```

---

### Task 11: Create Frost Bolt Resource Files

**Files:**
- Create: `godot/shared/projectiles/frost_bolt_params.tres`
- Create: `godot/shared/projectiles/frost_bolt_effect_params.tres`

- [ ] **Step 1: Create frost bolt params resource**

Create `godot/shared/projectiles/frost_bolt_params.tres`:

```
[gd_resource type="Resource" script_class="ProjectileParams" load_steps=2 format=3 uid="uid://frost_bolt_params"]

[ext_resource type="Script" path="res://shared/projectiles/projectile_params.gd" id="1_script"]

[resource]
script = ExtResource("1_script")
speed = 500.0
lifetime = 1.5
radius = 6.0
spawn_offset = 40.0
spawn_grace = 0.10
fire_cooldown = 0.25
impact_force = 0.0
movement_type = 0
visual_scene = "res://view/projectiles/frost_bolt_visual.tscn"
```

- [ ] **Step 2: Create frost bolt effect params resource**

Create `godot/shared/projectiles/frost_bolt_effect_params.tres`:

```
[gd_resource type="Resource" script_class="ProjectileEffectParams" load_steps=5 format=3 uid="uid://frost_bolt_effect_params"]

[ext_resource type="Script" path="res://view/projectiles/projectile_effect_params.gd" id="1_script"]
[ext_resource type="PackedScene" path="res://view/projectiles/frost_bolt_muzzle.tscn" id="2_muzzle"]
[ext_resource type="PackedScene" path="res://view/projectiles/frost_bolt_impact.tscn" id="3_impact"]
[ext_resource type="PackedScene" path="res://view/projectiles/frost_bolt_shard.tscn" id="4_shard"]

[resource]
script = ExtResource("1_script")
muzzle_scene = ExtResource("2_muzzle")
impact_scene = ExtResource("3_impact")
expire_scene = null
trail_interval = 0.1
trail_scene = ExtResource("4_shard")
enemy_flash_color = Color(0.8, 0.95, 1, 1)
enemy_flash_duration = 0.1
```

- [ ] **Step 3: Commit**

```bash
git add godot/shared/projectiles/frost_bolt_params.tres godot/shared/projectiles/frost_bolt_effect_params.tres
git commit -m "feat: add frost bolt projectile and effect params resources"
```

---

### Task 12: Register Frost Bolt Type and Wire Up Effects

**Files:**
- Modify: `godot/shared/projectiles/projectile_types.gd`

- [ ] **Step 1: Add frost bolt to the registry**

In `godot/shared/projectiles/projectile_types.gd`, update the enum and registry:

Add to `enum Id`:
```gdscript
enum Id {
	TEST = 0,
	FROST_BOLT = 1,
}
```

Update `_registry`:
```gdscript
static var _registry: Dictionary = {
	"test": preload("res://shared/projectiles/test_projectile.tres"),
	"frost_bolt": preload("res://shared/projectiles/frost_bolt_params.tres"),
}
```

Update `_name_to_id`:
```gdscript
static var _name_to_id: Dictionary = {
	"test": Id.TEST,
	"frost_bolt": Id.FROST_BOLT,
}
```

Update `_id_to_name`:
```gdscript
static var _id_to_name: Dictionary = {
	Id.TEST: "test",
	Id.FROST_BOLT: "frost_bolt",
}
```

- [ ] **Step 2: Commit**

```bash
git add godot/shared/projectiles/projectile_types.gd
git commit -m "feat: register frost_bolt projectile type"
```

---

### Task 13: Integrate ProjectileEffects with Client

**Files:**
- Modify: `godot/client/client_main.gd` (or wherever ProjectileView is instantiated)

- [ ] **Step 1: Find client initialization code**

Read the client main file to understand where ProjectileView is created.

```bash
grep -r "ProjectileView" godot/client/ godot/view/
```

- [ ] **Step 2: Add ProjectileEffects instantiation**

Where ProjectileView is created, also create and add ProjectileEffects:

```gdscript
# After creating projectile_view
var projectile_effects = ProjectileEffects.new()
projectile_effects.initialize(_projectile_system)

# Register frost bolt effects
var frost_effect_params = preload("res://shared/projectiles/frost_bolt_effect_params.tres")
projectile_effects.register_effect_params(ProjectileType.Id.FROST_BOLT, frost_effect_params)

add_child(projectile_effects)
```

- [ ] **Step 3: Commit**

```bash
git add godot/client/client_main.gd
git commit -m "feat: wire up ProjectileEffects in client initialization"
```

---

### Task 14: Update Default Projectile Type for Testing

**Files:**
- Find and modify where projectile type is set when firing

- [ ] **Step 1: Find where projectiles are fired**

Search for where projectile spawning happens to change the default type:

```bash
grep -r "type_id" godot/simulation/systems/projectile_system.gd
```

- [ ] **Step 2: Update test/debug firing to use frost bolt**

If there's a hardcoded `TEST` type for firing, change it to `FROST_BOLT` for testing:

```gdscript
# Change from:
var type_id = ProjectileType.Id.TEST
# To:
var type_id = ProjectileType.Id.FROST_BOLT
```

- [ ] **Step 3: Commit**

```bash
git add <modified files>
git commit -m "feat: use frost_bolt as default projectile type"
```

---

### Task 15: Manual Visual Verification

- [ ] **Step 1: Launch the game**

```bash
cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --path . res://client/client.tscn
```

- [ ] **Step 2: Verify all effects**

Check each visual component:
- [ ] Frost bolt has crystalline angular shape
- [ ] Chromatic aberration shader visible on bolt edges
- [ ] PointLight2D illuminates surroundings as bolt flies
- [ ] Light pulses in sync with bolt glow
- [ ] Muzzle flash appears at player position on fire
- [ ] Trail shards spawn every ~100ms behind bolt
- [ ] Impact shatter explodes into angular fragments on wall hit
- [ ] Impact shatter appears on enemy hit
- [ ] Enemy flashes white/cyan briefly on hit
- [ ] Lifetime expiry fades quietly (no shatter)

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "feat: frost bolt visual effects complete

- Crystalline bolt with chromatic aberration shader
- Dynamic PointLight2D with pulsing energy
- Muzzle flash with particle spray
- Trailing ice shards at 100ms intervals
- Impact shatter with angular fragments
- Enemy flash feedback on hit
- Extensible ProjectileEffects system for future projectiles"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Chromatic aberration shader | `view/shaders/chromatic_aberration.gdshader` |
| 2 | Pulse glow shader | `view/shaders/pulse_glow.gdshader` |
| 3 | ProjectileEffectParams resource class | `view/projectiles/projectile_effect_params.gd` |
| 4 | Frost bolt visual scene | `frost_bolt_visual.gd`, `.tscn` |
| 5 | Muzzle flash effect | `frost_bolt_muzzle.gd`, `.tscn` |
| 6 | Impact shatter effect | `frost_bolt_impact.gd`, `.tscn` |
| 7 | Trail shard effect | `frost_bolt_shard.gd`, `.tscn` |
| 8 | ProjectileEffects system | `projectile_effects.gd` |
| 9 | Enemy flash method | `enemy_view.gd` |
| 10 | WorldView enemy flash wiring | `world_view.gd` |
| 11 | Frost bolt resource files | `.tres` files |
| 12 | Register frost bolt type | `projectile_types.gd` |
| 13 | Client integration | `client_main.gd` |
| 14 | Default type for testing | varies |
| 15 | Manual verification | N/A |
