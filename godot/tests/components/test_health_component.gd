extends GutTest

var HealthComponentCls = preload("res://simulation/components/health_component.gd")

func test_init_sets_current_to_max():
	var health = HealthComponentCls.new(100)
	assert_eq(health.current, 100)
	assert_eq(health.max_health, 100)

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

func test_take_damage_ignores_negative():
	# Negative amounts must never heal. Trust-boundary guard: any future AoE
	# or TCE trigger could accidentally pass a signed delta; silently healing
	# the target would be a subtle exploit and mask logic bugs.
	var health = HealthComponentCls.new(100)
	health.take_damage(40)  # 60 remaining
	var result = health.take_damage(-50)
	assert_eq(health.current, 60, "Negative damage must not change current")
	assert_eq(result["damage_dealt"], 0)
	assert_false(result["killed"])

func test_take_damage_zero():
	var health = HealthComponentCls.new(100)
	var result = health.take_damage(0)
	assert_eq(health.current, 100)
	assert_eq(result["damage_dealt"], 0)
	assert_false(result["killed"])

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
