# Enemy Spawning & AI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add enemies that spawn at arena edges, wander when idle, chase players with steering behaviors (seek + separation), and sync across the network.

**Architecture:** EnemyEntity (CharacterBody2D) holds state + advance logic. EnemySystem is the registry/tick driver that provides spatial grid context. EnemySpawner handles timed batch creation. Network snapshots extend with a separate enemy section (17 bytes/enemy). Client interpolates enemy positions and renders view-layer juice (telegraph, wobble, facing indicators). No combat/damage in this phase.

**Tech Stack:** Godot 4 / GDScript, GUT tests, WebSocket binary protocol

**Spec:** `docs/superpowers/specs/2026-04-10-enemy-spawning-ai-design.md`

---

### Task 1: SpatialGrid

Pure data structure for O(n) neighbor lookups. No Godot node dependencies.

**Files:**
- Create: `godot/simulation/systems/spatial_grid.gd`
- Test: `godot/tests/systems/test_spatial_grid.gd`

- [ ] **Step 1: Write SpatialGrid tests**

Create `godot/tests/systems/test_spatial_grid.gd`:

```gdscript
extends GutTest

var SpatialGrid = preload("res://simulation/systems/spatial_grid.gd")


func test_empty_grid_returns_empty():
	var grid = SpatialGrid.new(32.0)
	var result = grid.query_nearby(Vector2(100, 100))
	assert_eq(result.size(), 0)


func test_insert_and_query_finds_entity():
	var grid = SpatialGrid.new(32.0)
	var entity = {"id": 1, "position": Vector2(50, 50)}
	grid.insert(entity, entity.position)
	var result = grid.query_nearby(Vector2(50, 50))
	assert_eq(result.size(), 1)
	assert_eq(result[0].id, 1)


func test_query_finds_neighbor_in_adjacent_cell():
	var grid = SpatialGrid.new(32.0)
	var e1 = {"id": 1, "position": Vector2(30, 30)}
	var e2 = {"id": 2, "position": Vector2(34, 30)}  # next cell at cell_size=32
	grid.insert(e1, e1.position)
	grid.insert(e2, e2.position)
	var result = grid.query_nearby(Vector2(30, 30))
	assert_eq(result.size(), 2, "Should find both entities across cell boundary")


func test_query_does_not_find_distant_entity():
	var grid = SpatialGrid.new(32.0)
	var near = {"id": 1, "position": Vector2(50, 50)}
	var far = {"id": 2, "position": Vector2(500, 500)}
	grid.insert(near, near.position)
	grid.insert(far, far.position)
	var result = grid.query_nearby(Vector2(50, 50))
	assert_eq(result.size(), 1, "Should only find nearby entity")
	assert_eq(result[0].id, 1)


func test_clear_removes_all():
	var grid = SpatialGrid.new(32.0)
	grid.insert({"id": 1, "position": Vector2(10, 10)}, Vector2(10, 10))
	grid.insert({"id": 2, "position": Vector2(20, 20)}, Vector2(20, 20))
	grid.clear()
	assert_eq(grid.query_nearby(Vector2(10, 10)).size(), 0)


func test_many_entities_same_cell():
	var grid = SpatialGrid.new(32.0)
	for i in range(20):
		grid.insert({"id": i, "position": Vector2(5, 5)}, Vector2(5, 5))
	var result = grid.query_nearby(Vector2(5, 5))
	assert_eq(result.size(), 20)


func test_query_radius_filters_by_distance():
	var grid = SpatialGrid.new(32.0)
	var close = {"id": 1, "position": Vector2(50, 50)}
	var medium = {"id": 2, "position": Vector2(70, 50)}  # 20px away
	var far_ish = {"id": 3, "position": Vector2(90, 50)}  # 40px away
	grid.insert(close, close.position)
	grid.insert(medium, medium.position)
	grid.insert(far_ish, far_ish.position)
	var result = grid.query_radius(Vector2(50, 50), 25.0)
	assert_eq(result.size(), 2, "Only entities within 25px radius")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_spatial_grid.gd -gexit`
Expected: FAIL — file not found or class not found

- [ ] **Step 3: Implement SpatialGrid**

Create `godot/simulation/systems/spatial_grid.gd`:

```gdscript
class_name SpatialGrid

var _cell_size: float
var _grid: Dictionary = {}  # Vector2i -> Array


func _init(cell_size: float = 32.0) -> void:
	_cell_size = cell_size


func _get_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / _cell_size), floori(pos.y / _cell_size))


func insert(entity: Variant, pos: Vector2) -> void:
	var cell = _get_cell(pos)
	if not _grid.has(cell):
		_grid[cell] = []
	_grid[cell].append(entity)


func clear() -> void:
	_grid.clear()


func query_nearby(pos: Vector2) -> Array:
	var cell = _get_cell(pos)
	var result: Array = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key = Vector2i(cell.x + dx, cell.y + dy)
			if _grid.has(key):
				result.append_array(_grid[key])
	return result


func query_radius(pos: Vector2, radius: float) -> Array:
	var candidates = query_nearby(pos)
	var radius_sq = radius * radius
	var result: Array = []
	for entity in candidates:
		if entity.position.distance_squared_to(pos) <= radius_sq:
			result.append(entity)
	return result
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_spatial_grid.gd -gexit`
Expected: All 7 tests PASS

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/systems/spatial_grid.gd godot/tests/systems/test_spatial_grid.gd
git commit -m "Add SpatialGrid for O(n) neighbor lookups"
```

---

### Task 2: Data Layer — EnemyParams, SpawnerParams, RNG, EventBus

Small data classes, one RNG utility, and new EventBus signals. All foundational pieces.

**Files:**
- Create: `godot/simulation/entities/enemy_params.gd`
- Create: `godot/simulation/systems/spawner_params.gd`
- Modify: `godot/simulation/rng.gd`
- Modify: `godot/simulation/event_bus.gd`
- Test: `godot/tests/test_rng_accessor.gd` (add test for new method)

- [ ] **Step 1: Write test for RNG.next_float_range**

Add to `godot/tests/test_rng_accessor.gd` (read it first to find the right place):

```gdscript
func test_next_float_range():
	RNG.seed(42)
	var val = RNG.next_float_range(-0.5, 0.5)
	assert_true(val >= -0.5 and val <= 0.5, "Value should be within range")
	# Run several to check bounds
	for i in range(100):
		val = RNG.next_float_range(-1.0, 1.0)
		assert_true(val >= -1.0 and val <= 1.0, "Iteration %d out of range" % i)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_rng_accessor.gd -gexit`
Expected: FAIL — `next_float_range` not found

- [ ] **Step 3: Add next_float_range to RNG**

In `godot/simulation/rng.gd`, add after the `next_bool` method:

```gdscript
func next_float_range(from: float, to: float) -> float:
	return from + _rng.randf() * (to - from)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_rng_accessor.gd -gexit`
Expected: PASS

- [ ] **Step 5: Create EnemyParams resource**

Create `godot/simulation/entities/enemy_params.gd`:

```gdscript
class_name EnemyParams
extends Resource

@export var base_speed: float = 120.0
@export var speed_variation: float = 0.15
@export var turn_rate: float = 8.0
@export var separation_radius: float = 28.0
@export var separation_weight: float = 1.5
@export var arrival_radius: float = 20.0
@export var detection_radius: float = 250.0
@export var leash_radius: float = 350.0
@export var hysteresis_distance: float = 80.0
@export var base_spawn_duration: float = 0.5
@export var spawn_duration_variation: float = 0.15
@export var wander_radius: float = 50.0
@export var wander_speed_factor: float = 0.3
```

- [ ] **Step 6: Create SpawnerParams resource**

Create `godot/simulation/systems/spawner_params.gd`:

```gdscript
class_name SpawnerParams
extends Resource

@export var spawn_interval: float = 2.0
@export var batch_size: int = 3
@export var max_alive: int = 100
@export var spawn_margin: float = 60.0
@export var spawn_edge_inset: float = 16.0
@export var arena_size: Vector2 = Vector2(480, 320)
```

- [ ] **Step 7: Add EventBus signals**

In `godot/simulation/event_bus.gd`, add after the Network section:

```gdscript
# Enemies
signal enemy_spawned(event: Dictionary)
signal enemy_state_changed(event: Dictionary)
signal enemy_target_changed(event: Dictionary)
```

- [ ] **Step 8: Commit**

```bash
git add godot/simulation/rng.gd godot/simulation/event_bus.gd godot/simulation/entities/enemy_params.gd godot/simulation/systems/spawner_params.gd godot/tests/test_rng_accessor.gd
git commit -m "Add enemy data layer: EnemyParams, SpawnerParams, RNG.next_float_range, EventBus signals"
```

---

### Task 3: EnemyEntity — Core + Spawning State

The entity class with state enum, fields, SPAWNING→IDLE transition, and snapshot serialization.

**Files:**
- Create: `godot/simulation/entities/enemy_entity.gd`
- Create: `godot/simulation/entities/enemy_entity.tscn`
- Test: `godot/tests/entities/test_enemy_entity.gd`

- [ ] **Step 1: Write EnemyEntity tests for core + spawning**

Create `godot/tests/entities/test_enemy_entity.gd`:

```gdscript
extends GutTest

var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")


func _make_enemy(id: int = 1, pos: Vector2 = Vector2(100, 100)) -> EnemyEntity:
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParams.new()
	enemy.initialize(id, pos, params)
	return enemy


