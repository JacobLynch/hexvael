# Frost Bolt Juice V2 Design Spec

> Additional juice for frost bolt: knockback + visual polish.

## Overview

Build on the existing frost bolt visual implementation with four additions:
1. **Enemy knockback** — light push + stagger on hit (simulation)
2. **Frost cling particles** — ice crystals stick to hit enemies (view)
3. **Impact crack lines** — radial white lines at impact point (view)
4. **Muzzle vapor** — cold mist puff on fire (view)

## Enemy Knockback (Simulation)

### Design

Enemies receive a velocity impulse in the projectile's travel direction, then slide smoothly over a stagger window with friction decay. Mass-based resistance means heavier enemies get pushed less or not at all.

### Properties

**EnemyParams (new):**
```gdscript
@export var mass: float = 1.0  # 1.0 = light, 3.0+ = heavy/immune
```

**EnemyEntity (new state):**
```gdscript
var knockback_velocity: Vector2 = Vector2.ZERO
var stagger_timer: float = 0.0
```

**ProjectileParams (new, or in frost_bolt_params.tres):**
```gdscript
@export var knockback_force: float = 200.0
@export var knockback_stagger: float = 0.1
```

### Knockback Application

```gdscript
# TODO(TCE): Migrate knockback to effect system. This should become:
#   - "knockback" effect type in TCE
#   - Trigger data in projectile/gear params instead of hardcoded values
#   - Effect executor calls apply_knockback() with params from trigger

func apply_knockback(enemy: EnemyEntity, direction: Vector2, force: float, stagger: float) -> void:
    if enemy._params.mass >= 3.0:
        return  # Heavy enemies immune
    var actual_force = force / enemy._params.mass
    enemy.knockback_velocity = direction.normalized() * actual_force
    enemy.stagger_timer = stagger / enemy._params.mass
```

### Enemy Advance Modification

```gdscript
const KNOCKBACK_FRICTION: float = 8.0  # Tune for feel

func advance(dt: float, ...) -> void:
    if stagger_timer > 0.0:
        # Apply knockback velocity (smooth movement over time)
        position += knockback_velocity * dt
        
        # Friction decay — velocity dies down over the stagger window
        knockback_velocity *= exp(-KNOCKBACK_FRICTION * dt)
        
        stagger_timer -= dt
        if stagger_timer <= 0.0:
            knockback_velocity = Vector2.ZERO
        return  # Skip normal AI while staggered
    
    # Normal AI movement...
```

### Event Data

`enemy_hit` event includes:
```gdscript
{
    ...
    "projectile_direction": direction,  # Bolt's travel direction (not radial)
    "knockback_force": 200.0,
    "knockback_stagger": 0.1,
}
```

### Feel Targets

- **Displacement:** ~15-25px for light enemies (mass 1.0)
- **Duration:** ~100ms stagger
- **Heavy enemies:** mass >= 3.0 immune, mass 2.0 gets half effect

## Frost Cling Particles (View)

Ice crystals that stick to enemies on hit, providing visual confirmation beyond the white flash.

### Behavior

- 3-4 small angular ice crystal polygons
- Attach to enemy position (follow as they move)
- Slight outward drift + rotation
- Fade over ~300ms
- Self-destruct after fade

### Implementation

New scene: `godot/view/effects/frost_cling.tscn`
- Root Node2D with script
- Spawns polygon children on ready
- Stores reference to target enemy view node
- Updates position in `_process()` to follow enemy
- Tween handles fade and cleanup

Triggered by: `ProjectileEffects` listening to `enemy_hit`, spawns frost cling at enemy position.

## Impact Crack Lines (View)

Thin white lines radiating from impact point, like ice cracking on a surface.

### Behavior

- 4-6 `Line2D` nodes radiating from center
- Random angles, lengths 20-40px
- Width: 1-2px, white color
- Fade alpha over ~150ms
- Part of impact effect, not separate scene

### Implementation

Added to `FrostBoltImpact._ready()`:
- Spawn Line2D nodes alongside existing fragment burst
- Random angle distribution (avoid clustering)
- Tween alpha to 0 over 150ms

## Muzzle Vapor (View)

Cold mist puff at player position on fire, sells the "frost" element.

### Behavior

- Soft white/pale blue circular particles (contrast with angular shards)
- 4-6 particles, drift outward slowly
- Slight random spread
- Lifetime ~200ms
- Softer blend than the sharp flash (normal or soft additive)

### Implementation

Added to `FrostBoltMuzzle.tscn`:
- New `CPUParticles2D` child node
- Circular texture or small soft circle
- One-shot emission on ready
- Configured via particle system properties (no code needed)

## File Changes

### Simulation

| File | Change |
|------|--------|
| `simulation/entities/enemy_params.gd` | Add `mass: float = 1.0` export |
| `simulation/entities/enemy_entity.gd` | Add knockback state, modify `advance()` for stagger |
| `simulation/systems/projectile_system.gd` | Include knockback data in `enemy_hit` event |
| `shared/projectiles/frost_bolt_params.tres` | Add `knockback_force`, `knockback_stagger` |

### View

| File | Change |
|------|--------|
| `view/projectiles/frost_bolt_impact.gd` | Add crack line spawning |
| `view/projectiles/frost_bolt_muzzle.tscn` | Add vapor CPUParticles2D |
| `view/effects/frost_cling.tscn` | New scene |
| `view/effects/frost_cling.gd` | New script |
| `view/projectiles/projectile_effects.gd` | Spawn frost cling on enemy hit |

## Not Building

- Screen shake (reserved for bigger spells)
- Freeze frames (reserved for crits)
- Sound effects (separate pass)
- Enemy frozen shader (future status effect system)
- Surface frost decals (future surface system)
- TCE integration (marked with TODO for future migration)

## Success Criteria

- Frost bolt hits feel punchier with knockback feedback
- Light enemies visibly bump backward on hit
- Heavy enemies shrug off the push (mass >= 3.0)
- Frost cling particles confirm hits landed
- Crack lines add impact weight
- Muzzle vapor sells the cold element
- All visual effects work for both local and remote projectiles
- Knockback code has clear TODO marker for TCE migration
