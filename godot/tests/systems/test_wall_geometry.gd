extends GutTest

var WallGeometry = preload("res://shared/projectiles/wall_geometry.gd")
var ArenaScene = preload("res://shared/world/arena.tscn")

func test_extract_returns_four_walls():
    var arena = ArenaScene.instantiate()
    add_child_autofree(arena)
    var aabbs = WallGeometry.extract_aabbs(arena)
    assert_eq(aabbs.size(), 4, "arena has exactly 4 walls")

func test_extract_wall_positions_match_arena():
    var arena = ArenaScene.instantiate()
    add_child_autofree(arena)
    var aabbs: Array = WallGeometry.extract_aabbs(arena)

    # Per shared/world/arena.tscn wall positions and sizes:
    #   Top:    center (1200, -4),  size (2400, 8)
    #   Bottom: center (1200, 1604),size (2400, 8)
    #   Left:   center (-4,   800), size (8, 1600)
    #   Right:  center (2404, 800), size (8, 1600)
    var centers: Array[Vector2] = []
    for rect: Rect2 in aabbs:
        centers.append(rect.get_center())
    assert_true(centers.has(Vector2(1200, -4)))
    assert_true(centers.has(Vector2(1200, 1604)))
    assert_true(centers.has(Vector2(-4, 800)))
    assert_true(centers.has(Vector2(2404, 800)))
