class_name ProjectileEntity
extends RefCounted

enum DespawnReason {
	ALIVE    = -1,
	LIFETIME = 0,
	WALL     = 1,
	ENEMY    = 2,
	PLAYER   = 3,
	SELF     = 4,
	REJECTED = 5,  # client-only, never broadcast
}

const RECONCILE_DURATION: float = 0.1

# Identity
var projectile_id: int = -1
var type_id: int = 0
var owner_player_id: int = -1

# State
var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.RIGHT
var time_remaining: float = 0.0
var spawn_grace_remaining: float = 0.0
var time_since_spawn: float = 0.0
var params: ProjectileParams = null

# Reconciliation bookkeeping (client-side only)
var is_predicted: bool = false
var spawn_input_seq: int = -1
var _reconcile_delta: Vector2 = Vector2.ZERO
var _reconcile_remaining: float = 0.0


func initialize(
		id: int, type: int, owner: int,
		origin: Vector2, dir: Vector2,
		p: ProjectileParams) -> void:
	assert(p != null, "ProjectileEntity.initialize: params must not be null")
	projectile_id = id
	type_id = type
	owner_player_id = owner
	position = origin
	if dir.length_squared() > 0.0:
		direction = dir.normalized()
	else:
		push_error("ProjectileEntity.initialize: direction is zero-length, projectile will not move")
		direction = Vector2.ZERO
	params = p
	time_remaining = p.lifetime
	spawn_grace_remaining = p.spawn_grace
	time_since_spawn = 0.0


func start_reconcile(target: Vector2) -> void:
	_reconcile_delta = target - position
	_reconcile_remaining = RECONCILE_DURATION


# Dt-independent step. Called by server tick AND client prediction.
# Returns a DespawnReason if killed this step, else ALIVE.
func advance(dt: float, walls: Array, players: Array, enemies: Array) -> int:
	# 1. Motion (straight-line — trivially dt-independent)
	position += direction * params.speed * dt

	# 2. Timers
	time_remaining -= dt
	spawn_grace_remaining -= dt
	time_since_spawn += dt

	# 3. Reconciliation lerp
	if _reconcile_remaining > 0.0:
		var chunk: float = min(dt, _reconcile_remaining)
		position += _reconcile_delta * (chunk / RECONCILE_DURATION)
		_reconcile_remaining -= chunk

	# 4. Lifetime
	if time_remaining <= 0.0:
		return DespawnReason.LIFETIME

	# 5. Walls (static, always checked — safe on both server and client)
	for wall in walls:
		if CollisionMath.circle_aabb_overlap(position, params.radius, wall):
			return DespawnReason.WALL

	# 6. Enemies (server-only — client passes empty)
	for enemy in enemies:
		if enemy.state == EnemyEntity.State.DEAD:
			continue
		if CollisionMath.circle_circle_overlap(
				position, params.radius, enemy.position, enemy.get_collision_radius()):
			return DespawnReason.ENEMY

	# 7. Players (owner excluded during spawn grace)
	for player in players:
		var is_owner: bool = (player.player_id == owner_player_id)
		if is_owner and spawn_grace_remaining > 0.0:
			continue
		if CollisionMath.circle_circle_overlap(
				position, params.radius, player.position, player.get_collision_radius()):
			return (DespawnReason.SELF
					if is_owner else DespawnReason.PLAYER)

	return DespawnReason.ALIVE