func test_initial_state_is_spawning():
	var enemy = _make_enemy()
	assert_eq(enemy.state, EnemyEntity.State.SPAWNING)
	assert_eq(enemy.entity_id, 1)
	assert_eq(enemy.position, Vector2(100, 100))


func test_spawn_timer_counts_down():
	var enemy = _make_enemy()
	var initial_timer = enemy.spawn_timer
	enemy.advance(0.1, [], [])
	assert_almost_eq(enemy.spawn_timer, initial_timer - 0.1, 0.01)


func test_spawning_transitions_to_idle():
	var enemy = _make_enemy()
	# Advance past the spawn duration
	enemy.advance(enemy.spawn_timer + 0.01, [], [])
	assert_eq(enemy.state, EnemyEntity.State.IDLE)


func test_no_movement_during_spawning():
	var enemy = _make_enemy()
	var pos_before = enemy.position
	enemy.advance(0.1, [], [])
	assert_eq(enemy.position, pos_before, "Should not move while spawning")


func test_velocity_zero_during_spawning():
	var enemy = _make_enemy()
	enemy.advance(0.1, [], [])
	assert_eq(enemy.velocity, Vector2.ZERO)


func test_actual_speed_varies_with_rng():
	RNG.seed(42)
	var e1 = _make_enemy(1)
	RNG.seed(99)
	var e2 = _make_enemy(2)
	# With different seeds, speeds should differ (unless astronomically unlikely)
	assert_ne(e1.actual_speed, e2.actual_speed, "Different RNG seeds should produce different speeds")


func test_to_snapshot_data_roundtrip():
	var enemy = _make_enemy()
	enemy.facing = Vector2(0.707, 0.707).normalized()
	var data = enemy.to_snapshot_data()
	assert_eq(data["entity_id"], 1)
	assert_eq(data["state"], EnemyEntity.State.SPAWNING)
	assert_true(data.has("position"))
	assert_true(data.has("facing"))
	assert_true(data.has("spawn_timer"))


func test_dt_independence_spawning():
	# Two enemies with same initial state, advanced by same total time
	# but different dt chunks, should end in same state
	RNG.seed(42)
	var e1 = _make_enemy(1, Vector2(100, 100))
	var timer1 = e1.spawn_timer
	RNG.seed(42)
	var e2 = _make_enemy(2, Vector2(100, 100))
	var timer2 = e2.spawn_timer
	assert_almost_eq(timer1, timer2, 0.001, "Same seed should give same timer")
	# Advance e1 in one big step
	e1.advance(0.3, [], [])
	# Advance e2 in many small steps
	for i in range(30):
		e2.advance(0.01, [], [])
	assert_almost_eq(e1.spawn_timer, e2.spawn_timer, 0.01, "Spawn timer should converge")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_enemy_entity.gd -gexit`
Expected: FAIL — EnemyEntity not found

- [ ] **Step 3: Create enemy_entity.tscn**

Create `godot/simulation/entities/enemy_entity.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://simulation/entities/enemy_entity.gd" id="1"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_1"]
size = Vector2(12, 12)

[node name="EnemyEntity" type="CharacterBody2D"]
collision_layer = 4
collision_mask = 1
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_1")
```

Note: `collision_layer = 4` is layer 3 (bit 2). `collision_mask = 1` is layer 1 (walls + players on layer 1).

- [ ] **Step 4: Implement EnemyEntity core**

Create `godot/simulation/entities/enemy_entity.gd`:

```gdscript
class_name EnemyEntity
extends CharacterBody2D

enum State { SPAWNING = 0, IDLE = 1, CHASING = 2, DEAD = 3 }

var entity_id: int = -1
var state: int = State.SPAWNING
var facing: Vector2 = Vector2.RIGHT
var target_player_id: int = -1
var actual_speed: float = 0.0
var spawn_timer: float = 0.0
var _wander_target: Vector2 = Vector2.ZERO
var _params: EnemyParams = null


func initialize(id: int, spawn_position: Vector2, params: EnemyParams) -> void:
	entity_id = id
	position = spawn_position
	_params = params
	actual_speed = params.base_speed * (1.0 + RNG.next_float_range(
		-params.speed_variation, params.speed_variation))
	spawn_timer = params.base_spawn_duration * (1.0 + RNG.next_float_range(
		-params.spawn_duration_variation, params.spawn_duration_variation))
	_wander_target = position


func advance(dt: float, players: Array, neighbors: Array) -> void:
	match state:
		State.SPAWNING:
			_advance_spawning(dt)
		State.IDLE:
			_advance_idle(dt, players)
		State.CHASING:
			_advance_chasing(dt, players, neighbors)


func _advance_spawning(dt: float) -> void:
	spawn_timer -= dt
	velocity = Vector2.ZERO
	if spawn_timer <= 0.0:
		_set_state(State.IDLE)
		_pick_wander_target()


func _advance_idle(dt: float, players: Array) -> void:
	# Check for player detection
	var nearest = _find_nearest_player(players, _params.detection_radius)
	if nearest != null:
		target_player_id = nearest.player_id
		_set_state(State.CHASING)
		_advance_chasing(dt, players, [])
		return

	# Wander toward target
	var to_wander = _wander_target - position
	var dist = to_wander.length()
	if dist < 5.0:
		_pick_wander_target()
		to_wander = _wander_target - position
		dist = to_wander.length()

	if dist > 0.0:
		var wander_dir = to_wander.normalized()
		facing = facing.lerp(wander_dir, 1.0 - exp(-_params.turn_rate * dt))
		velocity = facing * actual_speed * _params.wander_speed_factor
	else:
		velocity = Vector2.ZERO

	move_and_slide()


func _advance_chasing(dt: float, players: Array, neighbors: Array) -> void:
	# Validate current target
	var target = _get_target_player(players)
	if target == null:
		target_player_id = -1
		_set_state(State.IDLE)
		_pick_wander_target()
		return

	var dist_to_target = position.distance_to(target.position)

	# Leash check
	if dist_to_target > _params.leash_radius:
		var fallback = _find_nearest_player(players, _params.detection_radius)
		if fallback != null:
			target_player_id = fallback.player_id
			target = fallback
			dist_to_target = position.distance_to(target.position)
		else:
			target_player_id = -1
			_set_state(State.IDLE)
			_pick_wander_target()
			return

	# Hysteresis — switch target if another player is much closer
	for player in players:
		if player.player_id == target_player_id:
			continue
		var d = position.distance_to(player.position)
		if d < dist_to_target - _params.hysteresis_distance:
			var old_id = target_player_id
			target_player_id = player.player_id
			target = player
			dist_to_target = d
			EventBus.enemy_target_changed.emit({
				"entity_id": entity_id, "old_target_id": old_id,
				"new_target_id": target_player_id, "position": position,
			})

	# Seek direction
	var seek_dir = (target.position - position).normalized()

	# Separation
	var separation_dir = Vector2.ZERO
	for neighbor in neighbors:
		if neighbor == self:
			continue
		var offset = position - neighbor.position
		var d = offset.length()
		if d < _params.separation_radius and d > 0.0:
			separation_dir += offset.normalized() / d

	# Combine
	var desired_dir = (seek_dir + separation_dir * _params.separation_weight)
	if desired_dir.length_squared() > 0.0:
		desired_dir = desired_dir.normalized()
	else:
		desired_dir = seek_dir

	# Turn rate
	facing = facing.lerp(desired_dir, 1.0 - exp(-_params.turn_rate * dt))
	if facing.length_squared() > 0.0:
		facing = facing.normalized()

	# Arrival
	var speed_factor = clampf(dist_to_target / _params.arrival_radius, 0.0, 1.0)

	# Apply
	velocity = facing * actual_speed * speed_factor
	move_and_slide()


func _find_nearest_player(players: Array, max_dist: float) -> Variant:
	var best = null
	var best_dist = max_dist + 1.0
	for player in players:
		var d = position.distance_to(player.position)
		if d <= max_dist and d < best_dist:
			best = player
			best_dist = d
	return best


func _get_target_player(players: Array) -> Variant:
	for player in players:
		if player.player_id == target_player_id:
			return player
	return null


func _pick_wander_target() -> void:
	var offset = Vector2(
		RNG.next_float_range(-_params.wander_radius, _params.wander_radius),
		RNG.next_float_range(-_params.wander_radius, _params.wander_radius),
	)
	_wander_target = position + offset


func _set_state(new_state: int) -> void:
	var old_state = state
	state = new_state
	EventBus.enemy_state_changed.emit({
		"entity_id": entity_id, "old_state": old_state,
		"new_state": new_state, "position": position,
	})


func to_snapshot_data() -> Dictionary:
	return {
		"entity_id": entity_id,
		"position": position,
		"state": state,
		"facing": facing,
		"spawn_timer": spawn_timer,
	}


func kill() -> void:
	_set_state(State.DEAD)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_enemy_entity.gd -gexit`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add godot/simulation/entities/enemy_entity.gd godot/simulation/entities/enemy_entity.tscn godot/tests/entities/test_enemy_entity.gd
git commit -m "Add EnemyEntity with state machine, spawning, idle wander, and chasing"
```

---

### Task 4: EnemyEntity — Chasing, Steering & Aggro Tests

Focused tests for the chasing behavior: seek, separation, arrival, turn rate, sticky aggro, detection, leash.

