# Health and Damage System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add health pools to players and enemies, damage application via projectiles, player ghost state on death, and view-layer feedback (floating damage numbers, health bars).

**Architecture:** HealthComponent (pure data) + DamageSystem (orchestration). DamageSystem is injected into ProjectileSystem on the server. Players enter ghost state on death, respawn after 5 seconds. View layer listens to events for visual feedback.

**Tech Stack:** Godot 4, GDScript, GUT testing framework

---

## File Structure

**New files:**
| File | Responsibility |
|------|----------------|
| `simulation/components/health_component.gd` | Pure health math (current, max, take_damage, heal) |
| `simulation/systems/damage_system.gd` | Orchestrates damage, emits events, handles death |
| `tests/components/test_health_component.gd` | Unit tests for HealthComponent |
| `tests/systems/test_damage_system.gd` | Unit tests for DamageSystem |
| `view/effects/damage_number.gd` | Floating damage number behavior |
| `view/effects/damage_number.tscn` | Damage number scene |
| `view/effects/damage_number_spawner.gd` | Spawns damage numbers on hit events |
| `view/ui/enemy_health_bar.gd` | Health bar behavior |
| `view/ui/enemy_health_bar.tscn` | Health bar scene |
| `view/ui/health_bar_manager.gd` | Creates/updates health bars for entities |
| `view/effects/ghost_overlay.gd` | Ghost screen overlay and player ghost visuals |

**Modified files:**
| File | Changes |
|------|---------|
| `simulation/entities/player_movement_state.gd` | Add GHOST = 2 |
| `simulation/entities/player_entity.gd` | Add health field, ghost state, respawn |
| `simulation/entities/enemy_entity.gd` | Add health field |
| `simulation/entities/enemy_params.gd` | Add max_health export |
| `shared/projectiles/projectile_params.gd` | Add damage, element exports |
| `shared/projectiles/frost_bolt_params.tres` | Set damage = 25 |
| `simulation/event_bus.gd` | Add player_ghost_started, player_respawned signals |
| `simulation/systems/projectile_system.gd` | Inject DamageSystem, call apply_damage on hits |
| `simulation/network/net_server.gd` | Create DamageSystem, pass to ProjectileSystem |
| `view/projectiles/projectile_effects.gd` | Use target_entity_id consistently |
| `view/world/world_view.gd` | Use target_entity_id, integrate new view components |

---

## Task 1: HealthComponent

**Files:**
- Create: `godot/simulation/components/health_component.gd`
- Test: `godot/tests/components/test_health_component.gd`

- [ ] **Step 1: Create test file with first test**

```gdscript
# godot/tests/components/test_health_component.gd
extends GutTest

var HealthComponentCls = preload("res://simulation/components/health_component.gd")


func test_init_sets_current_to_max():
	var health = HealthComponentCls.new(100)
	assert_eq(health.current, 100)
	assert_eq(health.max_health, 100)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/components/test_health_component.gd -gexit`

Expected: FAIL — file not found or class missing

- [ ] **Step 3: Create components directory and minimal HealthComponent**

```bash
mkdir -p godot/simulation/components
```

```gdscript
# godot/simulation/components/health_component.gd
class_name HealthComponent
extends RefCounted

var current: int
var max_health: int


func _init(max_hp: int) -> void:
	max_health = max_hp
	current = max_hp
```

- [ ] **Step 4: Rebuild Godot class cache**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import`

- [ ] **Step 5: Run test to verify it passes**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/components/test_health_component.gd -gexit`

Expected: PASS

- [ ] **Step 6: Add test for take_damage**

```gdscript
# Add to test_health_component.gd
func test_take_damage_reduces_current():
	var health = HealthComponentCls.new(100)
	var result = health.take_damage(30)
	assert_eq(health.current, 70)
	assert_eq(result["damage_dealt"], 30)
	assert_false(result["killed"])


func test_take_damage_kills_at_zero():
	var health = HealthComponentCls.new(50)
	var result = health.take_damage(50)
	assert_eq(health.current, 0)
	assert_true(result["killed"])


func test_take_damage_clamps_to_current():
	var health = HealthComponentCls.new(30)
	var result = health.take_damage(100)
	assert_eq(health.current, 0)
	assert_eq(result["damage_dealt"], 30)
	assert_true(result["killed"])
```

- [ ] **Step 7: Run tests to verify they fail**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/components/test_health_component.gd -gexit`

Expected: FAIL — take_damage not defined

- [ ] **Step 8: Implement take_damage**

```gdscript
# Add to health_component.gd
func take_damage(amount: int) -> Dictionary:
	var actual = mini(amount, current)
	current -= actual
	return { "damage_dealt": actual, "killed": current <= 0 }
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/components/test_health_component.gd -gexit`

Expected: PASS (all 4 tests)

- [ ] **Step 10: Add tests for heal and is_dead**

```gdscript
# Add to test_health_component.gd
func test_heal_increases_current():
	var health = HealthComponentCls.new(100)
	health.take_damage(40)
	var healed = health.heal(25)
	assert_eq(health.current, 85)
	assert_eq(healed, 25)


func test_heal_clamps_to_max():
	var health = HealthComponentCls.new(100)
	health.take_damage(20)
	var healed = health.heal(50)
	assert_eq(health.current, 100)
	assert_eq(healed, 20)


func test_is_dead():
	var health = HealthComponentCls.new(50)
	assert_false(health.is_dead())
	health.take_damage(50)
	assert_true(health.is_dead())
```

- [ ] **Step 11: Run tests to verify they fail**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/components/test_health_component.gd -gexit`

Expected: FAIL — heal/is_dead not defined

- [ ] **Step 12: Implement heal and is_dead**

