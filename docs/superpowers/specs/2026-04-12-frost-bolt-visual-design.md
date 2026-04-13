# Frost Bolt Visual Design Spec

> First projectile visual implementation. Establishes patterns for future projectile types.

## Overview

Transform the placeholder projectile into a juicy frost bolt with crystalline visuals, shader effects, dynamic lighting, and satisfying impact feedback. Pure visual work — no damage/health systems.

## Visual Identity

**Style:** Arcane Frost — crystalline sharpness with otherworldly magical instability.

**Color Palette:** Classic ice
- Core: cyan (`#aaeeff`) to white (`#ffffff`) gradient
- Glow: soft blue (`rgb(140, 160, 255)`)
- Accents: pale blue-white for shards and particles

## The Bolt

### Shape
- Angular crystalline polygon (6-point elongated, sharp edges)
- Bright white center line for visual punch
- Approximately 40x14 pixels at default scale

### Shaders

**Chromatic Aberration:**
- Slight red/blue color channel offset at edges
- Creates arcane/unstable feel
- Offset ~2-3 pixels, subtle not garish

**Pulse Glow:**
- Core intensity breathes at ~12Hz
- Modulates between 80-100% brightness
- Uses additive blending

### Dynamic Light
- `PointLight2D` attached to bolt
- Cyan tint matching glow color
- Radius: ~100px
- Energy pulses in sync with glow shader
- Illuminates walls, enemies, environment as bolt passes

## Trailing Effects

### Ice Shards
- Spawn every ~100ms while bolt flies
- Angular polygon shape (not circles)
- Drift backward with slight spread
- Rotate as they move
- Fade over ~400ms
- 1-2 shards per spawn, sparse not dense

### Magic Motes
- Small glowing particles orbiting near bolt
- Continuous low-rate emitter (~3-4 visible at once)
- Orbit radius ~15-20px
- Fade quickly, don't trail far behind
- Additive blending for glow stacking

## Muzzle Flash (On Fire)

**Timing:** ~150ms total duration, no firing delay

**Components:**
- Central white flash: expands from player position, fades
- Ice particles: 6-8 small angular shards
- Spray direction: forward cone (~60° spread)
- Light pulse: brief PointLight2D flash at player (~100ms)

**Feel:** Instant and responsive. The flash is feedback, not windup.

## Impact Shatter (On Hit)

### All Impacts (Wall + Enemy)
- Central white flash burst (~100ms)
- 10-12 angular ice fragments explode outward
- Fragments scatter 360° from impact point
- Fragments rotate, shrink, and fade over ~500ms
- Brief light flash at impact point (~150ms)

### Enemy Hit Bonus
- Same shatter as walls (visual consistency)
- Enemy sprite flashes white/cyan for ~100ms
- No screen shake (save headroom for bigger spells)
- No freeze frame (save for crits/special hits)

### Lifetime Expiry (No Collision)
- Bolt fades out quickly over ~100ms
- 2-3 small particles drift off
- No shatter — it fizzled, not impacted

## Technical Implementation

### File Structure

```
godot/view/projectiles/
  frost_bolt_visual.tscn      # Main visual scene
  frost_bolt_visual.gd        # Optional script for animation control

godot/view/shaders/
  chromatic_aberration.gdshader   # Shared, reusable
  pulse_glow.gdshader             # Shared, reusable
  frost_bolt.gdshader             # Composes above, bolt-specific params

godot/view/effects/
  projectile_effects.gd       # Spawns muzzle/impact/trail effects

godot/shared/projectiles/
  frost_bolt_params.tres      # ProjectileParams resource
```

### Frost Bolt Visual Scene (`frost_bolt_visual.tscn`)

```
Node2D (root)
├── Polygon2D (bolt shape, shader material)
├── PointLight2D (dynamic lighting)
└── CPUParticles2D (magic motes, continuous)
```

### ProjectileEffectParams Resource (New)

```gdscript
class_name ProjectileEffectParams
extends Resource

@export var muzzle_scene: PackedScene  # Spawned at player on fire
@export var impact_scene: PackedScene  # Spawned at impact point
@export var trail_interval: float = 0.0  # Seconds between trail spawns (0 = disabled)
@export var trail_scene: PackedScene  # What to spawn for trail shards
@export var enemy_flash_color: Color = Color(0.8, 0.95, 1.0, 1.0)
@export var enemy_flash_duration: float = 0.1
```

