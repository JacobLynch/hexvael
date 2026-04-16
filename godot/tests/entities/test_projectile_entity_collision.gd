extends GutTest

var ProjectileEntity = preload("res://simulation/entities/projectile_entity.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
var EnemyEntityScene = preload("res://simulation/entities/enemy_entity.tscn")

func _make_projectile(origin: Vector2, dir: Vector2, owner_id: int) -> ProjectileEntity:
	var p = ProjectileEntity.new()
	var params = ProjectileType.get_params(ProjectileType.Id.TEST)
	p.initialize(1, ProjectileType.Id.TEST, owner_id, origin, dir, params)
	return p

func test_projectile_hits_enemy_returns_enemy_reason():
	var proj = _make_projectile(Vector2(100, 100), Vector2.RIGHT, 42)
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	enemy.position = Vector2(120, 100)
	enemy.state = EnemyEntity.State.IDLE   # not DEAD
	var reason = proj.advance(0.05, [], [], [enemy])
	assert_eq(reason, ProjectileEntity.DespawnReason.ENEMY)

func test_projectile_skips_dead_enemies():
	var proj = _make_projectile(Vector2(100, 100), Vector2.RIGHT, 42)
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	enemy.position = Vector2(120, 100)
	enemy.state = EnemyEntity.State.DEAD
	var reason = proj.advance(0.05, [], [], [enemy])
	assert_eq(reason, ProjectileEntity.DespawnReason.ALIVE)

func test_projectile_hits_non_owner_player_returns_player_reason():
	var proj = _make_projectile(Vector2(100, 100), Vector2.RIGHT, 42)
	var other = PlayerEntityScene.instantiate()
	add_child_autofree(other)
	other.player_id = 99
	other.position = Vector2(120, 100)
	var reason = proj.advance(0.05, [], [other], [])
	assert_eq(reason, ProjectileEntity.DespawnReason.PLAYER)

func test_owner_passes_through_during_spawn_grace():
	var proj = _make_projectile(Vector2(100, 100), Vector2.RIGHT, 42)
	proj.direction = Vector2.ZERO   # override to prevent movement
	var owner = PlayerEntityScene.instantiate()
	add_child_autofree(owner)
	owner.player_id = 42
	owner.position = Vector2(100, 100)
	var reason = proj.advance(0.05, [], [owner], [])
	assert_eq(reason, ProjectileEntity.DespawnReason.ALIVE)

func test_owner_passes_through_after_grace_expires():
	# Projectiles never collide with their owner — the player can dash ahead
	# of a slow projectile without taking self-damage.
	var proj = _make_projectile(Vector2(100, 100), Vector2.RIGHT, 42)
	proj.direction = Vector2.ZERO   # override to prevent movement
	proj.spawn_grace_remaining = 0.0
	var owner = PlayerEntityScene.instantiate()
	add_child_autofree(owner)
	owner.player_id = 42
	owner.position = Vector2(100, 100)
	var reason = proj.advance(0.05, [], [owner], [])
	assert_eq(reason, ProjectileEntity.DespawnReason.ALIVE)

func test_collision_order_walls_before_enemies():
	# Wall and enemy both in range — walls should win
	var proj = _make_projectile(Vector2(10, 10), Vector2.RIGHT, 42)
	proj.direction = Vector2.ZERO   # override to prevent movement
	var walls: Array[Rect2] = [Rect2(Vector2(0, 0), Vector2(20, 20))]
	var enemy = EnemyEntityScene.instantiate()
	add_child_autofree(enemy)
	enemy.position = Vector2(10, 10)
	enemy.state = EnemyEntity.State.IDLE
	var reason = proj.advance(0.01, walls, [], [enemy])
	assert_eq(reason, ProjectileEntity.DespawnReason.WALL)