```gdscript
# Add to health_component.gd
func heal(amount: int) -> int:
	var actual = mini(amount, max_health - current)
	current += actual
	return actual


func is_dead() -> bool:
	return current <= 0
```

- [ ] **Step 13: Run tests to verify they pass**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/components/test_health_component.gd -gexit`

Expected: PASS (all 7 tests)

- [ ] **Step 14: Add snapshot serialization tests**

```gdscript
# Add to test_health_component.gd
func test_to_dict():
	var health = HealthComponentCls.new(100)
	health.take_damage(25)
	var data = health.to_dict()
	assert_eq(data["current"], 75)
	assert_eq(data["max"], 100)


func test_from_dict():
	var health = HealthComponentCls.new(100)
	health.from_dict({ "current": 30, "max": 100 })
	assert_eq(health.current, 30)
	assert_eq(health.max_health, 100)
```

- [ ] **Step 15: Implement to_dict and from_dict**

```gdscript
# Add to health_component.gd
func to_dict() -> Dictionary:
	return { "current": current, "max": max_health }


func from_dict(data: Dictionary) -> void:
	current = data.get("current", max_health)
	max_health = data.get("max", max_health)
```

- [ ] **Step 16: Run all tests**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/components/test_health_component.gd -gexit`

Expected: PASS (all 9 tests)

- [ ] **Step 17: Commit**

```bash
git add godot/simulation/components/health_component.gd godot/tests/components/test_health_component.gd
git commit -m "$(cat <<'EOF'
feat: add HealthComponent for entity health tracking

Pure data class with take_damage, heal, is_dead, and snapshot
serialization. No EventBus coupling - just health math.
EOF
)"
```

---

## Task 2: Add damage and element to ProjectileParams

**Files:**
- Modify: `godot/shared/projectiles/projectile_params.gd`
- Modify: `godot/shared/projectiles/frost_bolt_params.tres`

- [ ] **Step 1: Add damage and element exports to ProjectileParams**

```gdscript
# Add to godot/shared/projectiles/projectile_params.gd after knockback_stagger

## Damage dealt on hit. 0 = no damage.
@export var damage: int = 0
## Element type for TCE triggers (e.g., "frost", "fire", "physical")
@export var element: String = "physical"
```

- [ ] **Step 2: Update frost_bolt_params.tres with damage value**

```gdscript
# Add to end of godot/shared/projectiles/frost_bolt_params.tres before final empty line
damage = 25
element = "frost"
```

- [ ] **Step 3: Rebuild Godot class cache**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import`

- [ ] **Step 4: Run existing projectile tests to verify no regression**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/systems/ -ginclude_subdirs -gexit`

Expected: All existing tests PASS

- [ ] **Step 5: Commit**

```bash
git add godot/shared/projectiles/projectile_params.gd godot/shared/projectiles/frost_bolt_params.tres
git commit -m "$(cat <<'EOF'
feat: add damage and element fields to ProjectileParams

Frost bolt deals 25 damage with "frost" element. Prepares for
DamageSystem integration.
EOF
)"
```

---

## Task 3: Add max_health to EnemyParams

**Files:**
- Modify: `godot/simulation/entities/enemy_params.gd`

- [ ] **Step 1: Add max_health export**

```gdscript
# Add to godot/simulation/entities/enemy_params.gd after mass field

## Maximum health. Enemy dies when health reaches 0.
@export var max_health: int = 50
```

- [ ] **Step 2: Run existing enemy tests to verify no regression**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/entities/ -ginclude_subdirs -gexit`

Expected: All existing tests PASS

- [ ] **Step 3: Commit**

```bash
git add godot/simulation/entities/enemy_params.gd
git commit -m "feat: add max_health to EnemyParams (default 50)"
```

---

## Task 4: Add health to EnemyEntity

**Files:**
- Modify: `godot/simulation/entities/enemy_entity.gd`
- Test: `godot/tests/entities/test_enemy_entity.gd`

- [ ] **Step 1: Add health initialization test**

```gdscript
# Add to godot/tests/entities/test_enemy_entity.gd

func test_initialize_creates_health():
	var enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParams.new()
	params.max_health = 75
	enemy.initialize(1, Vector2.ZERO, params)
	assert_eq(enemy.health.current, 75)
	assert_eq(enemy.health.max_health, 75)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_enemy_entity.gd::test_initialize_creates_health -gexit`

Expected: FAIL — health property doesn't exist

- [ ] **Step 3: Add health field and initialization to EnemyEntity**

```gdscript
# Add field after _cached_collision_radius in enemy_entity.gd
var health: HealthComponent = null

# Update initialize() - add after _params = params
health = HealthComponent.new(params.max_health)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_enemy_entity.gd::test_initialize_creates_health -gexit`

Expected: PASS

- [ ] **Step 5: Add health to snapshot test**

```gdscript
# Add to test_enemy_entity.gd

func test_snapshot_includes_health():
	var enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParams.new()
	params.max_health = 100
	enemy.initialize(1, Vector2.ZERO, params)
	enemy.health.take_damage(30)
	var data = enemy.to_snapshot_data()
	assert_eq(data["health"], 70)
	assert_eq(data["max_health"], 100)
```

- [ ] **Step 6: Run test to verify it fails**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_enemy_entity.gd::test_snapshot_includes_health -gexit`

Expected: FAIL — health/max_health not in snapshot

- [ ] **Step 7: Update to_snapshot_data to include health**

```gdscript
# Update to_snapshot_data() in enemy_entity.gd - add to return dict
"health": health.current if health != null else 0,
"max_health": health.max_health if health != null else 0,
```

- [ ] **Step 8: Run all enemy tests**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_enemy_entity.gd -gexit`

Expected: All PASS

- [ ] **Step 9: Commit**

```bash
git add godot/simulation/entities/enemy_entity.gd godot/tests/entities/test_enemy_entity.gd
git commit -m "$(cat <<'EOF'
feat: add health to EnemyEntity

