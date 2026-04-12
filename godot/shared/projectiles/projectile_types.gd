class_name ProjectileType

enum Id {
	TEST = 0,
}

static func get_params(type_id: int) -> ProjectileParams:
	match type_id:
		Id.TEST:
			return preload("res://shared/projectiles/test_projectile.tres")
	push_error("ProjectileType.get_params: unknown type_id %d" % type_id)
	return null
