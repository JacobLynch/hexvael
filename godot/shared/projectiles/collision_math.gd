class_name CollisionMath

static func circle_aabb_overlap(
        center: Vector2, radius: float, rect: Rect2) -> bool:
    var closest_x := clampf(center.x, rect.position.x, rect.end.x)
    var closest_y := clampf(center.y, rect.position.y, rect.end.y)
    var dx := center.x - closest_x
    var dy := center.y - closest_y
    return (dx * dx + dy * dy) < (radius * radius)

static func circle_circle_overlap(
        a: Vector2, ra: float, b: Vector2, rb: float) -> bool:
    var sum := ra + rb
    return a.distance_squared_to(b) < (sum * sum)