Health initialized from EnemyParams.max_health. Included in snapshot
for client-side health bar display.
EOF
)"
```

---

## Task 5: Add EventBus signals

**Files:**
- Modify: `godot/simulation/event_bus.gd`

- [ ] **Step 1: Add new signals for ghost state**

```gdscript
# Add to godot/simulation/event_bus.gd after player_moved signal

# Player death/respawn
signal player_ghost_started(event: Dictionary)   # entity_id, position, duration
signal player_respawned(event: Dictionary)       # entity_id, position
```

- [ ] **Step 2: Commit**

```bash
git add godot/simulation/event_bus.gd
git commit -m "feat: add player_ghost_started and player_respawned signals"
```

---

## Task 6: Add GHOST state to PlayerMovementState

**Files:**
- Modify: `godot/simulation/entities/player_movement_state.gd`

- [ ] **Step 1: Add GHOST constant**

```gdscript
# Add to godot/simulation/entities/player_movement_state.gd
const GHOST = 2     # dead, no-clip movement, awaiting respawn
```

- [ ] **Step 2: Commit**

```bash
git add godot/simulation/entities/player_movement_state.gd
git commit -m "feat: add GHOST movement state for player death"
```

---

## Task 7: Add health and ghost state to PlayerEntity

**Files:**
- Modify: `godot/simulation/entities/player_entity.gd`
- Test: `godot/tests/entities/test_player_entity.gd`

- [ ] **Step 1: Add test for health initialization**

```gdscript
# Add to godot/tests/entities/test_player_entity.gd

func test_initialize_creates_health():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(1, Vector2.ZERO)
	assert_eq(player.health.current, 100)
	assert_eq(player.health.max_health, 100)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_player_entity.gd::test_initialize_creates_health -gexit`

Expected: FAIL — health property doesn't exist

- [ ] **Step 3: Add health field and constant**

```gdscript
# Add to godot/simulation/entities/player_entity.gd after dodge_cooldown_remaining

# Health
const PLAYER_MAX_HEALTH: int = 100
var health: HealthComponent = null

# Ghost state
var ghost_timer: float = 0.0
const GHOST_DURATION: float = 5.0
```

- [ ] **Step 4: Initialize health in initialize()**

```gdscript
# Update initialize() in player_entity.gd - add after position = spawn_position
health = HealthComponent.new(PLAYER_MAX_HEALTH)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_player_entity.gd::test_initialize_creates_health -gexit`

Expected: PASS

- [ ] **Step 6: Add test for enter_ghost_state**

```gdscript
# Add to test_player_entity.gd

func test_enter_ghost_state():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(1, Vector2(100, 100))
	player.enter_ghost_state()
	assert_eq(player.state, PlayerMovementState.GHOST)
	assert_almost_eq(player.ghost_timer, 5.0, 0.01)
	assert_eq(player.velocity, Vector2.ZERO)
```

- [ ] **Step 7: Run test to verify it fails**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_player_entity.gd::test_enter_ghost_state -gexit`

Expected: FAIL — enter_ghost_state not defined

- [ ] **Step 8: Implement enter_ghost_state**

```gdscript
# Add to player_entity.gd after start_dodge()

func enter_ghost_state() -> void:
	state = PlayerMovementState.GHOST
	ghost_timer = GHOST_DURATION
	velocity = Vector2.ZERO
	dodge_time_remaining = 0.0
	$CollisionShape2D.set_deferred("disabled", true)
	if not _suppress_events:
		EventBus.player_ghost_started.emit({
			"entity_id": player_id,
			"position": position,
			"duration": GHOST_DURATION,
		})
```

- [ ] **Step 9: Run test to verify it passes**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_player_entity.gd::test_enter_ghost_state -gexit`

Expected: PASS

- [ ] **Step 10: Add test for ghost movement and respawn**

```gdscript
# Add to test_player_entity.gd

func test_ghost_advances_and_respawns():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(1, Vector2(100, 100))
	player.health.take_damage(100)  # Kill player
	player.enter_ghost_state()
	
	# Ghost should be able to move
	player.move_input = Vector2(1, 0)
	player.advance(1.0)  # 1 second
	assert_eq(player.state, PlayerMovementState.GHOST)
	assert_almost_eq(player.ghost_timer, 4.0, 0.01)
	
	# Advance past timer
	player.advance(4.1)
	assert_eq(player.state, PlayerMovementState.WALKING)
	assert_eq(player.position, Vector2.ZERO)  # Respawn at center
	assert_eq(player.health.current, 100)  # Full health
```

- [ ] **Step 11: Run test to verify it fails**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_player_entity.gd::test_ghost_advances_and_respawns -gexit`

Expected: FAIL — GHOST state not handled in advance()

- [ ] **Step 12: Add _advance_ghost and _respawn methods**

```gdscript
# Add to player_entity.gd after enter_ghost_state()

func _advance_ghost(dt: float) -> void:
	ghost_timer -= dt
	if move_input.length_squared() > 0.001:
		velocity = move_input.normalized() * params.top_speed
	else:
		velocity *= exp(-params.friction * dt)
	position += velocity * dt  # Direct position update, no collision
	
	if ghost_timer <= 0.0:
		_respawn()


func _respawn() -> void:
	state = PlayerMovementState.WALKING
	position = Vector2.ZERO
	health.current = health.max_health
	velocity = Vector2.ZERO
	ghost_timer = 0.0
	dodge_cooldown_remaining = 0.0
	_ensure_collision_enabled()
	if not _suppress_events:
		EventBus.player_respawned.emit({
			"entity_id": player_id,
			"position": position,
		})


func _ensure_collision_enabled() -> void:
	$CollisionShape2D.set_deferred("disabled", false)
```

