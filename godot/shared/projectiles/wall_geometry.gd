class_name WallGeometry

static func extract_aabbs(arena_root: Node) -> Array[Rect2]:
    var out: Array[Rect2] = []
    var collision := arena_root.get_node_or_null("Collision")
    assert(collision != null, "arena has no Collision node")
    for child in collision.get_children():
        if not (child is CollisionShape2D):
            continue
        var shape := (child as CollisionShape2D).shape
        assert(shape is RectangleShape2D, "non-rect wall shape not supported")
        var rect_shape: RectangleShape2D = shape
        var half: Vector2 = rect_shape.size / 2.0
        var center: Vector2 = child.global_position
        out.append(Rect2(center - half, rect_shape.size))
    return out
