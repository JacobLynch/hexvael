# Shooting Juice Design Spec

> Frost bolt firing feel improvements: camera kick, sprite recoil, launch streak, brighter muzzle light.

## Overview

Make shooting feel more powerful by adding juice effects when the player fires. These effects are parameterized per projectile type — frost bolt gets specific values, future projectiles can have different or no effects.

## Effects Summary

| Effect | Local Player | Remote Players | Configurable Via |
|--------|--------------|----------------|------------------|
| Camera kick | Yes | No | `camera_kick_amplitude` |
| Sprite recoil | Yes | Yes | `sprite_recoil_distance` |
| Launch streak | Yes | Yes | `launch_streak_scene` |
| Muzzle light | Yes | Yes | Values in muzzle scene |

## Camera Kick

**Behavior:**
- On local player fire, camera instantly offsets opposite to shot direction
- Returns to normal via exponential decay (~50ms snap-back feel)
- Remote players' shots don't affect your camera

**Parameters (frost bolt):**
- Amplitude: 3.0 pixels

**Implementation:**

Add to CameraRig:
```gdscript
var _kick_offset: Vector2 = Vector2.ZERO
const KICK_DECAY: float = 20.0

func add_kick(direction: Vector2, amplitude: float) -> void:
    _kick_offset = -direction.normalized() * amplitude
```

In `_process()`, decay kick and add to camera target:
```gdscript
_kick_offset *= exp(-KICK_DECAY * delta)
var target = _target_position + lookahead + _shake_offset + _kick_offset
```

**Trigger:** Called from `ProjectileEffects.spawn_local_muzzle_flash()` using effect params.

## Sprite Recoil

**Behavior:**
- On any player fire, their sprite nudges backward 1-2px
- Snaps back quickly via exponential decay (~50ms)
- Purely visual — simulation position unchanged
- Easy to disable via `RECOIL_ENABLED` constant

**Parameters (frost bolt):**
- Distance: 2.0 pixels

**Implementation:**

Add to PlayerView:
```gdscript
const RECOIL_ENABLED: bool = true
const RECOIL_DECAY: float = 20.0

var _recoil_offset: Vector2 = Vector2.ZERO

func apply_recoil(direction: Vector2, distance: float) -> void:
    if not RECOIL_ENABLED:
        return
    _recoil_offset = -direction.normalized() * distance
```

In `_process()`:
```gdscript
_recoil_offset *= exp(-RECOIL_DECAY * delta)
position = _target_position + _recoil_offset
```

**Trigger:** WorldView listens to `projectile_spawned`, looks up player view by `owner_player_id`, calls `apply_recoil()` with params from effect config.

## Launch Streak

**Behavior:**
- On projectile spawn, a Line2D appears from spawn point to bolt position
- Line stretches as bolt moves away for ~80ms
- Then releases (stops tracking) and fades out over ~100ms
- Self-destructs after fade
- Works for all players (local + remote)

**Visual style:**
- Width: 2-3px
- Color: frost bolt cyan/white (`Color(0.7, 0.9, 1.0, 0.9)`)
- Additive blend for glow feel

**Implementation:**

New scene `frost_bolt_streak.tscn` with script:
```gdscript
class_name FrostBoltStreak
extends Node2D

const TRACK_DURATION: float = 0.08
const FADE_DURATION: float = 0.1

var _line: Line2D
var _start_point: Vector2
var _track_timer: float = 0.0
var _fading: bool = false
var _projectile_id: int = -1
var _projectile_system: ProjectileSystem

func initialize(start: Vector2, proj_id: int, proj_system: ProjectileSystem) -> void:
    _start_point = start
    _projectile_id = proj_id
    _projectile_system = proj_system
    global_position = start
    _create_line()

func _create_line() -> void:
    _line = Line2D.new()
    _line.width = 2.5
    _line.default_color = Color(0.7, 0.9, 1.0, 0.9)
    _line.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
    add_child(_line)

func _process(delta: float) -> void:
    if _fading:
        return
        
    if _track_timer < TRACK_DURATION:
        var proj = _projectile_system.projectiles.get(_projectile_id)
        if proj:
            _line.points[1] = proj.position - global_position
        _track_timer += delta
    else:
        _start_fade()

func _start_fade() -> void:
    _fading = true
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
    tween.tween_callback(queue_free)
```

**Trigger:** ProjectileEffects spawns streak on `projectile_spawned` if `launch_streak_scene` is set.

## Muzzle Light Bump

**Behavior:**
- Brighter, slightly larger light burst on fire
- Already part of muzzle scene, works for all players

**Changes to frost_bolt_muzzle.tscn Light node:**
```
energy = 2.5      # was 1.5
texture_scale = 0.18   # was 0.12
```

No code changes needed.

## ProjectileEffectParams Extension

Add three new exports:
```gdscript
## Camera kick amplitude on fire. 0 = no kick. Local player only.
@export var camera_kick_amplitude: float = 0.0

## Sprite recoil distance in pixels. 0 = no recoil.
@export var sprite_recoil_distance: float = 0.0

## Scene for launch streak effect. Null = no streak.
@export var launch_streak_scene: PackedScene = null
```

## frost_bolt_effect_params.tres Values

```
camera_kick_amplitude = 3.0
sprite_recoil_distance = 2.0
launch_streak_scene = ExtResource("frost_bolt_streak.tscn")
```

## File Changes

| File | Change |
|------|--------|
| `view/world/camera_rig.gd` | Add `add_kick()`, `_kick_offset`, decay logic |
| `view/world/player_view.gd` | Add `apply_recoil()`, `_recoil_offset`, `RECOIL_ENABLED` toggle |
| `view/world/world_view.gd` | Wire recoil to `projectile_spawned` event |
| `view/projectiles/projectile_effect_params.gd` | Add 3 new exports |
| `view/projectiles/projectile_effects.gd` | Trigger camera kick (local only), spawn streak |
| `view/effects/frost_bolt_streak.gd` | New script |
| `view/effects/frost_bolt_streak.tscn` | New scene |
| `view/projectiles/frost_bolt_muzzle.tscn` | Bump light energy + scale |
| `shared/projectiles/frost_bolt_effect_params.tres` | Set new param values |

## Not Building

- Generic streak system (frost bolt specific for now)
- Sound effects (separate pass)
- Screen flash / post-processing effects
- Chromatic aberration pulse

## Success Criteria

- Firing frost bolt feels noticeably punchier
- Camera kicks back briefly on local fire
- Player sprites visibly recoil for all players
- Launch streak adds dramatic acceleration feel
- Muzzle flash illuminates surroundings better
- Effects are parameterized — other projectiles can have different values
- Sprite recoil easily disabled via constant toggle