- [ ] **Step 13: Add GHOST case to advance() match statement**

```gdscript
# Update advance() in player_entity.gd - add new case to match statement
		PlayerMovementState.GHOST:
			_advance_ghost(dt)
			return  # Skip collision handling for ghost
```

- [ ] **Step 14: Run test to verify it passes**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_player_entity.gd::test_ghost_advances_and_respawns -gexit`

Expected: PASS

- [ ] **Step 15: Add test for ghost cannot dodge or fire**

```gdscript
# Add to test_player_entity.gd

func test_ghost_cannot_dodge():
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(1, Vector2.ZERO)
	player.enter_ghost_state()
	
	# Try to dodge
	player.apply_input({
		"move_direction": Vector2.RIGHT,
		"aim_direction": Vector2.RIGHT,
		"action_flags": MessageTypes.InputActionFlags.DODGE,
	})
	
	# Should still be in ghost state, not dodging
	assert_eq(player.state, PlayerMovementState.GHOST)
```

- [ ] **Step 16: Update apply_input to block actions during ghost**

```gdscript
# Update apply_input() in player_entity.gd - add early return after aim handling
	# Block actions during ghost state
	if state == PlayerMovementState.GHOST:
		return
```

- [ ] **Step 17: Run test to verify it passes**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_player_entity.gd::test_ghost_cannot_dodge -gexit`

Expected: PASS

- [ ] **Step 18: Update to_snapshot_data to include health and ghost_timer**

```gdscript
# Update to_snapshot_data() in player_entity.gd - add to return dict
"health": health.current if health != null else PLAYER_MAX_HEALTH,
"max_health": health.max_health if health != null else PLAYER_MAX_HEALTH,
"ghost_timer": ghost_timer,
```

- [ ] **Step 19: Run all player entity tests**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_player_entity.gd -gexit`

Expected: All PASS

- [ ] **Step 20: Commit**

```bash
git add godot/simulation/entities/player_entity.gd godot/tests/entities/test_player_entity.gd
git commit -m "$(cat <<'EOF'
feat: add health and ghost state to PlayerEntity

- Health initialized to 100
- enter_ghost_state() disables collision, starts 5s timer
- Ghost can move (no-clip) but cannot dodge or fire
- Respawns at center with full health when timer expires
EOF
)"
```

---

## Task 8: DamageSystem

**Files:**
- Create: `godot/simulation/systems/damage_system.gd`
- Test: `godot/tests/systems/test_damage_system.gd`

- [ ] **Step 1: Create test file with enemy damage test**

```gdscript
# godot/tests/systems/test_damage_system.gd
extends GutTest

var DamageSystemCls = preload("res://simulation/systems/damage_system.gd")
var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")
var EnemyParamsCls = preload("res://simulation/entities/enemy_params.gd")


func test_apply_damage_to_enemy():
	var damage_system = DamageSystemCls.new()
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParamsCls.new()
	params.max_health = 100
	enemy.initialize(1, Vector2.ZERO, params)
	
	var result = damage_system.apply_damage(enemy, 30, {
		"source_entity_id": 5,
		"projectile_id": 10,
		"element": "frost",
	})
	
	assert_eq(enemy.health.current, 70)
	assert_eq(result["damage_dealt"], 30)
	assert_false(result["killed"])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_damage_system.gd -gexit`

Expected: FAIL — file not found

- [ ] **Step 3: Create minimal DamageSystem**

```gdscript
# godot/simulation/systems/damage_system.gd
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
		"remaining_health": target.health.current,
		"max_health": target.health.max_health,
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

- [ ] **Step 4: Rebuild Godot class cache**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --import`

- [ ] **Step 5: Run test to verify it passes**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_damage_system.gd -gexit`

Expected: PASS

- [ ] **Step 6: Add test for enemy death**

```gdscript
# Add to test_damage_system.gd

func test_apply_damage_kills_enemy():
	var damage_system = DamageSystemCls.new()
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParamsCls.new()
	params.max_health = 50
	enemy.initialize(1, Vector2.ZERO, params)
	
	var result = damage_system.apply_damage(enemy, 50, {})
	
	assert_eq(enemy.health.current, 0)
	assert_true(result["killed"])
	assert_eq(enemy.state, EnemyEntity.State.DEAD)
```

- [ ] **Step 7: Run test to verify it passes**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_damage_system.gd::test_apply_damage_kills_enemy -gexit`

Expected: PASS

- [ ] **Step 8: Add test for player damage and ghost state**

```gdscript
# Add to test_damage_system.gd
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


func test_apply_damage_to_player():
	var damage_system = DamageSystemCls.new()
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(1, Vector2.ZERO)
	
	var result = damage_system.apply_damage(player, 40, {
		"source_entity_id": 99,
		"element": "frost",
	})
	
	assert_eq(player.health.current, 60)
	assert_eq(result["damage_dealt"], 40)
	assert_false(result["killed"])


func test_apply_damage_kills_player():
	var damage_system = DamageSystemCls.new()
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(1, Vector2(100, 100))
	
	var result = damage_system.apply_damage(player, 100, {})
	
	assert_true(result["killed"])
	assert_eq(player.state, PlayerMovementState.GHOST)
```

- [ ] **Step 9: Run all damage system tests**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_damage_system.gd -gexit`

Expected: All PASS

- [ ] **Step 10: Commit**

```bash
git add godot/simulation/systems/damage_system.gd godot/tests/systems/test_damage_system.gd
git commit -m "$(cat <<'EOF'
feat: add DamageSystem for damage orchestration

Applies damage to entities, emits hit/died events with full context,
handles death transitions (player -> ghost, enemy -> DEAD).
EOF
)"
```

