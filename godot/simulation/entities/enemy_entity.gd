class_name EnemyEntity
extends CharacterBody2D

enum State { SPAWNING = 0, IDLE = 1, CHASING = 2, DEAD = 3 }

const KNOCKBACK_FRICTION: float = 12.0  ## Velocity decay rate during stagger

var entity_id: int = -1
var state: int = State.SPAWNING
var facing: Vector2 = Vector2.RIGHT
var target_player_id: int = -1
var actual_speed: float = 0.0
var spawn_timer: float = 0.0
var _wander_target: Vector2 = Vector2.ZERO
var _params: EnemyParams = null
# Knockback state
var knockback_velocity: Vector2 = Vector2.ZERO
var stagger_timer: float = 0.0
var _cached_collision_radius: float = -1.0
var health: HealthComponent = null


func initialize(id: int, spawn_position: Vector2, params: EnemyParams) -> void:
	entity_id = id
	position = spawn_position
	_params = params
	health = HealthComponent.new(params.max_health)
	actual_speed = params.base_speed * (1.0 + RNG.next_float_range(
		-params.speed_variation, params.speed_variation))
	spawn_timer = params.base_spawn_duration * (1.0 + RNG.next_float_range(
		-params.spawn_duration_variation, params.spawn_duration_variation))
	_wander_target = position


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

	# Separation — ratio-based: full repulsion at d=0, zero at d=separation_radius
	var separation_dir = Vector2.ZERO
	for neighbor in neighbors:
		if neighbor == self:
			continue
		var offset = position - neighbor.position
		var d = offset.length()
		if d < _params.separation_radius and d > 0.0:
			separation_dir += offset.normalized() * (1.0 - d / _params.separation_radius)

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

	# Arrival — stop at min_approach_distance
	var approach_dist = dist_to_target - _params.min_approach_distance
	var speed_factor = clampf(approach_dist / _params.arrival_radius, 0.0, 1.0)

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


func get_collision_radius() -> float:
	if _cached_collision_radius < 0.0:
		var shape_node := $CollisionShape2D as CollisionShape2D
		var shape := shape_node.shape
		if shape is CircleShape2D:
			_cached_collision_radius = (shape as CircleShape2D).radius
		elif shape is RectangleShape2D:
			var s := (shape as RectangleShape2D).size
			_cached_collision_radius = max(s.x, s.y) / 2.0
		else:
			push_warning("EnemyEntity: unknown collision shape, defaulting to 16 px")
			_cached_collision_radius = 16.0
	return _cached_collision_radius


## Returns the entity's world-space AABB based on its CollisionShape2D.
## Preferred over get_collision_radius for rectangular shapes — avoids
## the inscribed-circle under-approximation that misses corners.
func get_collision_rect() -> Rect2:
	var shape_node := $CollisionShape2D as CollisionShape2D
	var shape := shape_node.shape
	var half: Vector2
	if shape is RectangleShape2D:
		half = (shape as RectangleShape2D).size / 2.0
	elif shape is CircleShape2D:
		var r := (shape as CircleShape2D).radius
		half = Vector2(r, r)
	else:
		push_warning("EnemyEntity: unknown collision shape, using 16 px fallback")
		half = Vector2(16, 16)
	return Rect2(position - half, half * 2.0)


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


func to_snapshot_data() -> Dictionary:
	return {
		"entity_id": entity_id,
		"position": position,
		"state": state,
		"facing": facing,
		"spawn_timer": spawn_timer,
		"health": health.current if health != null else 0,
		"max_health": health.max_health if health != null else 0,
	}


func kill() -> void:
	_set_state(State.DEAD)