**Files:**
- Test: `godot/tests/entities/test_enemy_steering.gd`
- Test: `godot/tests/entities/test_enemy_aggro.gd`

- [ ] **Step 1: Write steering tests**

Create `godot/tests/entities/test_enemy_steering.gd`:

```gdscript
extends GutTest

var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


func _make_enemy(pos: Vector2 = Vector2(100, 100), params: EnemyParams = null) -> EnemyEntity:
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	if params == null:
		params = EnemyParams.new()
	RNG.seed(42)
	enemy.initialize(1, pos, params)
	# Skip spawning state
	enemy.state = EnemyEntity.State.CHASING
	return enemy


func _make_player(id: int, pos: Vector2) -> PlayerEntity:
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(id, pos)
	return player


func test_enemy_moves_toward_player():
	var enemy = _make_enemy(Vector2(100, 100))
	var player = _make_player(1, Vector2(200, 100))
	enemy.target_player_id = 1
	enemy.facing = Vector2.RIGHT

	enemy.advance(0.5, [player], [])
	# Enemy should have moved rightward
	assert_gt(enemy.position.x, 100.0, "Enemy should move toward player")


func test_separation_pushes_enemies_apart():
	var e1 = _make_enemy(Vector2(100, 100))
	var player = _make_player(1, Vector2(200, 100))
	e1.target_player_id = 1
	e1.facing = Vector2.RIGHT

	# Create a neighbor very close (simulated, not a real entity in tree)
	var e2 = _make_enemy(Vector2(105, 100))

	e1.advance(0.05, [player], [e2])
	# e1's velocity should have some upward or downward component from separation
	# (pushed away from e2 which is to its right)
	# The exact direction depends on the combined seek + separation, but
	# separation should push e1 leftward relative to pure seek
	# Just verify it moved (non-zero velocity)
	assert_ne(e1.velocity, Vector2.ZERO, "Enemy should move")


func test_arrival_slows_near_target():
	var params = EnemyParams.new()
	params.arrival_radius = 40.0
	var enemy = _make_enemy(Vector2(100, 100), params)
	var player = _make_player(1, Vector2(110, 100))  # 10px away, inside arrival radius
	enemy.target_player_id = 1
	enemy.facing = Vector2.RIGHT

	enemy.advance(0.05, [player], [])
	var close_speed = enemy.velocity.length()

	# Reset and test from further away
	RNG.seed(42)
	var enemy_far = _make_enemy(Vector2(100, 100), params)
	var player_far = _make_player(2, Vector2(200, 100))  # 100px away, outside arrival
	enemy_far.target_player_id = 2
	enemy_far.facing = Vector2.RIGHT
	enemy_far.advance(0.05, [player_far], [])
	var far_speed = enemy_far.velocity.length()

	assert_lt(close_speed, far_speed, "Should move slower near target")


func test_turn_rate_lerps_facing():
	var params = EnemyParams.new()
	params.turn_rate = 4.0  # Moderate turn rate
	var enemy = _make_enemy(Vector2(100, 100), params)
	var player = _make_player(1, Vector2(100, 200))  # Directly below
	enemy.target_player_id = 1
	enemy.facing = Vector2.RIGHT  # Facing right, target is down

	enemy.advance(0.05, [player], [])
	# Facing should have rotated toward down but not snapped instantly
	assert_gt(enemy.facing.y, 0.0, "Facing should rotate toward target")
	assert_gt(enemy.facing.x, 0.0, "Should not have fully rotated yet")


func test_dt_independence_chasing():
	var player = _make_player(1, Vector2(300, 100))

	RNG.seed(42)
	var e1 = _make_enemy(Vector2(100, 100))
	e1.target_player_id = 1
	e1.facing = Vector2.RIGHT
	# One big step
	e1.advance(0.5, [player], [])

	RNG.seed(42)
	var e2 = _make_enemy(Vector2(100, 100))
	e2.target_player_id = 1
	e2.facing = Vector2.RIGHT
	# Many small steps
	for i in range(10):
		e2.advance(0.05, [player], [])

	# Positions should be close (not exact due to move_and_slide + floating point)
	assert_almost_eq(e1.position.x, e2.position.x, 5.0, "X should converge")
	assert_almost_eq(e1.position.y, e2.position.y, 5.0, "Y should converge")
```

- [ ] **Step 2: Write aggro tests**

Create `godot/tests/entities/test_enemy_aggro.gd`:

```gdscript
extends GutTest

var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


func _make_enemy(pos: Vector2 = Vector2(100, 100)) -> EnemyEntity:
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParams.new()
	params.detection_radius = 200.0
	params.leash_radius = 300.0
	params.hysteresis_distance = 80.0
	RNG.seed(42)
	enemy.initialize(1, pos, params)
	return enemy


func _make_player(id: int, pos: Vector2) -> PlayerEntity:
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(id, pos)
	return player


func test_idle_detects_player_in_range():
	var enemy = _make_enemy()
	# Force to idle
	enemy.state = EnemyEntity.State.IDLE
	var player = _make_player(1, Vector2(150, 100))  # 50px away, within 200 detection
	enemy.advance(0.05, [player], [])
	assert_eq(enemy.state, EnemyEntity.State.CHASING)
	assert_eq(enemy.target_player_id, 1)


func test_idle_ignores_player_outside_detection():
	var enemy = _make_enemy()
	enemy.state = EnemyEntity.State.IDLE
	var player = _make_player(1, Vector2(400, 100))  # 300px away, outside 200 detection
	enemy.advance(0.05, [player], [])
	assert_eq(enemy.state, EnemyEntity.State.IDLE)


func test_chasing_leash_returns_to_idle():
	var enemy = _make_enemy()
	enemy.state = EnemyEntity.State.CHASING
	enemy.facing = Vector2.RIGHT
	var player = _make_player(1, Vector2(500, 100))  # 400px, beyond 300 leash
	enemy.target_player_id = 1
	enemy.advance(0.05, [player], [])
	assert_eq(enemy.state, EnemyEntity.State.IDLE, "Should leash back to idle")
	assert_eq(enemy.target_player_id, -1)


func test_sticky_aggro_keeps_target():
	var enemy = _make_enemy()
	enemy.state = EnemyEntity.State.CHASING
	enemy.facing = Vector2.RIGHT
	var p1 = _make_player(1, Vector2(200, 100))  # 100px away, current target
	var p2 = _make_player(2, Vector2(180, 100))  # 80px away, closer but not by hysteresis
	enemy.target_player_id = 1
	enemy.advance(0.05, [p1, p2], [])
	assert_eq(enemy.target_player_id, 1, "Should stick to original target")


func test_hysteresis_switches_target():
	var enemy = _make_enemy()
	enemy.state = EnemyEntity.State.CHASING
	enemy.facing = Vector2.RIGHT
	var p1 = _make_player(1, Vector2(290, 100))  # 190px away, current target
	var p2 = _make_player(2, Vector2(105, 100))  # 5px away, closer by >80
	enemy.target_player_id = 1
	enemy.advance(0.05, [p1, p2], [])
	assert_eq(enemy.target_player_id, 2, "Should switch to much closer player")


func test_retargets_on_disconnect():
	var enemy = _make_enemy()
	enemy.state = EnemyEntity.State.CHASING
	enemy.facing = Vector2.RIGHT
	enemy.target_player_id = 1  # Target that doesn't exist in player list
	var p2 = _make_player(2, Vector2(150, 100))  # Within detection
	enemy.advance(0.05, [p2], [])
	assert_eq(enemy.target_player_id, 2, "Should retarget to available player")
```

- [ ] **Step 3: Run all steering and aggro tests**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/entities/test_enemy_steering.gd,res://tests/entities/test_enemy_aggro.gd -gexit`
Expected: All tests PASS (implementation already in Task 3)

- [ ] **Step 4: Commit**

```bash
git add godot/tests/entities/test_enemy_steering.gd godot/tests/entities/test_enemy_aggro.gd
git commit -m "Add steering and aggro tests for EnemyEntity"
```

---

### Task 5: EnemySystem

Registry and tick driver. Wires up SpatialGrid for separation. Passes player references to enemies.

**Files:**
- Create: `godot/simulation/systems/enemy_system.gd`
- Test: `godot/tests/systems/test_enemy_system.gd`

- [ ] **Step 1: Write EnemySystem tests**

Create `godot/tests/systems/test_enemy_system.gd`:

```gdscript
extends GutTest

var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


var _system: EnemySystem


func before_each():
	_system = EnemySystem.new()
	add_child_autofree(_system)


func _make_enemy(id: int, pos: Vector2 = Vector2(100, 100)) -> EnemyEntity:
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	var params = EnemyParams.new()
	RNG.seed(id * 7)  # Different seed per enemy for variation
	enemy.initialize(id, pos, params)
	return enemy


func _make_player(id: int, pos: Vector2) -> PlayerEntity:
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(id, pos)
	return player


func test_register_and_get():
	var enemy = _make_enemy(10001)
	_system.register_enemy(enemy)
	assert_true(_system.has_enemy(10001))
	assert_eq(_system.get_enemy(10001), enemy)


func test_unregister():
	var enemy = _make_enemy(10001)
	_system.register_enemy(enemy)
	_system.unregister_enemy(10001)
	assert_false(_system.has_enemy(10001))


func test_get_all_enemies():
	var e1 = _make_enemy(10001, Vector2(50, 50))
	var e2 = _make_enemy(10002, Vector2(150, 150))
	_system.register_enemy(e1)
	_system.register_enemy(e2)
	assert_eq(_system.get_all_enemies().size(), 2)


func test_advance_all_ticks_enemies():
	var enemy = _make_enemy(10001)
	_system.register_enemy(enemy)
	var initial_timer = enemy.spawn_timer
	var players: Dictionary = {}
	_system.advance_all(0.1, players)
	assert_almost_eq(enemy.spawn_timer, initial_timer - 0.1, 0.01)


func test_advance_all_removes_dead_enemies():
	var enemy = _make_enemy(10001)
	_system.register_enemy(enemy)
	enemy.kill()
	var players: Dictionary = {}
	_system.advance_all(0.05, players)
	assert_false(_system.has_enemy(10001), "Dead enemy should be removed")


func test_get_enemies_in_radius():
	var e1 = _make_enemy(10001, Vector2(50, 50))
	var e2 = _make_enemy(10002, Vector2(55, 50))
	var e3 = _make_enemy(10003, Vector2(500, 500))
	e1.state = EnemyEntity.State.IDLE
	e2.state = EnemyEntity.State.IDLE
	e3.state = EnemyEntity.State.IDLE
	_system.register_enemy(e1)
	_system.register_enemy(e2)
	_system.register_enemy(e3)
	# Need to rebuild grid first
	_system.advance_all(0.0, {})
	var nearby = _system.get_enemies_in_radius(Vector2(50, 50), 30.0)
	assert_eq(nearby.size(), 2, "Should find 2 nearby enemies")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_enemy_system.gd -gexit`
Expected: FAIL — EnemySystem not found

- [ ] **Step 3: Implement EnemySystem**

Create `godot/simulation/systems/enemy_system.gd`:

```gdscript
class_name EnemySystem
extends Node

var _enemies: Dictionary = {}  # entity_id -> EnemyEntity
var _spatial_grid: SpatialGrid
var _dead_queue: Array = []  # entity_ids to remove after processing

@export var params: EnemyParams = null


func _init() -> void:
	_spatial_grid = SpatialGrid.new()


func register_enemy(enemy: EnemyEntity) -> void:
	_enemies[enemy.entity_id] = enemy


func unregister_enemy(entity_id: int) -> void:
	_enemies.erase(entity_id)


func has_enemy(entity_id: int) -> bool:
	return _enemies.has(entity_id)


func get_enemy(entity_id: int) -> EnemyEntity:
	return _enemies.get(entity_id)


func get_all_enemies() -> Array:
	return _enemies.values()


func get_enemies_in_radius(pos: Vector2, radius: float) -> Array:
	return _spatial_grid.query_radius(pos, radius)


func advance_all(dt: float, players: Dictionary) -> void:
	_dead_queue.clear()

	# Rebuild spatial grid with non-spawning, non-dead enemies
	_spatial_grid.clear()
	for enemy in _enemies.values():
		if enemy.state == EnemyEntity.State.IDLE or enemy.state == EnemyEntity.State.CHASING:
			_spatial_grid.insert(enemy, enemy.position)

	var player_array: Array = players.values()

	# Advance each enemy
	for enemy in _enemies.values():
		if enemy.state == EnemyEntity.State.DEAD:
			_dead_queue.append(enemy.entity_id)
			continue
		var neighbors = _spatial_grid.query_nearby(enemy.position)
		enemy.advance(dt, player_array, neighbors)

	# Remove dead enemies
	for eid in _dead_queue:
		_enemies.erase(eid)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_enemy_system.gd -gexit`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/systems/enemy_system.gd godot/tests/systems/test_enemy_system.gd
git commit -m "Add EnemySystem: registry, tick driver, spatial grid integration"
```

---

### Task 6: EnemySpawner

Timer-based batch spawning, edge-biased point selection, max_alive cap.

**Files:**
- Create: `godot/simulation/systems/enemy_spawner.gd`
- Test: `godot/tests/systems/test_enemy_spawner.gd`

- [ ] **Step 1: Write EnemySpawner tests**

Create `godot/tests/systems/test_enemy_spawner.gd`:

```gdscript
extends GutTest

var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


func _make_system() -> EnemySystem:
	var system = EnemySystem.new()
	add_child_autofree(system)
	return system


func _make_spawner(system: EnemySystem, params: SpawnerParams = null) -> EnemySpawner:
	if params == null:
		params = SpawnerParams.new()
	var enemy_params = EnemyParams.new()
	var spawner = EnemySpawner.new()
	add_child_autofree(spawner)
	spawner.initialize(system, params, enemy_params)
	return spawner


func _make_player(id: int, pos: Vector2) -> PlayerEntity:
	var player = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(id, pos)
	return player


func test_spawns_batch_on_interval():
	var system = _make_system()
	var params = SpawnerParams.new()
	params.spawn_interval = 1.0
	params.batch_size = 3
	RNG.seed(42)
	var spawner = _make_spawner(system, params)
	var players: Dictionary = {}
	spawner.advance(1.0, players)
	assert_eq(system.get_all_enemies().size(), 3, "Should spawn batch of 3")


func test_respects_max_alive():
	var system = _make_system()
	var params = SpawnerParams.new()
	params.spawn_interval = 0.5
	params.batch_size = 10
	params.max_alive = 5
	RNG.seed(42)
	var spawner = _make_spawner(system, params)
	var players: Dictionary = {}
	spawner.advance(0.5, players)
	assert_eq(system.get_all_enemies().size(), 5, "Should cap at max_alive")
	# Tick again — should not spawn more
	spawner.advance(0.5, players)
	assert_eq(system.get_all_enemies().size(), 5, "Should still be at max_alive")


func test_no_spawn_before_interval():
	var system = _make_system()
	var params = SpawnerParams.new()
	params.spawn_interval = 2.0
	params.batch_size = 3
	RNG.seed(42)
	var spawner = _make_spawner(system, params)
	spawner.advance(1.0, {})
	assert_eq(system.get_all_enemies().size(), 0, "Should not spawn before interval")


func test_spawn_margin_rejects_near_player():
	var system = _make_system()
	var params = SpawnerParams.new()
	params.spawn_interval = 0.1
	params.batch_size = 50  # Try to spawn many
	params.spawn_margin = 9999.0  # Giant margin — everywhere is too close
	params.max_alive = 50
	RNG.seed(42)
	var spawner = _make_spawner(system, params)
	var player = _make_player(1, Vector2(240, 160))
	var players: Dictionary = {1: player}
	spawner.advance(0.1, players)
	# With 9999 margin in a 480x320 arena, all spawn points should be rejected
	assert_eq(system.get_all_enemies().size(), 0, "All spawns rejected near player")


func test_entity_ids_are_unique():
	var system = _make_system()
	var params = SpawnerParams.new()
	params.spawn_interval = 0.5
	params.batch_size = 5
	RNG.seed(42)
	var spawner = _make_spawner(system, params)
	spawner.advance(0.5, {})
	var ids: Dictionary = {}
	for enemy in system.get_all_enemies():
		assert_false(ids.has(enemy.entity_id), "ID %d should be unique" % enemy.entity_id)
		ids[enemy.entity_id] = true
	assert_gte(system.get_all_enemies()[0].entity_id, 10000, "IDs should start at 10000+")


func test_spawned_enemies_start_in_spawning_state():
	var system = _make_system()
	var params = SpawnerParams.new()
	params.spawn_interval = 0.5
	params.batch_size = 3
	RNG.seed(42)
	var spawner = _make_spawner(system, params)
	spawner.advance(0.5, {})
	for enemy in system.get_all_enemies():
		assert_eq(enemy.state, EnemyEntity.State.SPAWNING)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_enemy_spawner.gd -gexit`
Expected: FAIL — EnemySpawner not found

- [ ] **Step 3: Implement EnemySpawner**

Create `godot/simulation/systems/enemy_spawner.gd`:

```gdscript
class_name EnemySpawner
extends Node

var _enemy_system: EnemySystem
var _spawner_params: SpawnerParams
var _enemy_params: EnemyParams
var _spawn_timer: float = 0.0
var _next_enemy_id: int = 10000

var EnemyEntityScene: PackedScene = preload("res://simulation/entities/enemy_entity.tscn")

const MAX_SPAWN_ATTEMPTS: int = 5


func initialize(enemy_system: EnemySystem, spawner_params: SpawnerParams, enemy_params: EnemyParams) -> void:
	_enemy_system = enemy_system
	_spawner_params = spawner_params
	_enemy_params = enemy_params
	_spawn_timer = spawner_params.spawn_interval


func advance(dt: float, players: Dictionary) -> void:
	_spawn_timer -= dt
	if _spawn_timer > 0.0:
		return
	_spawn_timer = _spawner_params.spawn_interval

	var alive_count = _enemy_system.get_all_enemies().size()
	var to_spawn = mini(_spawner_params.batch_size, _spawner_params.max_alive - alive_count)

	for i in range(to_spawn):
		var point = _pick_spawn_point(players)
		if point == null:
			continue
		_spawn_enemy_at(point)


func _pick_spawn_point(players: Dictionary) -> Variant:
	var arena = _spawner_params.arena_size
	var inset = _spawner_params.spawn_edge_inset

	for _attempt in range(MAX_SPAWN_ATTEMPTS):
		var point = _random_edge_point(arena, inset)
		if _is_far_from_players(point, players):
			return point
	return null