---

## Task 9: Integrate DamageSystem into ProjectileSystem

**Files:**
- Modify: `godot/simulation/systems/projectile_system.gd`
- Modify: `godot/simulation/network/net_server.gd`
- Test: `godot/tests/systems/test_projectile_system_damage.gd`

- [ ] **Step 1: Create test file for projectile damage**

```gdscript
# godot/tests/systems/test_projectile_system_damage.gd
extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var DamageSystemCls = preload("res://simulation/systems/damage_system.gd")
var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")
var EnemyParamsCls = preload("res://simulation/entities/enemy_params.gd")
var ProjectileParamsCls = preload("res://shared/projectiles/projectile_params.gd")


func test_projectile_damages_enemy_on_hit():
	var projectile_system = ProjectileSystemCls.new()
	var damage_system = DamageSystemCls.new()
	projectile_system.set_damage_system(damage_system)
	add_child_autofree(projectile_system)
	
	# Create enemy
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParamsCls.new()
	params.max_health = 100
	enemy.initialize(1, Vector2(50, 0), params)
	enemy._set_state(EnemyEntity.State.IDLE)  # Not spawning
	
	# Spawn projectile heading toward enemy
	var proj = projectile_system.spawn_authoritative(99, 0, Vector2.ZERO, Vector2.RIGHT, 1)
	proj.params.damage = 25
	proj.params.radius = 10.0
	
	# Advance until hit
	projectile_system.advance(0.1, [], [enemy])
	
	# Enemy should have taken damage
	assert_eq(enemy.health.current, 75, "Enemy should have taken 25 damage")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_system_damage.gd -gexit`

Expected: FAIL — set_damage_system not defined

- [ ] **Step 3: Add DamageSystem injection to ProjectileSystem**

```gdscript
# Add to godot/simulation/systems/projectile_system.gd after _current_rtt_ms field
var _damage_system: DamageSystem = null


func set_damage_system(damage_system: DamageSystem) -> void:
	_damage_system = damage_system
```

- [ ] **Step 4: Update advance() to apply damage on entity hits**

```gdscript
# Update advance() in projectile_system.gd
# Replace the existing "Apply knockback on enemy hit" block with:

			# Apply damage and knockback on entity hits
			if _damage_system != null:
				var source_info = {
					"source_entity_id": p.owner_player_id,
					"projectile_id": p.projectile_id,
					"element": p.params.element,
				}
				
				if reason == ProjectileEntity.DespawnReason.ENEMY:
					var enemy: EnemyEntity = enemy_lookup.get(p.last_hit_entity_id)
					if enemy != null:
						_damage_system.apply_damage(enemy, p.params.damage, source_info)
						if p.params.knockback_force > 0.0:
							enemy.apply_knockback(
								p.direction,
								p.params.knockback_force,
								p.params.knockback_stagger
							)
				
				elif reason == ProjectileEntity.DespawnReason.PLAYER:
					var player = player_lookup.get(p.last_hit_entity_id)
					if player != null:
						_damage_system.apply_damage(player, p.params.damage, source_info)
				
				elif reason == ProjectileEntity.DespawnReason.SELF:
					var player = player_lookup.get(p.owner_player_id)
					if player != null:
						_damage_system.apply_damage(player, p.params.damage, source_info)
			
			elif reason == ProjectileEntity.DespawnReason.ENEMY:
				# Fallback: apply knockback without damage (client-side)
				var enemy: EnemyEntity = enemy_lookup.get(p.last_hit_entity_id)
				if enemy != null and p.params.knockback_force > 0.0:
					enemy.apply_knockback(
						p.direction,
						p.params.knockback_force,
						p.params.knockback_stagger
					)
```

- [ ] **Step 5: Add player_lookup to advance()**

```gdscript
# Update advance() in projectile_system.gd - add after enemy_lookup creation
	var player_lookup: Dictionary = {}
	for player in players:
		player_lookup[player.player_id] = player
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_system_damage.gd -gexit`

Expected: PASS

- [ ] **Step 7: Add test for friendly fire**

```gdscript
# Add to test_projectile_system_damage.gd
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


func test_projectile_damages_other_player():
	var projectile_system = ProjectileSystemCls.new()
	var damage_system = DamageSystemCls.new()
	projectile_system.set_damage_system(damage_system)
	add_child_autofree(projectile_system)
	
	# Create target player
	var target = PlayerEntityScene.instantiate()
	add_child_autofree(target)
	target.initialize(2, Vector2(50, 0))
	
	# Spawn projectile from different player
	var proj = projectile_system.spawn_authoritative(1, 0, Vector2.ZERO, Vector2.RIGHT, 1)
	proj.params.damage = 25
	proj.params.radius = 10.0
	proj.params.spawn_grace = 0.0  # No grace period
	
	# Advance until hit
	projectile_system.advance(0.1, [target], [])
	
	assert_eq(target.health.current, 75, "Target should have taken 25 damage")
```

- [ ] **Step 8: Run test to verify it passes**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_projectile_system_damage.gd::test_projectile_damages_other_player -gexit`

Expected: PASS

- [ ] **Step 9: Update NetServer to create and inject DamageSystem**

```gdscript
# Add to godot/simulation/network/net_server.gd after _player_position_history declaration
var _damage_system: DamageSystem

# Update _ready() - add after _projectile_system creation
	_damage_system = DamageSystem.new()
	_projectile_system.set_damage_system(_damage_system)
```

- [ ] **Step 10: Run existing projectile tests to verify no regression**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/systems/ -ginclude_subdirs -gexit`

Expected: All PASS

- [ ] **Step 11: Commit**

