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

# Auto-assigned ids start at 1000 to avoid collisions with legacy enum ids (0-N).
static var _auto_id: int = 1000


## Register a new projectile type at runtime.
## Call this from game init or mod loading.
## If type_id is omitted, an id is auto-assigned starting at 1000 so the type
## remains network-reachable via get_type_id(name).
static func register(type_name: String, params: ProjectileParams, type_id: int = -1) -> void:
	if type_id < 0:
		type_id = _auto_id
		_auto_id += 1
	_registry[type_name] = params
	_name_to_id[type_name] = type_id
	_id_to_name[type_id] = type_name


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
