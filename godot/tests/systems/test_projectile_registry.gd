extends GutTest


func test_get_params_by_string_key():
	var params = ProjectileType.get_params_by_name("test")
	assert_not_null(params, "Should return params for 'test' projectile")
	assert_eq(params.speed, 600.0, "Should have correct speed")


func test_get_params_unknown_key_returns_null():
	var params = ProjectileType.get_params_by_name("nonexistent")
	assert_null(params, "Should return null for unknown key")


func test_legacy_enum_still_works():
	var params = ProjectileType.get_params(ProjectileType.Id.TEST)
	assert_not_null(params, "Legacy enum lookup should still work")


func test_register_new_type():
	# This test verifies extensibility — can add types without code changes
	ProjectileType.register("custom", preload("res://shared/projectiles/test_projectile.tres"))
	var params = ProjectileType.get_params_by_name("custom")
	assert_not_null(params, "Should be able to register and retrieve custom type")
	# Clean up
	ProjectileType.unregister("custom")


func test_get_type_id_for_name():
	var type_id = ProjectileType.get_type_id("test")
	assert_eq(type_id, ProjectileType.Id.TEST, "Should map name to enum id")