```bash
git add godot/simulation/systems/projectile_system.gd godot/simulation/network/net_server.gd godot/tests/systems/test_projectile_system_damage.gd
git commit -m "$(cat <<'EOF'
feat: integrate DamageSystem into ProjectileSystem

Server injects DamageSystem into ProjectileSystem. On hit:
- Enemies take damage, knockback still applies
- Players take damage (friendly fire enabled)
- Self-damage on own projectile hit
EOF
)"
```

---

## Task 10: Block firing during ghost state

**Files:**
- Modify: `godot/simulation/systems/projectile_system.gd`

- [ ] **Step 1: Update can_fire to check ghost state**

The current `can_fire(player_id)` signature doesn't have access to player state. We need to add a player parameter or check it at the call site. The cleaner approach is to check at the call site in NetServer where we have the player entity.

For now, add a separate method:

```gdscript
# Add to projectile_system.gd after can_fire()

func can_player_fire(player: PlayerEntity) -> bool:
	if player.state == PlayerMovementState.GHOST:
		return false
	return can_fire(player.player_id)
```

- [ ] **Step 2: Commit**

```bash
git add godot/simulation/systems/projectile_system.gd
git commit -m "feat: add can_player_fire() to block firing during ghost state"
```

---

## Task 11: Update view layer to use target_entity_id consistently

**Files:**
- Modify: `godot/view/projectiles/projectile_effects.gd`
- Modify: `godot/view/world/world_view.gd`

- [ ] **Step 1: Update projectile_effects.gd to use target_entity_id**

```gdscript
# Update _flash_enemy() in godot/view/projectiles/projectile_effects.gd
func _flash_enemy(entity_id: int, color: Color, duration: float, cling_scene: PackedScene = null) -> void:
	EventBus.enemy_hit.emit({
		"target_entity_id": entity_id,  # Changed from entity_id
		"flash_color": color,
		"flash_duration": duration,
		"cling_scene": cling_scene,
	})
```

- [ ] **Step 2: Update world_view.gd to use target_entity_id**

```gdscript
# Update _on_enemy_hit() in godot/view/world/world_view.gd
func _on_enemy_hit(event: Dictionary) -> void:
	var entity_id: int = event.get("target_entity_id", event.get("entity_id", -1))  # Support both
	var flash_color: Color = event.get("flash_color", Color.WHITE)
	var flash_duration: float = event.get("flash_duration", 0.1)
	var cling_scene: PackedScene = event.get("cling_scene", null)
	# ... rest unchanged
```

- [ ] **Step 3: Commit**

```bash
git add godot/view/projectiles/projectile_effects.gd godot/view/world/world_view.gd
git commit -m "refactor: use target_entity_id consistently in hit events"
```

---

## Task 12: Damage Number View Component

**Files:**
- Create: `godot/view/effects/damage_number.gd`
- Create: `godot/view/effects/damage_number.tscn`
- Create: `godot/view/effects/damage_number_spawner.gd`
- Modify: `godot/view/world/world_view.gd`

- [ ] **Step 1: Create damage_number.gd**

```gdscript
# godot/view/effects/damage_number.gd
extends Label

var velocity: Vector2 = Vector2(0, -60)
var lifetime: float = 0.8
var _age: float = 0.0


func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 16)
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 2)
	z_index = 100


func _process(delta: float) -> void:
	_age += delta
	position += velocity * delta
	velocity.y += 80 * delta  # Slight gravity
	
	# Fade out
	var progress = _age / lifetime
	modulate.a = 1.0 - progress
	
	if _age >= lifetime:
		queue_free()
```

- [ ] **Step 2: Create damage_number.tscn**

```
; godot/view/effects/damage_number.tscn
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://view/effects/damage_number.gd" id="1_script"]

[node name="DamageNumber" type="Label"]
script = ExtResource("1_script")
```

- [ ] **Step 3: Create damage_number_spawner.gd**

```gdscript
# godot/view/effects/damage_number_spawner.gd
extends Node

var DamageNumberScene: PackedScene = preload("res://view/effects/damage_number.tscn")
var _parent: Node2D = null


func initialize(parent: Node2D) -> void:
	_parent = parent
	EventBus.enemy_hit.connect(_on_hit)
	EventBus.player_hit.connect(_on_hit)


func _on_hit(event: Dictionary) -> void:
	var damage: int = event.get("damage", 0)
	if damage <= 0:
		return
	
	var pos: Vector2 = event.get("position", Vector2.ZERO)
	# Add slight random offset so multiple hits don't stack
	pos += Vector2((randf() - 0.5) * 20, (randf() - 0.5) * 10)
	
	var number = DamageNumberScene.instantiate()
	number.text = str(damage)
	number.position = pos
	_parent.add_child(number)


func _exit_tree() -> void:
	if EventBus.enemy_hit.is_connected(_on_hit):
		EventBus.enemy_hit.disconnect(_on_hit)
	if EventBus.player_hit.is_connected(_on_hit):
		EventBus.player_hit.disconnect(_on_hit)
```

- [ ] **Step 4: Integrate into WorldView**

```gdscript
# Add to godot/view/world/world_view.gd initialize() after wall_bump initialization
	var damage_number_spawner = preload("res://view/effects/damage_number_spawner.gd").new()
	add_child(damage_number_spawner)
	damage_number_spawner.initialize(self)
```

- [ ] **Step 5: Test manually by running the game**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --path . res://client.tscn`

Expected: Shooting enemies shows floating damage numbers

- [ ] **Step 6: Commit**

```bash
git add godot/view/effects/damage_number.gd godot/view/effects/damage_number.tscn godot/view/effects/damage_number_spawner.gd godot/view/world/world_view.gd
git commit -m "$(cat <<'EOF'
feat: add floating damage numbers on hit

Numbers float up, fade out over 0.8s. Spawned for both enemy and
player hits.
EOF
)"
```

---

