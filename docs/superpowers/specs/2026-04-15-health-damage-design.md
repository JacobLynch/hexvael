# Health and Damage System Design

**Date:** 2026-04-15  
**Status:** Approved

## Overview

A health and damage system for Hexvael that introduces health pools for players and enemies, damage application via projectiles, player death with ghost state, and view-layer feedback (floating damage numbers, health bars, hit flash).

## Architecture

**HealthComponent + DamageSystem pattern:**
- `HealthComponent` — pure data class for health math, no side effects
- `DamageSystem` — orchestration layer that applies damage, emits events, handles death

This separation keeps health logic reusable and testable while centralizing damage flow for future TCE integration.

---

## Components

### HealthComponent

Pure data class used by both PlayerEntity and EnemyEntity.

**Location:** `/simulation/components/health_component.gd`

```gdscript
class_name HealthComponent
extends RefCounted

var current: int
var max_health: int

func _init(max_hp: int) -> void:
    max_health = max_hp
    current = max_hp

func take_damage(amount: int) -> Dictionary:
    var actual = mini(amount, current)
    current -= actual
    return { "damage_dealt": actual, "killed": current <= 0 }

func heal(amount: int) -> int:
    var actual = mini(amount, max_health - current)
    current += actual
    return actual

func is_dead() -> bool:
    return current <= 0

func to_dict() -> Dictionary:
    return { "current": current, "max": max_health }

func from_dict(data: Dictionary) -> void:
    current = data.get("current", max_health)
    max_health = data.get("max", max_health)
```

**Key points:**
- No EventBus, no entity references — pure math
- Integer health (avoids float precision drift)
- Returns info from `take_damage` so caller knows what happened
- Snapshot-friendly with `to_dict`/`from_dict`

---

### DamageSystem

Orchestration layer for all damage application.

**Location:** `/simulation/systems/damage_system.gd`

```gdscript
class_name DamageSystem
extends RefCounted

func apply_damage(target, amount: int, source_info: Dictionary) -> Dictionary:
    var result = target.health.take_damage(amount)
    
    var event_data = {
        "target_entity_id": _get_entity_id(target),
        "source_entity_id": source_info.get("source_entity_id", -1),
        "damage": result.damage_dealt,
        "position": target.position,
        "element": source_info.get("element", "physical"),
        "projectile_id": source_info.get("projectile_id", -1),
        "chain_depth": source_info.get("chain_depth", 0),
    }
    
    if _is_player(target):
        EventBus.player_hit.emit(event_data)
    else:
        EventBus.enemy_hit.emit(event_data)
    
    if result.killed:
        _handle_death(target, event_data)
    
    return result

func _handle_death(target, event_data: Dictionary) -> void:
    if _is_player(target):
        target.enter_ghost_state()
        EventBus.player_died.emit(event_data)
    else:
        target.kill()
        EventBus.enemy_died.emit(event_data)

func _is_player(target) -> bool:
    return target is PlayerEntity

func _get_entity_id(target) -> int:
    if target is PlayerEntity:
        return target.player_id
    return target.entity_id
```

**Key points:**
- Single entry point for all damage
- Emits hit events with full context for view layer and future TCE
- Handles death transitions per entity type
- Returns result so callers can react

---

## Player Ghost State

When a player dies, they enter a ghost state for 5 seconds before respawning.

**New PlayerMovementState:**
```gdscript
const GHOST = 2  # Add to player_movement_state.gd
```

**PlayerEntity additions:**

```gdscript
var health: HealthComponent
var ghost_timer: float = 0.0
const GHOST_DURATION: float = 5.0
const PLAYER_MAX_HEALTH: int = 100

func initialize(id: int, spawn_position: Vector2) -> void:
    player_id = id
    position = spawn_position
    health = HealthComponent.new(PLAYER_MAX_HEALTH)

func enter_ghost_state() -> void:
    state = PlayerMovementState.GHOST
    ghost_timer = GHOST_DURATION
    velocity = Vector2.ZERO
    dodge_time_remaining = 0.0
    $CollisionShape2D.set_deferred("disabled", true)
    EventBus.player_ghost_started.emit({
        "entity_id": player_id,
        "position": position,
        "duration": GHOST_DURATION,
    })

func _advance_ghost(dt: float) -> void:
    ghost_timer -= dt
    if move_input.length_squared() > 0.001:
        velocity = move_input.normalized() * params.top_speed
    else:
        velocity *= exp(-params.friction * dt)
    position += velocity * dt
    
    if ghost_timer <= 0.0:
        _respawn()

func _respawn() -> void:
    state = PlayerMovementState.WALKING
    position = Vector2.ZERO  # Center of arena
    health.current = health.max_health
    velocity = Vector2.ZERO
    ghost_timer = 0.0
    dodge_cooldown_remaining = 0.0
    _ensure_collision_enabled()
    EventBus.player_respawned.emit({
        "entity_id": player_id,
        "position": position,
    })

func _ensure_collision_enabled() -> void:
    $CollisionShape2D.set_deferred("disabled", false)
```

**Action restrictions during ghost:**
- `apply_input()` ignores action flags (dodge, fire) while in GHOST state
- `ProjectileSystem.can_fire()` returns false for ghost players
- Ghost can only move (no-clip)

---

## Entity Integration

### PlayerEntity

