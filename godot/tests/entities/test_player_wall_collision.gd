extends GutTest
## Regression test: client-side prediction must respect arena wall collisions.
## The bug was that the client scene had no wall collision geometry, so
## move_and_collide() had nothing to stop the player — predictions walked
## through walls and the server bounced them back.

var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
var ArenaScene = preload("res://shared/world/arena.tscn")

var _arena: Node2D
var _player: PlayerEntity

const TICK_S: float = MessageTypes.TICK_INTERVAL_MS / 1000.0
# Arena is 2400x1600, walls are 8px thick centered at boundaries.
# Player is 12x12 (6px half-extent). Wall inner edges:
#   Top:    y = 0      (wall center y=-4, half-thickness=4)
#   Bottom: y = 1600   (wall center y=1604, half-thickness=4)
#   Left:   x = 0      (wall center x=-4, half-thickness=4)
#   Right:  x = 2400   (wall center x=2404, half-thickness=4)
# Player stops when its edge meets the wall edge, so min/max position
# is offset by the player's 6px half-extent: x in [6, 2394], y in [6, 1594].


func before_each():
	_arena = ArenaScene.instantiate()
	add_child_autofree(_arena)
	_player = PlayerEntityScene.instantiate()
	add_child_autofree(_player)


func test_player_stops_at_right_wall():
	# Place player near right edge, moving right
	_player.initialize(1, Vector2(2390.0, 800.0))
	_player.apply_input({"move_direction": Vector2(1.0, 0.0), "aim_direction": Vector2.RIGHT})

	# Run enough ticks to push well past the wall if there were no collision
	for i in range(20):
		_player.advance(TICK_S)

	assert_lt(_player.position.x, 2400.0,
		"Player should not pass through the right wall")


func test_player_stops_at_left_wall():
	_player.initialize(1, Vector2(50.0, 800.0))
	_player.apply_input({"move_direction": Vector2(-1.0, 0.0), "aim_direction": Vector2.LEFT})

	for i in range(20):
		_player.advance(TICK_S)

	assert_gt(_player.position.x, 0.0,
		"Player should not pass through the left wall")


func test_player_stops_at_top_wall():
	_player.initialize(1, Vector2(1200.0, 50.0))
	_player.apply_input({"move_direction": Vector2(0.0, -1.0), "aim_direction": Vector2.UP})

	for i in range(20):
		_player.advance(TICK_S)

	assert_gt(_player.position.y, 0.0,
		"Player should not pass through the top wall")


func test_player_stops_at_bottom_wall():
	_player.initialize(1, Vector2(1200.0, 1550.0))
	_player.apply_input({"move_direction": Vector2(0.0, 1.0), "aim_direction": Vector2.DOWN})

	for i in range(20):
		_player.advance(TICK_S)

	assert_lt(_player.position.y, 1600.0,
		"Player should not pass through the bottom wall")


func test_player_held_against_wall_stays_put():
	# Player already at the wall, holding into it — should not drift
	_player.initialize(1, Vector2(2394.0, 800.0))
	_player.apply_input({"move_direction": Vector2(1.0, 0.0), "aim_direction": Vector2.RIGHT})

	_player.advance(TICK_S)
	var pos_after_one = _player.position

	for i in range(10):
		_player.advance(TICK_S)

	assert_almost_eq(_player.position.x, pos_after_one.x, 0.1,
		"Player pressed against wall should not drift")