## Task 13: Enemy Health Bar View Component

**Files:**
- Create: `godot/view/ui/enemy_health_bar.gd`
- Create: `godot/view/ui/enemy_health_bar.tscn`
- Create: `godot/view/ui/health_bar_manager.gd`
- Modify: `godot/view/world/world_view.gd`

- [ ] **Step 1: Create enemy_health_bar.gd**

```gdscript
# godot/view/ui/enemy_health_bar.gd
extends Control

var entity_id: int = -1
var _target_node: Node2D = null
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _max_health: int = 100
var _current_health: int = 100

const BAR_WIDTH: float = 24.0
const BAR_HEIGHT: float = 4.0
const BAR_OFFSET: Vector2 = Vector2(0, -16)


func _ready() -> void:
	# Background (dark)
	_bar_bg = ColorRect.new()
	_bar_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_bg.position = Vector2(-BAR_WIDTH / 2, 0)
	_bar_bg.color = Color(0.2, 0.2, 0.2, 0.8)
	add_child(_bar_bg)
	
	# Fill (green -> yellow -> red based on health)
	_bar_fill = ColorRect.new()
	_bar_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_fill.position = Vector2(-BAR_WIDTH / 2, 0)
	_bar_fill.color = Color(0.2, 0.8, 0.2)
	add_child(_bar_fill)
	
	z_index = 50


func initialize(id: int, target: Node2D, max_hp: int, current_hp: int) -> void:
	entity_id = id
	_target_node = target
	_max_health = max_hp
	_current_health = current_hp
	_update_bar()


func update_health(current_hp: int, max_hp: int) -> void:
	_current_health = current_hp
	_max_health = max_hp
	_update_bar()


func _update_bar() -> void:
	var ratio = float(_current_health) / float(_max_health) if _max_health > 0 else 0.0
	_bar_fill.size.x = BAR_WIDTH * ratio
	
	# Color: green -> yellow -> red
	if ratio > 0.5:
		_bar_fill.color = Color(0.2, 0.8, 0.2)
	elif ratio > 0.25:
		_bar_fill.color = Color(0.9, 0.8, 0.1)
	else:
		_bar_fill.color = Color(0.9, 0.2, 0.1)
	
	# Hide at full health
	visible = _current_health < _max_health


func _process(_delta: float) -> void:
	if _target_node != null and is_instance_valid(_target_node):
		global_position = _target_node.global_position + BAR_OFFSET
	else:
		queue_free()
```

- [ ] **Step 2: Create enemy_health_bar.tscn**

```
; godot/view/ui/enemy_health_bar.tscn
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://view/ui/enemy_health_bar.gd" id="1_script"]

[node name="EnemyHealthBar" type="Control"]
script = ExtResource("1_script")
```

- [ ] **Step 3: Create health_bar_manager.gd**

```gdscript
# godot/view/ui/health_bar_manager.gd
extends Node

var HealthBarScene: PackedScene = preload("res://view/ui/enemy_health_bar.tscn")
var _parent: Node2D = null
var _bars: Dictionary = {}  # entity_id -> health bar node
var _enemy_views: Dictionary = {}  # Reference to WorldView's enemy views


func initialize(parent: Node2D, enemy_views: Dictionary) -> void:
	_parent = parent
	_enemy_views = enemy_views
	EventBus.enemy_hit.connect(_on_enemy_hit)
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_died.connect(_on_enemy_died)


func _on_enemy_spawned(event: Dictionary) -> void:
	var entity_id: int = event.get("entity_id", -1)
	if entity_id < 0:
		return
	# Health bar created lazily on first damage


func _on_enemy_hit(event: Dictionary) -> void:
	var entity_id: int = event.get("target_entity_id", event.get("entity_id", -1))
	if entity_id < 0:
		return
	
	var enemy_view = _enemy_views.get(entity_id)
	if enemy_view == null:
		return
	
	var max_hp: int = event.get("max_health", 50)
	var current_hp: int = event.get("remaining_health", max_hp)
	
	# Create bar if doesn't exist
	if not _bars.has(entity_id):
		var bar = HealthBarScene.instantiate()
		_parent.add_child(bar)
		bar.initialize(entity_id, enemy_view, max_hp, current_hp)
		_bars[entity_id] = bar
	else:
		var bar = _bars[entity_id]
		bar.update_health(current_hp, max_hp)


func _on_enemy_died(event: Dictionary) -> void:
	var entity_id: int = event.get("target_entity_id", event.get("entity_id", -1))
	_remove_bar(entity_id)


func _remove_bar(entity_id: int) -> void:
	if _bars.has(entity_id):
		_bars[entity_id].queue_free()
		_bars.erase(entity_id)


func _exit_tree() -> void:
	if EventBus.enemy_hit.is_connected(_on_enemy_hit):
		EventBus.enemy_hit.disconnect(_on_enemy_hit)
	if EventBus.enemy_spawned.is_connected(_on_enemy_spawned):
		EventBus.enemy_spawned.disconnect(_on_enemy_spawned)
	if EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.disconnect(_on_enemy_died)
```

- [ ] **Step 4: Integrate into WorldView**

```gdscript
# Add to godot/view/world/world_view.gd initialize() after damage_number_spawner
	var health_bar_manager = preload("res://view/ui/health_bar_manager.gd").new()
	add_child(health_bar_manager)
	health_bar_manager.initialize(self, _enemy_views)
```

- [ ] **Step 5: Test manually**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --path . res://client.tscn`

Expected: Health bars appear above damaged enemies, hidden at full health

- [ ] **Step 6: Commit**

```bash
git add godot/view/ui/enemy_health_bar.gd godot/view/ui/enemy_health_bar.tscn godot/view/ui/health_bar_manager.gd godot/view/world/world_view.gd
git commit -m "$(cat <<'EOF'
feat: add enemy health bars

Bars appear above enemies after taking damage. Color shifts from
green to yellow to red. Hidden at full health.
EOF
)"
```