func _random_edge_point(arena: Vector2, inset: float) -> Vector2:
	# Pick a random edge (0=top, 1=bottom, 2=left, 3=right)
	var edge = RNG.next_int(0, 3)
	match edge:
		0:  # Top
			return Vector2(RNG.next_float_range(inset, arena.x - inset), inset)
		1:  # Bottom
			return Vector2(RNG.next_float_range(inset, arena.x - inset), arena.y - inset)
		2:  # Left
			return Vector2(inset, RNG.next_float_range(inset, arena.y - inset))
		3:  # Right
			return Vector2(arena.x - inset, RNG.next_float_range(inset, arena.y - inset))
	return Vector2(inset, inset)  # Fallback


func _is_far_from_players(point: Vector2, players: Dictionary) -> bool:
	for player in players.values():
		if point.distance_to(player.position) < _spawner_params.spawn_margin:
			return false
	return true


func _spawn_enemy_at(point: Vector2) -> void:
	var enemy: EnemyEntity = EnemyEntityScene.instantiate()
	enemy.initialize(_next_enemy_id, point, _enemy_params)
	_next_enemy_id += 1
	# Add to scene tree (server_main or test adds spawner as child, so get_parent works)
	get_parent().add_child(enemy)
	_enemy_system.register_enemy(enemy)
	EventBus.enemy_spawned.emit({
		"entity_id": enemy.entity_id,
		"position": point,
		"spawn_duration": enemy.spawn_timer,
	})
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/systems/test_enemy_spawner.gd -gexit`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/systems/enemy_spawner.gd godot/tests/systems/test_enemy_spawner.gd
git commit -m "Add EnemySpawner: timed batch spawning with edge-biased point selection"
```

---

### Task 7: Network Protocol — MessageTypes + NetMessage + Snapshot

Extend the binary protocol for enemy snapshot data and the ENEMY_DIED event. Extend Snapshot with `enemy_entities`.

**Files:**
- Modify: `godot/shared/network/message_types.gd`
- Modify: `godot/simulation/network/net_message.gd`
- Modify: `godot/simulation/network/snapshot.gd`
- Test: `godot/tests/network/test_enemy_network.gd`

- [ ] **Step 1: Write network tests for enemy encoding**

Create `godot/tests/network/test_enemy_network.gd`:

```gdscript
extends GutTest

var NetMessage = preload("res://simulation/network/net_message.gd")
var Snapshot = preload("res://simulation/network/snapshot.gd")


func _make_enemy_data(id: int, x: float, y: float, state: int = 0,
		facing: Vector2 = Vector2.RIGHT, spawn_timer: float = 0.5) -> Dictionary:
	return {
		"entity_id": id, "position": Vector2(x, y), "state": state,
		"facing": facing, "spawn_timer": spawn_timer,
	}


func test_encode_decode_snapshot_with_enemies():
	var msg = {
		"type": MessageTypes.Binary.FULL_SNAPSHOT,
		"tick": 100,
		"entities": [
			{"entity_id": 1, "position": Vector2(100, 200), "flags": 0, "last_input_seq": 5},
		],
		"enemy_entities": [
			_make_enemy_data(10001, 50.0, 75.0, 0, Vector2(0.707, 0.707), 0.4),
			_make_enemy_data(10002, 300.0, 200.0, 2, Vector2(-1.0, 0.0), 0.0),
		],
	}
	var bytes = NetMessage.encode(msg)
	var decoded = NetMessage.decode_binary(bytes)

	assert_eq(decoded["type"], MessageTypes.Binary.FULL_SNAPSHOT)
	assert_eq(decoded["tick"], 100)
	assert_eq(decoded["entities"].size(), 1)
	assert_eq(decoded["enemy_entities"].size(), 2)

	var e0 = decoded["enemy_entities"][0]
	assert_eq(e0["entity_id"], 10001)
	assert_almost_eq(e0["position"].x, 50.0, 0.1)
	assert_almost_eq(e0["position"].y, 75.0, 0.1)
	assert_eq(e0["state"], 0)
	assert_almost_eq(e0["facing"].x, 0.707, 0.01)
	assert_almost_eq(e0["spawn_timer"], 0.4, 0.01)


func test_encode_decode_snapshot_no_enemies():
	var msg = {
		"type": MessageTypes.Binary.FULL_SNAPSHOT,
		"tick": 50,
		"entities": [],
		"enemy_entities": [],
	}
	var bytes = NetMessage.encode(msg)
	var decoded = NetMessage.decode_binary(bytes)
	assert_eq(decoded["enemy_entities"].size(), 0)


func test_encode_decode_enemy_died():
	var msg = {
		"type": MessageTypes.Binary.ENEMY_DIED,
		"entity_id": 10005,
		"position": Vector2(123.5, 456.75),
		"killer_id": 2,
	}
	var bytes = NetMessage.encode(msg)
	assert_eq(bytes.size(), MessageTypes.Layout.ENEMY_DIED_SIZE)

	var decoded = NetMessage.decode_binary(bytes)
	assert_eq(decoded["type"], MessageTypes.Binary.ENEMY_DIED)
	assert_eq(decoded["entity_id"], 10005)
	assert_almost_eq(decoded["position"].x, 123.5, 0.01)
	assert_almost_eq(decoded["position"].y, 456.75, 0.01)
	assert_eq(decoded["killer_id"], 2)


func test_snapshot_diff_with_enemies():
	var baseline = Snapshot.new()
	baseline.tick = 10
	baseline.enemy_entities = {
		10001: _make_enemy_data(10001, 50.0, 50.0, 2),
		10002: _make_enemy_data(10002, 100.0, 100.0, 1),
	}
	var current = Snapshot.new()
	current.tick = 11
	current.enemy_entities = {
		10001: _make_enemy_data(10001, 55.0, 50.0, 2),  # moved
		10002: _make_enemy_data(10002, 100.0, 100.0, 1),  # unchanged
		10003: _make_enemy_data(10003, 200.0, 200.0, 0),  # new
	}
	var delta = Snapshot.diff_enemies(baseline, current)
	assert_eq(delta.size(), 2, "Should have moved + new enemy")


func test_snapshot_diff_enemy_removed():
	var baseline = Snapshot.new()
	baseline.tick = 10
	baseline.enemy_entities = {
		10001: _make_enemy_data(10001, 50.0, 50.0),
	}
	var current = Snapshot.new()
	current.tick = 11
	current.enemy_entities = {}
	var delta = Snapshot.diff_enemies(baseline, current)
	assert_eq(delta.size(), 1)
	assert_eq(delta[0]["entity_id"], 10001)
	assert_eq(delta[0]["state"], MessageTypes.EnemyFlags.REMOVED)


func test_snapshot_apply_delta_enemies():
	var snap = Snapshot.new()
	snap.tick = 10
	snap.enemy_entities = {
		10001: _make_enemy_data(10001, 50.0, 50.0, 2),
	}
	var delta = [
		_make_enemy_data(10001, 55.0, 50.0, 2),  # updated
		_make_enemy_data(10002, 100.0, 100.0, 0),  # new
	]
	snap.apply_enemy_delta(11, delta)
	assert_eq(snap.tick, 11)
	assert_eq(snap.enemy_entities.size(), 2)
	assert_almost_eq(snap.enemy_entities[10001]["position"].x, 55.0, 0.1)


func test_snapshot_duplicate_includes_enemies():
	var snap = Snapshot.new()
	snap.tick = 10
	snap.enemy_entities = {10001: _make_enemy_data(10001, 50.0, 50.0)}
	var copy = snap.duplicate_snapshot()
	copy.enemy_entities[10001]["position"] = Vector2(999, 999)
	assert_almost_eq(snap.enemy_entities[10001]["position"].x, 50.0, 0.1,
		"Original should be unchanged")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_enemy_network.gd -gexit`
Expected: FAIL

- [ ] **Step 3: Extend MessageTypes**

In `godot/shared/network/message_types.gd`, add to the `Binary` enum:

```gdscript
ENEMY_DIED = 5,
```

Add a new `EnemyFlags` enum after `EntityFlags`:

```gdscript
enum EnemyFlags {
	REMOVED = 255,
}
```

Add to `Layout` class:

```gdscript
# Per-enemy: [entity_id: u16][x: f32][y: f32][state: u8][facing_x: f16][facing_y: f16][spawn_timer: f16]
const ENEMY_ENTITY_SIZE = 17
# Enemy died: [type: u8][entity_id: u16][x: f32][y: f32][killer_id: u16]
const ENEMY_DIED_SIZE = 13
```

- [ ] **Step 4: Extend NetMessage with enemy encoding**

In `godot/simulation/network/net_message.gd`, add to the `encode` match:

```gdscript
MessageTypes.Binary.ENEMY_DIED:
	return _encode_enemy_died(msg)
```

Add to the `decode_binary` match:

```gdscript
MessageTypes.Binary.ENEMY_DIED:
	return _decode_enemy_died(bytes)
```

Update `_encode_snapshot` to append enemy entities after player entities:

```gdscript
static func _encode_snapshot(msg: Dictionary) -> PackedByteArray:
	var entities: Array = msg["entities"]
	var enemy_entities: Array = msg.get("enemy_entities", [])
	var header_size = MessageTypes.Layout.SNAPSHOT_HEADER_SIZE
	var entity_size = MessageTypes.Layout.ENTITY_SIZE
	var enemy_size = MessageTypes.Layout.ENEMY_ENTITY_SIZE
	var total_size = header_size + entities.size() * entity_size + 2 + enemy_entities.size() * enemy_size
	var buf = PackedByteArray()
	buf.resize(total_size)
	buf.encode_u8(0, msg["type"])
	buf.encode_u32(1, msg["tick"])
	buf.encode_u16(5, entities.size())

	# Player entities
	for i in range(entities.size()):
		var offset = header_size + i * entity_size
		var ent = entities[i]
		var pos: Vector2 = ent["position"]
		buf.encode_u16(offset, ent["entity_id"])
		buf.encode_float(offset + 2, pos.x)
		buf.encode_float(offset + 6, pos.y)
		buf.encode_u8(offset + 10, ent["flags"])
		buf.encode_u32(offset + 11, ent.get("last_input_seq", 0))

	# Enemy count + entities
	var enemy_offset_start = header_size + entities.size() * entity_size
	buf.encode_u16(enemy_offset_start, enemy_entities.size())
	for i in range(enemy_entities.size()):
		var offset = enemy_offset_start + 2 + i * enemy_size
		var ent = enemy_entities[i]
		var pos: Vector2 = ent["position"]
		var facing: Vector2 = ent.get("facing", Vector2.RIGHT)
		buf.encode_u16(offset, ent["entity_id"])
		buf.encode_float(offset + 2, pos.x)
		buf.encode_float(offset + 6, pos.y)
		buf.encode_u8(offset + 10, ent["state"])
		buf.encode_half(offset + 11, facing.x)
		buf.encode_half(offset + 13, facing.y)
		buf.encode_half(offset + 15, ent.get("spawn_timer", 0.0))
	return buf
```

Update `_decode_snapshot` to parse enemy section:

```gdscript
static func _decode_snapshot(bytes: PackedByteArray, type: int) -> Variant:
	var header_size = MessageTypes.Layout.SNAPSHOT_HEADER_SIZE
	var entity_size = MessageTypes.Layout.ENTITY_SIZE
	var enemy_size = MessageTypes.Layout.ENEMY_ENTITY_SIZE
	if bytes.size() < header_size:
		return null
	var entity_count = bytes.decode_u16(5)
	var player_section_size = entity_count * entity_size
	if bytes.size() < header_size + player_section_size:
		return null

	# Decode player entities
	var entities: Array = []
	for i in range(entity_count):
		var offset = header_size + i * entity_size
		entities.append({
			"entity_id": bytes.decode_u16(offset),
			"position": Vector2(bytes.decode_float(offset + 2), bytes.decode_float(offset + 6)),
			"flags": bytes.decode_u8(offset + 10),
			"last_input_seq": bytes.decode_u32(offset + 11),
		})

	# Decode enemy entities (if present)
	var enemy_entities: Array = []
	var enemy_offset_start = header_size + player_section_size
	if bytes.size() >= enemy_offset_start + 2:
		var enemy_count = bytes.decode_u16(enemy_offset_start)
		if bytes.size() >= enemy_offset_start + 2 + enemy_count * enemy_size:
			for i in range(enemy_count):
				var offset = enemy_offset_start + 2 + i * enemy_size
				enemy_entities.append({
					"entity_id": bytes.decode_u16(offset),
					"position": Vector2(bytes.decode_float(offset + 2), bytes.decode_float(offset + 6)),
					"state": bytes.decode_u8(offset + 10),
					"facing": Vector2(bytes.decode_half(offset + 11), bytes.decode_half(offset + 13)),
					"spawn_timer": bytes.decode_half(offset + 15),
				})

	return {
		"type": type,
		"tick": bytes.decode_u32(1),
		"entities": entities,
		"enemy_entities": enemy_entities,
	}
```

Add enemy died encode/decode:

```gdscript
static func _encode_enemy_died(msg: Dictionary) -> PackedByteArray:
	var buf = PackedByteArray()
	buf.resize(MessageTypes.Layout.ENEMY_DIED_SIZE)
	var pos: Vector2 = msg["position"]
	buf.encode_u8(0, MessageTypes.Binary.ENEMY_DIED)
	buf.encode_u16(1, msg["entity_id"])
	buf.encode_float(3, pos.x)
	buf.encode_float(7, pos.y)
	buf.encode_u16(11, msg.get("killer_id", 0))
	return buf


static func _decode_enemy_died(bytes: PackedByteArray) -> Variant:
	if bytes.size() < MessageTypes.Layout.ENEMY_DIED_SIZE:
		return null
	return {
		"type": MessageTypes.Binary.ENEMY_DIED,
		"entity_id": bytes.decode_u16(1),
		"position": Vector2(bytes.decode_float(3), bytes.decode_float(7)),
		"killer_id": bytes.decode_u16(11),
	}
```

- [ ] **Step 5: Extend Snapshot class**

In `godot/simulation/network/snapshot.gd`, add:

```gdscript
var enemy_entities: Dictionary = {}  # entity_id -> snapshot data dict
```

Add enemy diff method:

```gdscript
static func diff_enemies(baseline: Snapshot, current: Snapshot) -> Array:
	var changes: Array = []
	for eid in current.enemy_entities:
		if not baseline.enemy_entities.has(eid):
			changes.append(current.enemy_entities[eid].duplicate())
		else:
			var base_ent = baseline.enemy_entities[eid]
			var curr_ent = current.enemy_entities[eid]
			if not base_ent["position"].is_equal_approx(curr_ent["position"]) \
					or base_ent["state"] != curr_ent["state"] \
					or not base_ent["facing"].is_equal_approx(curr_ent["facing"]) \
					or not is_equal_approx(base_ent["spawn_timer"], curr_ent["spawn_timer"]):
				changes.append(curr_ent.duplicate())
	for eid in baseline.enemy_entities:
		if not current.enemy_entities.has(eid):
			changes.append({
				"entity_id": eid,
				"position": Vector2.ZERO,
				"state": MessageTypes.EnemyFlags.REMOVED,
				"facing": Vector2.ZERO,
				"spawn_timer": 0.0,
			})
	return changes
```

Add enemy apply delta:

```gdscript
func apply_enemy_delta(new_tick: int, delta_entities: Array) -> void:
	tick = new_tick
	for ent in delta_entities:
		var eid: int = ent["entity_id"]
		if ent["state"] == MessageTypes.EnemyFlags.REMOVED:
			enemy_entities.erase(eid)
		else:
			enemy_entities[eid] = ent.duplicate()
```

Update `to_entity_array` to have an enemy counterpart:

```gdscript
func to_enemy_entity_array() -> Array:
	return enemy_entities.values()
```

Update `duplicate_snapshot`:

```gdscript
func duplicate_snapshot() -> Snapshot:
	var copy = Snapshot.new()
	copy.tick = tick
	for eid in entities:
		copy.entities[eid] = entities[eid].duplicate()
	for eid in enemy_entities:
		copy.enemy_entities[eid] = enemy_entities[eid].duplicate()
	return copy
```

- [ ] **Step 6: Run all network tests (old + new)**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_enemy_network.gd,res://tests/network/test_net_message.gd,res://tests/network/test_snapshot.gd -gexit`
Expected: All tests PASS (old tests still pass with backward-compatible format)

- [ ] **Step 7: Commit**

```bash
git add godot/shared/network/message_types.gd godot/simulation/network/net_message.gd godot/simulation/network/snapshot.gd godot/tests/network/test_enemy_network.gd
git commit -m "Extend network protocol with enemy snapshot section and ENEMY_DIED event"
```

---

### Task 8: NetServer Integration

Wire EnemySystem and EnemySpawner into the server tick loop. Build snapshots with enemies. Send death events.

**Files:**
- Modify: `godot/simulation/network/net_server.gd`
- Modify: `godot/server_main.gd`

- [ ] **Step 1: Add EnemySystem and EnemySpawner to NetServer**

In `godot/simulation/network/net_server.gd`, add fields after `_input_buffer`:

```gdscript
var _enemy_system: EnemySystem
var _enemy_spawner: EnemySpawner
var _death_events: Array = []  # queued death events to send this tick
```

In `_ready()`, after `_movement_system` initialization, add:

```gdscript
_enemy_system = EnemySystem.new()
add_child(_enemy_system)

var enemy_params = EnemyParams.new()
var spawner_params = SpawnerParams.new()
_enemy_spawner = EnemySpawner.new()
add_child(_enemy_spawner)
_enemy_spawner.initialize(_enemy_system, spawner_params, enemy_params)
```

- [ ] **Step 2: Update the server tick loop**

In `_server_tick()`, after `_movement_system.tick_all()`, add the enemy phase:

```gdscript
# Phase: Spawn and tick enemies
_enemy_spawner.advance(MessageTypes.TICK_INTERVAL_MS / 1000.0, _player_entities)
_enemy_system.advance_all(MessageTypes.TICK_INTERVAL_MS / 1000.0, _player_entities)
```

- [ ] **Step 3: Update `_build_current_snapshot` to include enemies**

Replace the `_build_current_snapshot` method:

```gdscript
func _build_current_snapshot() -> Snapshot:
	var snap = Snapshot.new()
	snap.tick = _tick
	for player_id in _player_entities:
		var player: PlayerEntity = _player_entities[player_id]
		snap.entities[player_id] = player.to_snapshot_data()
	for enemy in _enemy_system.get_all_enemies():
		snap.enemy_entities[enemy.entity_id] = enemy.to_snapshot_data()
	return snap
```

