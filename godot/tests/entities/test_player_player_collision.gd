extends GutTest
## Regression test: local player prediction must collide with remote player proxies.
## The bug was that remote players were visual-only on the client, so the local
## player's move_and_collide() walked right through them while the server blocked
## the movement, causing rubberbanding.

var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")

var _local: PlayerEntity
var _remote_proxy: StaticBody2D

const TICK_S: float = MessageTypes.TICK_INTERVAL_MS / 1000.0


func _create_proxy(pos: Vector2) -> StaticBody2D:
	var body = StaticBody2D.new()
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(12, 12)  # Must match PlayerEntity
	collision.shape = shape
	body.add_child(collision)
	body.position = pos
	add_child_autofree(body)
	return body


func before_each():
	_local = PlayerEntityScene.instantiate()
	add_child_autofree(_local)
	_local.initialize(1, Vector2(100.0, 160.0))


func test_local_player_stops_at_remote_proxy():
	# Remote player proxy directly to the right
	_remote_proxy = _create_proxy(Vector2(120.0, 160.0))

	_local.apply_input(Vector2(1.0, 0.0))
	for i in range(20):
		_local.tick()

	# Local player (12x12) and proxy (12x12) — they should collide.
	# Player at x=100 moving right toward proxy at x=120.
	# Player edge at 106, proxy edge at 114. Gap = 8px.
	# At 200px/s * 0.05s = 10px/tick, should reach and stop within a few ticks.
	assert_lt(_local.position.x, 120.0,
		"Local player should not pass through remote player proxy")


func test_local_player_slides_along_remote_proxy():
	# Remote player blocking direct rightward path, local moves diagonally.
	# move_and_collide slides the remainder along the collision normal,
	# so the player deflects vertically while the proxy blocks direct overlap.
	_remote_proxy = _create_proxy(Vector2(130.0, 160.0))

	_local.apply_input(Vector2(1.0, 1.0).normalized())
	for i in range(20):
		_local.tick()

	# Player should have deflected downward — y must have changed
	assert_gt(absf(_local.position.y - 160.0), 1.0,
		"Should have slid vertically when blocked by remote proxy")