```gdscript
var health: HealthComponent
const PLAYER_MAX_HEALTH: int = 100

func initialize(id: int, spawn_position: Vector2) -> void:
    player_id = id
    position = spawn_position
    health = HealthComponent.new(PLAYER_MAX_HEALTH)

func to_snapshot_data() -> Dictionary:
    return {
        # ... existing fields ...
        "health": health.current,
        "max_health": health.max_health,
        "ghost_timer": ghost_timer,
    }
```

### EnemyEntity

```gdscript
var health: HealthComponent

func initialize(id: int, spawn_position: Vector2, params: EnemyParams) -> void:
    # ... existing ...
    health = HealthComponent.new(params.max_health)

func to_snapshot_data() -> Dictionary:
    return {
        # ... existing ...
        "health": health.current,
        "max_health": health.max_health,
    }
```

### EnemyParams

```gdscript
@export var max_health: int = 50
```

### ProjectileParams

```gdscript
@export var damage: int = 25
@export var element: String = "physical"
```

---

## ProjectileSystem Integration

DamageSystem is injected into ProjectileSystem. When projectiles hit entities, damage is applied.

```gdscript
var _damage_system: DamageSystem = null

func initialize(damage_system: DamageSystem) -> void:
    _damage_system = damage_system
```

In `advance()`, when a projectile despawns due to hitting an entity:

```gdscript
if _damage_system != null:
    var source_info = {
        "source_entity_id": p.owner_player_id,
        "projectile_id": p.projectile_id,
        "element": p.params.element,
    }
    
    if reason == ProjectileEntity.DespawnReason.ENEMY:
        var enemy = enemy_lookup.get(p.last_hit_entity_id)
        if enemy != null:
            _damage_system.apply_damage(enemy, p.params.damage, source_info)
            # Knockback still applied after damage
    
    elif reason == ProjectileEntity.DespawnReason.PLAYER:
        var player = player_lookup.get(p.last_hit_entity_id)
        if player != null:
            _damage_system.apply_damage(player, p.params.damage, source_info)
    
    elif reason == ProjectileEntity.DespawnReason.SELF:
        var player = player_lookup.get(p.owner_player_id)
        if player != null:
            _damage_system.apply_damage(player, p.params.damage, source_info)
```

**Server-authoritative:** Client passes null for damage_system (no local damage application).

---

## EventBus Signals

**New signals:**
```gdscript
signal player_ghost_started(event: Dictionary)  # entity_id, position, duration
signal player_respawned(event: Dictionary)      # entity_id, position
```

**Existing signals now emitted:**
```gdscript
signal enemy_hit(event: Dictionary)    # target_entity_id, source_entity_id, damage, position, element, projectile_id, chain_depth
signal enemy_died(event: Dictionary)   # same fields
signal player_hit(event: Dictionary)   # same fields
signal player_died(event: Dictionary)  # same fields
```

---

## View Layer

### DamageNumberSpawner

**Location:** `/view/effects/damage_number_spawner.gd`

Listens to `enemy_hit` and `player_hit`. Spawns floating damage numbers that rise and fade over 0.8 seconds.

### HealthBarManager

**Location:** `/view/ui/health_bar_manager.gd`

Creates and updates health bars for entities:
- Enemy bars: small bar above sprite, hidden when at full health
- Player bars: HUD element for local player

### HitFlashEffect

Integrated into enemy view. On `enemy_hit`, flash white for ~3 frames (0.05s) using shader parameter.

### GhostOverlay

**Location:** `/view/effects/ghost_overlay.gd`

Listens to `player_ghost_started` and `player_respawned`:
- Local player: desaturate/blue tint screen overlay, countdown timer in center
- All ghost players: translucent sprite

---

## Default Values

| Entity | Max Health |
|--------|------------|
| Player | 100 |
| Basic Enemy | 50 |

| Projectile | Damage |
|------------|--------|
| Frost Bolt | 25 |

| Timing | Duration |
|--------|----------|
| Ghost state | 5.0 seconds |
| Hit flash | 0.05 seconds |
| Damage number float | 0.8 seconds |

---

## Files

**New files:**
- `/simulation/components/health_component.gd`
- `/simulation/systems/damage_system.gd`
- `/view/effects/damage_number_spawner.gd`
- `/view/effects/damage_number.tscn`
- `/view/ui/health_bar_manager.gd`
- `/view/ui/enemy_health_bar.tscn`
- `/view/effects/ghost_overlay.gd`

**Modified files:**
- `/simulation/entities/player_entity.gd`
- `/simulation/entities/player_movement_state.gd`
- `/simulation/entities/enemy_entity.gd`
- `/simulation/systems/projectile_system.gd`
- `/simulation/event_bus.gd`
- `/shared/enemies/enemy_params.gd`
- `/shared/projectiles/projectile_params.gd`
- `/shared/projectiles/frost_bolt_params.tres`

---

## Design Decisions

1. **HealthComponent + DamageSystem** — separates health math (pure, testable) from damage orchestration (events, death handling, future TCE hooks)

2. **Ghost state instead of instant respawn** — 5-second observational penalty, player can move but not act, respawns at center with full health

3. **Full friendly fire** — projectiles deal full damage to teammates, Magicka-style chaos

4. **No spawn protection** — center spawn location assumed safe

5. **Integer health** — avoids float precision issues across network

6. **Damage on ProjectileParams** — simple and direct for v1, element field prepares for TCE

7. **Server-authoritative damage** — client ProjectileSystem doesn't apply damage, only server does
