# Hold-to-Fire Design

## Summary

Add automatic firing when the fire button is held. Same cooldown between shots as click-to-fire (0.20s). Fires immediately on press, continues while held.

## Current Behavior

- `KeyboardMouseInputProvider` detects `is_action_just_pressed("fire")` (edge-triggered)
- Fire latch consumed in `client_main._process()`, spawns predicted projectile
- `ProjectileSystem` enforces cooldown per player via `can_fire()` / `start_cooldown()`
- Cooldown: 0.20s (from `ProjectileParams.fire_cooldown`)

## Design

### InputProvider Changes

**Base class** (`input_provider.gd`):
```gdscript
func is_fire_held() -> bool:
    return false
```

**KeyboardMouseInputProvider** (`keyboard_mouse_input_provider.gd`):
```gdscript
func is_fire_held() -> bool:
    return Input.is_action_pressed("fire")
```

### client_main Changes

In `_process()`, after the existing fire press latch handling:

```gdscript
# Hold-to-fire: continuously fire while held and cooldown allows
if _input_provider.is_fire_held():
    if _local_player != null and _projectile_system.can_player_fire(_local_player):
        _net_client.fire_pressed_latch = true
        # Spawn muzzle flash and predicted projectile (same as click-to-fire)
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

### Behavior

| Input | Result |
|-------|--------|
| Click | Single shot (unchanged) |
| Hold | Fires immediately, then at cooldown rate (5/sec) while held |
| Release | Stops firing |

### No Changes Required

- **Server**: Already processes fire inputs at whatever rate they arrive
- **ProjectileSystem**: Cooldown already enforced via `can_fire()`
- **Network**: Fire latch already batched per server tick
- **ProjectileSpawnRouter**: No changes, handles fire the same way

## Files to Modify

1. `godot/simulation/input/input_provider.gd` - add `is_fire_held()` stub
2. `godot/simulation/input/keyboard_mouse_input_provider.gd` - implement `is_fire_held()`
3. `godot/client_main.gd` - add hold-to-fire check in `_process()`

## Testing

- Manual: hold fire button, verify continuous firing at cooldown rate
- Manual: tap fire button, verify single shot still works
- Manual: verify ghost state still blocks firing when held