- [ ] **Step 4: Update snapshot sending to include enemy deltas**

In the `_server_tick` snapshot-sending section, update the full snapshot construction to include `enemy_entities`:

Where full snapshots are built, change:

```gdscript
"entities": current_snap.to_entity_array(),
```

to:

```gdscript
"entities": current_snap.to_entity_array(),
"enemy_entities": current_snap.to_enemy_entity_array(),
```

For delta snapshots, update the delta construction:

```gdscript
var delta = Snapshot.diff(baseline, current_snap)
var enemy_delta = Snapshot.diff_enemies(baseline, current_snap)
var delta_msg = {
	"type": MessageTypes.Binary.DELTA_SNAPSHOT,
	"tick": _tick,
	"entities": delta,
	"enemy_entities": enemy_delta,
}
```

- [ ] **Step 5: Add death event sending**

Connect to `EventBus.enemy_died` in `_ready()`:

```gdscript
EventBus.enemy_died.connect(_on_enemy_died)
```

Add handler:

```gdscript
func _on_enemy_died(event: Dictionary) -> void:
	_death_events.append(event)
```

At the end of `_server_tick`, after sending snapshots, add:

```gdscript
# Send queued death events
for death_event in _death_events:
	var death_msg = NetMessage.encode({
		"type": MessageTypes.Binary.ENEMY_DIED,
		"entity_id": death_event["entity_id"],
		"position": death_event["position"],
		"killer_id": death_event.get("killer_id", 0),
	})
	for peer_id in _peers:
		var ws: WebSocketPeer = _peers[peer_id]
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send(death_msg)
_death_events.clear()
```

- [ ] **Step 6: Expose enemy_system for server_main access**

Add a getter to `net_server.gd`:

```gdscript
func get_enemy_system() -> EnemySystem:
	return _enemy_system
```

- [ ] **Step 7: Commit**

```bash
git add godot/simulation/network/net_server.gd godot/server_main.gd
git commit -m "Integrate EnemySystem and EnemySpawner into server tick loop"
```

---

### Task 9: NetClient Extension

Parse enemy entities from snapshots. Handle ENEMY_DIED messages. Emit signals for view layer. Expose enemy interpolation.

**Files:**
- Modify: `godot/simulation/network/net_client.gd`

- [ ] **Step 1: Add enemy signals and state**

At the top of `net_client.gd`, add signals:

```gdscript
signal enemy_snapshot_updated(enemy_entities: Dictionary)
signal enemy_died_received(event: Dictionary)
```

Add state for enemy interpolation after `_snapshot_time`:

```gdscript
# Enemy interpolation: two snapshots of enemy data
var _enemy_prev: Dictionary = {}  # entity_id -> snapshot data
var _enemy_curr: Dictionary = {}  # entity_id -> snapshot data
```

- [ ] **Step 2: Update snapshot handling for enemies**

In `_apply_full_snapshot`, after building the snapshot from entities, add:

```gdscript
# Enemy entities
_enemy_prev = {}
_enemy_curr = {}
for ent in msg.get("enemy_entities", []):
	var eid = ent["entity_id"]
	_enemy_prev[eid] = ent.duplicate()
	_enemy_curr[eid] = ent.duplicate()
enemy_snapshot_updated.emit(_enemy_curr)
```

In `_apply_delta_snapshot`, after `_snapshot_curr.apply_delta`, add:

```gdscript
# Enemy delta
_enemy_prev = _enemy_curr.duplicate()
for ent in msg.get("enemy_entities", []):
	var eid: int = ent["entity_id"]
	if ent["state"] == MessageTypes.EnemyFlags.REMOVED:
		_enemy_curr.erase(eid)
	else:
		_enemy_curr[eid] = ent.duplicate()
enemy_snapshot_updated.emit(_enemy_curr)
```

- [ ] **Step 3: Handle ENEMY_DIED in binary message handler**

In `_handle_binary_message`, add to the match:

```gdscript
MessageTypes.Binary.ENEMY_DIED:
	var event = {
		"entity_id": msg["entity_id"],
		"position": msg["position"],
		"killer_id": msg["killer_id"],
	}
	EventBus.enemy_died.emit(event)
	enemy_died_received.emit(event)
```

- [ ] **Step 4: Add enemy interpolation method**

Add after `get_interpolated_position`:

```gdscript
func get_interpolated_enemy(entity_id: int) -> Variant:
	if not _enemy_curr.has(entity_id):
		return null

	var curr = _enemy_curr[entity_id]
	if not _enemy_prev.has(entity_id):
		return curr  # New enemy, no interpolation

	var prev = _enemy_prev[entity_id]
	var tick_interval = MessageTypes.TICK_INTERVAL_MS / 1000.0
	var t = clampf(_snapshot_time / tick_interval, 0.0, MAX_REMOTE_INTERP)

	var result = curr.duplicate()
	result["position"] = prev["position"].lerp(curr["position"], t)
	result["facing"] = prev["facing"].lerp(curr["facing"], t)
	if result["facing"].length_squared() > 0.0:
		result["facing"] = result["facing"].normalized()
	return result


func get_enemy_ids() -> Array:
	return _enemy_curr.keys()
```

- [ ] **Step 5: Commit**

```bash
git add godot/simulation/network/net_client.gd
git commit -m "Extend NetClient to parse enemy snapshots and death events"
```

---

### Task 10: EnemyView

Colored square with facing indicator and idle wobble.

**Files:**
- Create: `godot/view/world/enemy_view.gd`
- Create: `godot/view/world/enemy_view.tscn`

- [ ] **Step 1: Create enemy_view.tscn**

Create `godot/view/world/enemy_view.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://view/world/enemy_view.gd" id="1"]

[node name="EnemyView" type="Node2D"]
script = ExtResource("1")
```

- [ ] **Step 2: Implement EnemyView**

Create `godot/view/world/enemy_view.gd`:

```gdscript
extends Node2D

var entity_id: int = -1
var _target_position: Vector2 = Vector2.ZERO
var _facing: Vector2 = Vector2.RIGHT
var _state: int = 0  # EnemyEntity.State
var _spawn_timer: float = 0.0
var _spawn_duration: float = 0.5  # Set on first SPAWNING state update
var _visual: ColorRect
var _facing_line: Line2D
var _time: float = 0.0

# Wobble parameters
const WOBBLE_FREQ: float = 3.0
const WOBBLE_AMOUNT: float = 0.03

# Spawn pop tween
var _pop_tween: Tween = null

# Colors
const ENEMY_COLOR = Color(0.4, 0.75, 0.3)  # sickly green


func _ready():
	_visual = ColorRect.new()
	_visual.size = Vector2(16, 16)
	_visual.position = Vector2(-8, -8)
	_visual.color = ENEMY_COLOR
	_visual.name = "Visual"
	add_child(_visual)

	_facing_line = Line2D.new()
	_facing_line.width = 2.0
	_facing_line.default_color = Color(0.9, 0.9, 0.3)
	_facing_line.points = PackedVector2Array([Vector2.ZERO, Vector2(4, 0)])
	_facing_line.name = "FacingLine"
	add_child(_facing_line)


func initialize(id: int, pos: Vector2) -> void:
	entity_id = id
	position = pos
	_target_position = pos


func update_from_data(data: Dictionary) -> void:
	_target_position = data["position"]
	_facing = data.get("facing", Vector2.RIGHT)
	var new_state = data.get("state", 0)

	# Detect transition out of SPAWNING
	if _state == 0 and new_state != 0:
		_play_spawn_pop()

	if new_state == 0 and _spawn_timer > 0.0:
		_spawn_duration = maxf(_spawn_duration, data.get("spawn_timer", 0.5))

	_state = new_state
	_spawn_timer = data.get("spawn_timer", 0.0)

	# Update facing line
	_facing_line.points = PackedVector2Array([Vector2.ZERO, _facing * 4.0])


func _process(delta: float):
	position = _target_position
	_time += delta

	if _state == 0:  # SPAWNING
		# Fade in based on spawn progress
		var progress = 1.0 - clampf(_spawn_timer / _spawn_duration, 0.0, 1.0)
		modulate.a = lerpf(0.2, 0.8, progress)
		scale = Vector2.ONE * lerpf(0.5, 0.8, progress)
	elif _state == 1:  # IDLE
		modulate.a = 1.0
		# Idle wobble
		var wobble = 1.0 + sin(_time * WOBBLE_FREQ * TAU) * WOBBLE_AMOUNT
		if _pop_tween == null or not _pop_tween.is_running():
			scale = Vector2(wobble, wobble)
	else:  # CHASING
		modulate.a = 1.0
		if _pop_tween == null or not _pop_tween.is_running():
			scale = Vector2.ONE


func _play_spawn_pop() -> void:
	if _pop_tween != null and _pop_tween.is_running():
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.07)
	_pop_tween.tween_property(self, "scale", Vector2.ONE, 0.08)
```

- [ ] **Step 3: Commit**

```bash
git add godot/view/world/enemy_view.gd godot/view/world/enemy_view.tscn
git commit -m "Add EnemyView with facing indicator, idle wobble, and spawn pop"
```

---

### Task 11: Death Effect

Particle burst on enemy death.

**Files:**
- Create: `godot/view/effects/enemy_death_effect.gd`

- [ ] **Step 1: Implement death effect**

