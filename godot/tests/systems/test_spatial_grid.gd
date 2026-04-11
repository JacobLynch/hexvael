extends GutTest

var SpatialGrid = preload("res://simulation/systems/spatial_grid.gd")


func test_empty_grid_returns_empty():
	var grid = SpatialGrid.new(32.0)
	var result = grid.query_nearby(Vector2(100, 100))
	assert_eq(result.size(), 0)


func test_insert_and_query_finds_entity():
	var grid = SpatialGrid.new(32.0)
	var entity = {"id": 1, "position": Vector2(50, 50)}
	grid.insert(entity, entity.position)
	var result = grid.query_nearby(Vector2(50, 50))
	assert_eq(result.size(), 1)
	assert_eq(result[0].id, 1)


func test_query_finds_neighbor_in_adjacent_cell():
	var grid = SpatialGrid.new(32.0)
	var e1 = {"id": 1, "position": Vector2(30, 30)}
	var e2 = {"id": 2, "position": Vector2(34, 30)}
	grid.insert(e1, e1.position)
	grid.insert(e2, e2.position)
	var result = grid.query_nearby(Vector2(30, 30))
	assert_eq(result.size(), 2, "Should find both entities across cell boundary")


func test_query_does_not_find_distant_entity():
	var grid = SpatialGrid.new(32.0)
	var near = {"id": 1, "position": Vector2(50, 50)}
	var far = {"id": 2, "position": Vector2(500, 500)}
	grid.insert(near, near.position)
	grid.insert(far, far.position)
	var result = grid.query_nearby(Vector2(50, 50))
	assert_eq(result.size(), 1, "Should only find nearby entity")
	assert_eq(result[0].id, 1)


func test_clear_removes_all():
	var grid = SpatialGrid.new(32.0)
	grid.insert({"id": 1, "position": Vector2(10, 10)}, Vector2(10, 10))
	grid.insert({"id": 2, "position": Vector2(20, 20)}, Vector2(20, 20))
	grid.clear()
	assert_eq(grid.query_nearby(Vector2(10, 10)).size(), 0)


func test_many_entities_same_cell():
	var grid = SpatialGrid.new(32.0)
	for i in range(20):
		grid.insert({"id": i, "position": Vector2(5, 5)}, Vector2(5, 5))
	var result = grid.query_nearby(Vector2(5, 5))
	assert_eq(result.size(), 20)


func test_query_radius_filters_by_distance():
	var grid = SpatialGrid.new(32.0)
	var close = {"id": 1, "position": Vector2(50, 50)}
	var medium = {"id": 2, "position": Vector2(70, 50)}
	var far_ish = {"id": 3, "position": Vector2(90, 50)}
	grid.insert(close, close.position)
	grid.insert(medium, medium.position)
	grid.insert(far_ish, far_ish.position)
	var result = grid.query_radius(Vector2(50, 50), 25.0)
	assert_eq(result.size(), 2, "Only entities within 25px radius")
