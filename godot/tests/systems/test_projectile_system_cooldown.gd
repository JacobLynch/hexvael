extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")

func test_can_fire_defaults_true():
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	assert_true(sys.can_fire(42))

func test_start_cooldown_blocks_can_fire():
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	sys.start_cooldown(42)
	assert_false(sys.can_fire(42))

func test_tick_cooldowns_decrements():
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	sys.start_cooldown(42)
	sys.tick_cooldowns(0.30)  # longer than 0.20 fire_cooldown
	assert_true(sys.can_fire(42))

func test_cooldown_is_per_player():
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	sys.start_cooldown(42)
	assert_false(sys.can_fire(42))
	assert_true(sys.can_fire(99))