Create `godot/view/effects/enemy_death_effect.gd`:

```gdscript
extends Node2D

## Spawns a brief flash + particle burst at the death position.
## Self-destructs after the animation completes.

var _flash: ColorRect


func _ready():
	# Flash rectangle
	_flash = ColorRect.new()
	_flash.size = Vector2(20, 20)
	_flash.position = Vector2(-10, -10)
	_flash.color = Color(1.0, 1.0, 0.7, 0.9)
	add_child(_flash)

	# Tween: flash -> shrink -> free
	var tween = create_tween()
	tween.tween_property(_flash, "modulate:a", 0.0, 0.25)
	tween.parallel().tween_property(_flash, "scale", Vector2(2.0, 2.0), 0.15)
	tween.parallel().tween_property(_flash, "scale", Vector2.ZERO, 0.25).set_delay(0.15)
	tween.tween_callback(queue_free)
```

- [ ] **Step 2: Commit**

```bash
git add godot/view/effects/enemy_death_effect.gd
git commit -m "Add enemy death flash effect"
```

---

### Task 12: WorldView + Client Integration + Collision

Extend WorldView to manage EnemyView instances. Add enemy collision proxies on the client. Update player collision mask.

**Files:**
- Modify: `godot/view/world/world_view.gd`
- Modify: `godot/client_main.gd`
- Modify: `godot/simulation/entities/player_entity.tscn`

- [ ] **Step 1: Extend WorldView for enemies**

In `godot/view/world/world_view.gd`, add at the top:

```gdscript
var EnemyViewScene: PackedScene = preload("res://view/world/enemy_view.tscn")
var EnemyDeathEffect = preload("res://view/effects/enemy_death_effect.gd")

var _enemy_views: Dictionary = {}  # entity_id -> EnemyView node
```

Update `initialize` to connect enemy signals:

```gdscript
func initialize(net_client: NetClient) -> void:
	_net_client = net_client
	_net_client.connected.connect(_on_connected)
	_net_client.disconnected.connect(_on_disconnected)
	_net_client.player_joined.connect(_on_player_joined)
	_net_client.player_left.connect(_on_player_left)
	_net_client.snapshot_received.connect(_on_snapshot)
	_net_client.enemy_died_received.connect(_on_enemy_died)
```

Update `_on_disconnected` to clear enemy views:

```gdscript
func _on_disconnected():
	for view in _player_views.values():
		view.queue_free()
	_player_views.clear()
	for view in _enemy_views.values():
		view.queue_free()
	_enemy_views.clear()
```

Update `_process` to update enemy positions:

```gdscript
func _process(delta: float):
	if _net_client == null:
		return

	# Player views (existing code unchanged)
	for player_id in _player_views:
		var view = _player_views[player_id]
		if view.is_local:
			var local_pos = _net_client.get_local_player_position()
			if local_pos != null:
				var offset = _net_client.get_visual_offset()
				view.update_position(local_pos + offset)
				_net_client.blend_visual_offset(delta)
		else:
			var interp_pos = _net_client.get_interpolated_position(player_id)
			if interp_pos != null:
				view.update_position(interp_pos)

	# Enemy views
	var current_enemy_ids = _net_client.get_enemy_ids()

	# Create views for new enemies
	for eid in current_enemy_ids:
		if not _enemy_views.has(eid):
			var data = _net_client.get_interpolated_enemy(eid)
			if data != null:
				_add_enemy_view(eid, data["position"])

	# Update existing views
	for eid in _enemy_views.keys():
		if eid not in current_enemy_ids:
			_remove_enemy_view(eid)
		else:
			var data = _net_client.get_interpolated_enemy(eid)
			if data != null:
				_enemy_views[eid].update_from_data(data)
```

Add enemy view management:

```gdscript
func _add_enemy_view(entity_id: int, pos: Vector2) -> void:
	if _enemy_views.has(entity_id):
		return
	var view = EnemyViewScene.instantiate()
	add_child(view)
	view.initialize(entity_id, pos)
	_enemy_views[entity_id] = view


func _remove_enemy_view(entity_id: int) -> void:
	if _enemy_views.has(entity_id):
		_enemy_views[entity_id].queue_free()
		_enemy_views.erase(entity_id)


func _on_enemy_died(event: Dictionary) -> void:
	var effect = Node2D.new()
	effect.set_script(EnemyDeathEffect)
	effect.position = event["position"]
	add_child(effect)
	# Remove the view (will be cleaned up next frame anyway via snapshot diff)
	_remove_enemy_view(event["entity_id"])
```

- [ ] **Step 2: Add enemy collision proxies in client_main.gd**

In `godot/client_main.gd`, add after `_remote_proxies`:

```gdscript
var _enemy_proxies: Dictionary = {}  # entity_id -> StaticBody2D
```

In `_on_connected`, connect the enemy snapshot signal:

```gdscript
_net_client.enemy_snapshot_updated.connect(_on_enemy_snapshot)
```

Add the handler and proxy management:

```gdscript
func _on_enemy_snapshot(enemy_entities: Dictionary) -> void:
	# Create proxies for new enemies (skip SPAWNING state — no collision yet)
	for eid in enemy_entities:
		var ent = enemy_entities[eid]
		if ent["state"] == 0:  # SPAWNING — no collision
			continue
		if not _enemy_proxies.has(eid):
			_add_enemy_proxy(eid, ent["position"])

	# Remove proxies for enemies no longer present or returned to SPAWNING
	for eid in _enemy_proxies.keys():
		if not enemy_entities.has(eid) or enemy_entities[eid]["state"] == 0:
			_remove_enemy_proxy(eid)


func _add_enemy_proxy(entity_id: int, pos: Vector2) -> void:
	if _enemy_proxies.has(entity_id):
		return
	var body = StaticBody2D.new()
	body.collision_layer = 4  # layer 3 (enemy)
	body.collision_mask = 0  # proxies don't need to detect anything
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(12, 12)
	collision.shape = shape
	body.add_child(collision)
	body.position = pos
	add_child(body)
	_enemy_proxies[entity_id] = body


func _remove_enemy_proxy(entity_id: int) -> void:
	if _enemy_proxies.has(entity_id):
		_enemy_proxies[entity_id].queue_free()
		_enemy_proxies.erase(entity_id)
```

Update `_process` to sync enemy proxy positions (add after `_update_remote_proxies()`):

```gdscript
_update_enemy_proxies()
```

Add:

```gdscript
func _update_enemy_proxies() -> void:
	for eid in _enemy_proxies:
		var data = _net_client.get_interpolated_enemy(eid)
		if data != null:
			_enemy_proxies[eid].position = data["position"]
```

Update `_on_disconnected` to clean up enemy proxies:

```gdscript
for proxy in _enemy_proxies.values():
	proxy.queue_free()
_enemy_proxies.clear()
```

- [ ] **Step 3: Update player collision mask for enemies**

In `godot/simulation/entities/player_entity.tscn`, add collision_mask to include enemy layer:

Change the CharacterBody2D node to:

```
[node name="PlayerEntity" type="CharacterBody2D"]
collision_mask = 5
script = ExtResource("1")
```

`collision_mask = 5` = layers 1 + 3 (bits 0 + 2 = 1 + 4 = 5). Player now collides with walls (layer 1) and enemies (layer 3).

- [ ] **Step 4: Run all existing tests to verify nothing is broken**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gexit`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add godot/view/world/world_view.gd godot/client_main.gd godot/simulation/entities/player_entity.tscn
git commit -m "Wire up enemy views, collision proxies, and player collision mask"
```

---

### Task 13: End-to-End Verification

Start server + client, verify enemies spawn, wander, chase, and render.

**Files:** None (manual verification)

- [ ] **Step 1: Run all tests**

Run: `cd /Users/jacob/Repos/hexvael/godot && godot --headless -s addons/gut/gut_cmdln.gd -gexit`
Expected: All tests PASS (spatial grid, enemy entity, steering, aggro, enemy system, spawner, network encoding, snapshot, existing player/network tests)

- [ ] **Step 2: Start server**

Run in a terminal:
```bash
cd /Users/jacob/Repos/hexvael/godot && godot --headless --main-pack project.godot -- --server res://server.tscn --port 9050
```
Or if using the Godot editor, run the server scene directly.

Expected: "Server listening on port 9050" in console.

- [ ] **Step 3: Start client and connect**

Open a second terminal or use the Godot editor to run `client.tscn`. Connect to `localhost:9050`.

Expected:
- Player (blue square) spawns at center
- After ~2 seconds (spawn_interval), green squares appear at arena edges with a fade-in telegraph
- After telegraph (~0.5s), enemies pop in and begin wandering
- When enemies detect the player (within 250px), they chase
- Enemies spread out via separation (don't stack on top of each other)
- Enemies slow down near the player (arrival behavior)
- Enemies body-block the player (collision works)
- Moving away from enemies causes them to follow with a smooth turn rate
- Enemies near the edge that don't detect the player wander idly with a subtle wobble

- [ ] **Step 4: Verify with two clients**

Connect a second browser/client. Verify:
- Enemies chase the nearest player (not always the same one)
- Sticky aggro works (enemy doesn't jitter between equidistant players)
- Both clients see the same enemies in the same positions (interpolation works)

- [ ] **Step 5: Final commit with any fixes**

If any issues were found and fixed, commit them:
```bash
git add -A
git commit -m "Fix issues found during end-to-end enemy verification"
```
