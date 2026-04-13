extends GutTest

var CollisionMath = preload("res://shared/projectiles/collision_math.gd")

func test_circle_aabb_overlap_inside():
    var rect = Rect2(Vector2(0, 0), Vector2(100, 100))
    assert_true(CollisionMath.circle_aabb_overlap(Vector2(50, 50), 10.0, rect))

func test_circle_aabb_overlap_touching_edge():
    var rect = Rect2(Vector2(0, 0), Vector2(100, 100))
    assert_true(CollisionMath.circle_aabb_overlap(Vector2(105, 50), 6.0, rect))
    assert_false(CollisionMath.circle_aabb_overlap(Vector2(110, 50), 6.0, rect))

func test_circle_aabb_overlap_corner():
    var rect = Rect2(Vector2(0, 0), Vector2(100, 100))
    # Circle at (103, 103), radius 5 → closest point (100,100), distance ≈ 4.24
    assert_true(CollisionMath.circle_aabb_overlap(Vector2(103, 103), 5.0, rect))
    # Circle at (108, 108), radius 5 → distance ≈ 11.3
    assert_false(CollisionMath.circle_aabb_overlap(Vector2(108, 108), 5.0, rect))

func test_circle_aabb_overlap_far():
    var rect = Rect2(Vector2(0, 0), Vector2(100, 100))
    assert_false(CollisionMath.circle_aabb_overlap(Vector2(500, 500), 50.0, rect))

func test_circle_circle_overlap_touching():
    # Centers 10 apart, radii 5 and 5 → sum is 10, not strictly less, so NO overlap
    assert_false(CollisionMath.circle_circle_overlap(
        Vector2(0, 0), 5.0, Vector2(10, 0), 5.0))
    # Sum 10.1, strictly greater → overlap
    assert_true(CollisionMath.circle_circle_overlap(
        Vector2(0, 0), 5.05, Vector2(10, 0), 5.05))

func test_circle_circle_overlap_distant():
    assert_false(CollisionMath.circle_circle_overlap(
        Vector2(0, 0), 5.0, Vector2(100, 0), 5.0))