---

## Task 14: Ghost Overlay View Component

**Files:**
- Create: `godot/view/effects/ghost_overlay.gd`
- Modify: `godot/view/world/world_view.gd`
- Modify: `godot/view/world/player_view.gd`

- [ ] **Step 1: Create ghost_overlay.gd**

```gdscript
# godot/view/effects/ghost_overlay.gd
extends CanvasLayer

var _overlay: ColorRect
var _timer_label: Label
var _ghost_timer: float = 0.0
var _is_ghost: bool = false
var _local_player_id: int = -1
var _player_views: Dictionary = {}


func initialize(local_player_id: int, player_views: Dictionary) -> void:
	_local_player_id = local_player_id
	_player_views = player_views
	
	# Screen overlay (blue tint)
	_overlay = ColorRect.new()
	_overlay.color = Color(0.1, 0.1, 0.3, 0.4)
	_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_overlay.visible = false
	add_child(_overlay)
	
	# Countdown timer
	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label.anchors_preset = Control.PRESET_CENTER
	_timer_label.add_theme_font_size_override("font_size", 48)
	_timer_label.add_theme_color_override("font_color", Color.WHITE)
	_timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_timer_label.add_theme_constant_override("outline_size", 4)
	_timer_label.visible = false
	add_child(_timer_label)
	
	EventBus.player_ghost_started.connect(_on_ghost_started)
	EventBus.player_respawned.connect(_on_respawned)


func _on_ghost_started(event: Dictionary) -> void:
	var entity_id: int = event.get("entity_id", -1)
	
	# Set player view to ghost visual
	_set_player_ghost_visual(entity_id, true)
	
	# Show overlay for local player
	if entity_id == _local_player_id:
		_is_ghost = true
		_ghost_timer = event.get("duration", 5.0)
		_overlay.visible = true
		_timer_label.visible = true


func _on_respawned(event: Dictionary) -> void:
	var entity_id: int = event.get("entity_id", -1)
	
	# Clear ghost visual
	_set_player_ghost_visual(entity_id, false)
	
	# Hide overlay for local player
	if entity_id == _local_player_id:
		_is_ghost = false
		_overlay.visible = false
		_timer_label.visible = false


func _set_player_ghost_visual(entity_id: int, is_ghost: bool) -> void:
	var view = _player_views.get(entity_id)
	if view != null and view.has_method("set_ghost_visual"):
		view.set_ghost_visual(is_ghost)


func _process(delta: float) -> void:
	if _is_ghost:
		_ghost_timer = maxf(0.0, _ghost_timer - delta)
		_timer_label.text = "%.1f" % _ghost_timer


func _exit_tree() -> void:
	if EventBus.player_ghost_started.is_connected(_on_ghost_started):
		EventBus.player_ghost_started.disconnect(_on_ghost_started)
	if EventBus.player_respawned.is_connected(_on_respawned):
		EventBus.player_respawned.disconnect(_on_respawned)
```

- [ ] **Step 2: Add set_ghost_visual to player_view.gd**

First, read the current player_view.gd to understand its structure:

```gdscript
# Add to godot/view/world/player_view.gd

func set_ghost_visual(is_ghost: bool) -> void:
	if is_ghost:
		modulate = Color(0.5, 0.5, 0.8, 0.5)  # Translucent blue
	else:
		modulate = Color.WHITE
```

- [ ] **Step 3: Integrate GhostOverlay into WorldView**

```gdscript
# Add field to godot/view/world/world_view.gd
var _ghost_overlay = null

# Add to initialize() after health_bar_manager
	_ghost_overlay = preload("res://view/effects/ghost_overlay.gd").new()
	add_child(_ghost_overlay)
```

```gdscript
# Add to _on_connected() in world_view.gd
func _on_connected(player_id: int):
	if _ghost_overlay != null:
		_ghost_overlay.initialize(player_id, _player_views)
```

- [ ] **Step 4: Test manually**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --path . res://client.tscn`

Expected: When player dies, screen gets blue overlay with countdown timer. Player appears translucent.

- [ ] **Step 5: Commit**

```bash
git add godot/view/effects/ghost_overlay.gd godot/view/world/player_view.gd godot/view/world/world_view.gd
git commit -m "$(cat <<'EOF'
feat: add ghost overlay and translucent player visual on death

Local player sees blue screen overlay with countdown timer.
All ghost players appear translucent.
EOF
)"
```

---

## Task 15: Final Integration Test

**Files:**
- Test manually

- [ ] **Step 1: Run all tests**

Run: `cd godot && /Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/ -ginclude_subdirs -gexit`

Expected: All tests PASS

- [ ] **Step 2: Manual playtest**

Run: `./dev.sh` (or equivalent to start server + client)

Test:
1. Shoot enemy - should see damage number, health bar appears
2. Kill enemy - health bar disappears, enemy dies
3. Get hit by enemy (if implemented) or friendly fire - player takes damage
4. Die - ghost state with overlay and timer
5. Wait 5 seconds - respawn at center with full health

- [ ] **Step 3: Commit any fixes**

If issues found, fix and commit with descriptive message.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete health and damage system implementation"
```

---

## Summary

This plan implements:
1. **HealthComponent** - pure health math
2. **DamageSystem** - damage orchestration with events
3. **Player ghost state** - 5s death state, respawn at center
4. **Enemy health** - configurable via EnemyParams
5. **Projectile damage** - integrated into ProjectileSystem
6. **View feedback** - damage numbers, health bars, ghost overlay

All systems are server-authoritative. Client-side prediction works for movement but damage is only applied on the server.
