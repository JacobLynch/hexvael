extends GutTest

var ProjectileSpawnRouter = preload("res://simulation/systems/projectile_spawn_router.gd")
var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
var PlayerPositionHistory = preload("res://simulation/systems/player_position_history.gd")

func _make_player(id: int, pos: Vector2) -> PlayerEntity:
	var p = PlayerEntityScene.instantiate()
	add_child_autofree(p)
	p.player_id = id
	p.position = pos
	p.aim_direction = Vector2.RIGHT
	return p

func _make_system() -> ProjectileSystem:
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	return sys

func test_no_fire_flag_no_spawn():
	var sys = _make_system()
	var player = _make_player(42, Vector2(100, 100))
	var input = {
		"action_flags": 0,
		"input_seq": 1,
	}
	ProjectileSpawnRouter.handle_fire(player, input, sys, {"authoritative": false})
	assert_eq(sys.projectiles.size(), 0)

func test_cooldown_blocks_spawn():
	var sys = _make_system()
	sys.start_cooldown(42)
	var player = _make_player(42, Vector2(100, 100))
	var input = {
		"action_flags": MessageTypes.InputActionFlags.FIRE,
		"input_seq": 1,
	}
	ProjectileSpawnRouter.handle_fire(player, input, sys, {"authoritative": false})
	assert_eq(sys.projectiles.size(), 0)

func test_client_branch_spawns_predicted_from_player_position():
	var sys = _make_system()
	var player = _make_player(42, Vector2(100, 100))
	var input = {
		"action_flags": MessageTypes.InputActionFlags.FIRE,
		"input_seq": 1,
	}
	ProjectileSpawnRouter.handle_fire(player, input, sys, {"authoritative": false, "projectile_type": "test"})
	assert_eq(sys.projectiles.size(), 1)
	assert_true(sys.projectiles.has(-1))   # negative temp id
	var proj: ProjectileEntity = sys.projectiles[-1]
	var params = ProjectileType.get_params(ProjectileType.Id.TEST)
	# Predicted spawn position is player position + aim * spawn_offset
	assert_almost_eq(proj.position.x, 100.0 + params.spawn_offset, 0.01)
	assert_almost_eq(proj.position.y, 100.0, 0.01)

func test_server_branch_rewinds_from_history_and_fast_forwards():
	var sys = _make_system()
	var history = PlayerPositionHistory.new()
	# Multiple historic samples so rewind has data
	history.record(42, 100, Vector2(50, 100))
	history.record(42, 101, Vector2(60, 100))
	history.record(42, 102, Vector2(70, 100))
	history.record(42, 103, Vector2(80, 100))
	history.record(42, 104, Vector2(90, 100))
	history.record(42, 105, Vector2(100, 100))
	var player = _make_player(42, Vector2(100, 100))
	var spawn_events: Array = []
	var context = {
		"authoritative": true,
		"rtt_ms": 100,   # 50 ms one-way
		"position_history": history,
		"tick": 105,
		"spawn_events": spawn_events,
		"projectile_type": "test",
	}
	var input = {
		"action_flags": MessageTypes.InputActionFlags.FIRE,
		"input_seq": 77,
	}
	ProjectileSpawnRouter.handle_fire(player, input, sys, context)
	assert_eq(sys.projectiles.size(), 1)
	assert_eq(spawn_events.size(), 1)
	assert_eq(spawn_events[0]["owner_player_id"], 42)
	assert_eq(spawn_events[0]["input_seq"], 77)
