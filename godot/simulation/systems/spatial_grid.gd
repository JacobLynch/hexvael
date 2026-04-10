class_name SpatialGrid

var _cell_size: float
var _grid: Dictionary = {}  # Vector2i -> Array


func _init(cell_size: float = 32.0) -> void:
	_cell_size = cell_size


func _get_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / _cell_size), floori(pos.y / _cell_size))


func insert(entity: Variant, pos: Vector2) -> void:
	var cell = _get_cell(pos)
	if not _grid.has(cell):
		_grid[cell] = []
	_grid[cell].append(entity)


func clear() -> void:
	_grid.clear()


func query_nearby(pos: Vector2) -> Array:
	var cell = _get_cell(pos)
	var result: Array = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key = Vector2i(cell.x + dx, cell.y + dy)
			if _grid.has(key):
				result.append_array(_grid[key])
	return result


func query_radius(pos: Vector2, radius: float) -> Array:
	var candidates = query_nearby(pos)
	var radius_sq = radius * radius
	var result: Array = []
	for entity in candidates:
		if entity.position.distance_squared_to(pos) <= radius_sq:
			result.append(entity)
	return result