### ProjectileEffects System (New)

Responsibilities:
- Listen to `EventBus.projectile_spawned` → spawn muzzle effect at player
- Listen to `EventBus.projectile_despawned` → spawn impact effect if collision
- Track active projectiles, spawn trail effects at intervals
- Delegate enemy flash to existing enemy view system

This keeps `ProjectileView` thin — it only manages the bolt visuals, not all the surrounding effects.

### Shader Approach

**chromatic_aberration.gdshader:**
```glsl
shader_type canvas_item;

uniform float offset : hint_range(0.0, 10.0) = 2.0;
uniform float strength : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    vec2 dir = normalize(UV - vec2(0.5));
    float edge = length(UV - vec2(0.5)) * 2.0;
    
    vec4 col = texture(TEXTURE, UV);
    vec4 r = texture(TEXTURE, UV - dir * offset * TEXTURE_PIXEL_SIZE * edge);
    vec4 b = texture(TEXTURE, UV + dir * offset * TEXTURE_PIXEL_SIZE * edge);
    
    COLOR = vec4(
        mix(col.r, r.r, strength),
        col.g,
        mix(col.b, b.b, strength),
        col.a
    );
}
```

**pulse_glow.gdshader:**
```glsl
shader_type canvas_item;

uniform float speed : hint_range(1.0, 30.0) = 12.0;
uniform float min_intensity : hint_range(0.0, 1.0) = 0.8;
uniform vec4 glow_color : source_color = vec4(0.55, 0.63, 1.0, 1.0);

void fragment() {
    float pulse = min_intensity + (1.0 - min_intensity) * (0.5 + 0.5 * sin(TIME * speed));
    vec4 col = texture(TEXTURE, UV);
    COLOR = col * glow_color * pulse;
}
```

### Integration Points

**ProjectileParams extension:**
- Add `effect_params: ProjectileEffectParams` reference
- Or keep effect config in the visual scene (simpler for now)

**ProjectileView changes:**
- Load visual scene from `ProjectileParams.visual_scene` (already supported)
- Delegate effect spawning to `ProjectileEffects` singleton or child node

**EventBus signals (existing):**
- `projectile_spawned` — includes position, direction, owner
- `projectile_despawned` — includes position, reason, target_entity_id

**Enemy flash:**
- Add signal or direct call to enemy view system
- `EnemyView` handles its own flash shader/modulate

## Extensibility

This implementation establishes patterns for future projectiles:

### Adding a New Projectile Type

1. Create visual scene in `godot/view/projectiles/` (copy frost bolt as template)
2. Adjust colors, shapes, particles, light settings
3. Create or reuse shaders from `godot/view/shaders/`
4. Create `ProjectileParams` resource pointing to the scene
5. Create `ProjectileEffectParams` for muzzle/impact/trail
6. Register in `ProjectileType` enum

No code changes required for basic variants.

### Shader Reuse

Shared shaders accept uniforms for customization:
- `chromatic_aberration`: offset, strength
- `pulse_glow`: speed, min_intensity, glow_color

Fire bolt reuses `pulse_glow` with orange color. Void bolt uses inverted parameters.

### Future Enhancements (Not This Spec)

- Surface decals (frost patches on ground)
- Status effect visuals (frozen enemy shader)
- Projectile charge levels (visual intensity scaling)
- Sound integration

## Not Building

- Screen shake on hit (reserved for bigger spells)
- Freeze frames (reserved for crits)
- Damage numbers (separate system)
- Health/damage logic (simulation layer, not view)
- Persistent frost decals (future surface system)
- Sound effects (separate pass)

## Success Criteria

- Frost bolt looks and feels distinct from placeholder
- Firing feels instant and responsive
- Impacts feel satisfying without overwhelming
- Dynamic light adds atmosphere
- Pattern is clear for adding fire bolt, void bolt, etc.
- Works correctly for both local and remote projectiles
- No simulation code touched — pure view layer
