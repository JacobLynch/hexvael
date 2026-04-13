class_name ProjectileType

# Legacy enum for backwards compatibility with existing code
enum Id {
	TEST = 0,
}

# String-keyed registry: name -> ProjectileParams resource
static var _registry: Dictionary = {
	"test": preload("res://shared/projectiles/test_projectile.tres"),
}

# Bidirectional name <-> id mapping for network serialization
static var _name_to_id: Dictionary = {
	"test": Id.TEST,
}
static var _id_to_name: Dictionary = {
	Id.TEST: "test",
}


## Register a new projectile type at runtime.
## Call this from game init or mod loading.
static func register(name: String, params: ProjectileParams, type_id: int = -1) -> void:
	_registry[name] = params
	if type_id >= 0:
		_name_to_id[name] = type_id
		_id_to_name[type_id] = name


## Unregister a projectile type (for testing or mod unloading).
static func unregister(name: String) -> void:
	_registry.erase(name)
	if _name_to_id.has(name):
		var type_id: int = _name_to_id[name]
		_id_to_name.erase(type_id)
		_name_to_id.erase(name)


## Get params by string name (preferred for new code).
## Returns null if the type is not registered (caller should handle).
static func get_params_by_name(name: String) -> ProjectileParams:
	return _registry.get(name, null)


## Get params by enum id (legacy compatibility).
static func get_params(type_id: int) -> ProjectileParams:
	if _id_to_name.has(type_id):
		return _registry[_id_to_name[type_id]]
	push_error("ProjectileType.get_params: unknown type_id %d" % type_id)
	return null


## Get the numeric type_id for a string name (for network serialization).
static func get_type_id(name: String) -> int:
	if _name_to_id.has(name):
		return _name_to_id[name]
	push_error("ProjectileType.get_type_id: unknown type '%s'" % name)
	return -1


## Get the string name for a numeric type_id.
static func get_type_name(type_id: int) -> String:
	if _id_to_name.has(type_id):
		return _id_to_name[type_id]
	return ""
