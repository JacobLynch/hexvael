extends GutTest
## Canary: client and server simulation must converge when reconciling.
## If these tests fail, someone forked prediction from authority — the
## "client and server share simulation code" rule is broken.

var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")
var ArenaScene = preload("res://shared/world/arena.tscn")
const MovementParams = preload("res://shared/movement/movement_params.gd")
const PlayerMovementState = preload("res://simulation/entities/player_movement_state.gd")

const TICK_S: float = MessageTypes.TICK_INTERVAL_MS / 1000.0


func _make_player(pos: Vector2) -> PlayerEntity:
	var p = PlayerEntityScene.instantiate()
	add_child_autofree(p)
	p.initialize(1, pos)
	p.params = MovementParams.new()
	return p


func test_replay_matches_server_for_walking():
	# Spawn arena so collision shapes exist for both players
	add_child_autofree(ArenaScene.instantiate())
	var server = _make_player(Vector2(240.0, 160.0))
	var client = _make_player(Vector2(240.0, 160.0))

	var inputs: Array = []
	for seq in range(10):
		inputs.append({
			"seq": seq + 1,
			"move_direction": Vector2(1.0, 0.0),
			"aim_direction": Vector2.RIGHT,
			"dodge_pressed": false,
			"input_seq": seq + 1,
		})

	# Server processes inputs one per tick
	for input in inputs:
		server.apply_input(input)
		server.advance(TICK_S)

	# Client "reconciles" by resetting to initial state then replaying identical inputs
	client.position = Vector2(240.0, 160.0)
	client.velocity = Vector2.ZERO
	for input in inputs:
		client.apply_input(input)
		client.advance(TICK_S)

	assert_almost_eq(client.position.x, server.position.x, 0.5,
		"Client replay must converge to server position")
	assert_almost_eq(client.velocity.x, server.velocity.x, 0.5,
		"Client replay must converge to server velocity")


func test_replay_matches_server_mid_dodge():
	add_child_autofree(ArenaScene.instantiate())
	var server = _make_player(Vector2(240.0, 160.0))
	var client = _make_player(Vector2(240.0, 160.0))

	# Input sequence: walk right for 3 ticks, then dodge, then continue
	var inputs: Array = []
	for i in range(3):
		inputs.append({
			"seq": i + 1, "move_direction": Vector2(1.0, 0.0),
			"aim_direction": Vector2.RIGHT, "dodge_pressed": false, "input_seq": i + 1,
		})
	inputs.append({
		"seq": 4, "move_direction": Vector2(1.0, 0.0),
		"aim_direction": Vector2.RIGHT, "dodge_pressed": true, "input_seq": 4,
	})
	for i in range(3):
		inputs.append({
			"seq": 5 + i, "move_direction": Vector2(1.0, 0.0),
			"aim_direction": Vector2.RIGHT, "dodge_pressed": false, "input_seq": 5 + i,
		})

	for input in inputs:
		server.apply_input(input)
		server.advance(TICK_S)

	for input in inputs:
		client.apply_input(input)
		client.advance(TICK_S)

	assert_almost_eq(client.position.x, server.position.x, 0.5,
		"Client replay through dodge must converge with server")


func test_replay_rejects_server_rejected_dodge():
	# Simulate: client predicted a dodge, but server had cooldown and rejected it.
	# After the reconcile, replay with the actual inputs the server saw (which
	# include the "attempted dodge" — but server rejected it because of cooldown
	# state restored from snapshot).
	add_child_autofree(ArenaScene.instantiate())
	var server = _make_player(Vector2(240.0, 160.0))
	var client = _make_player(Vector2(240.0, 160.0))

	# Put both in cooldown by forcing a prior dodge
	server.move_input = Vector2(1.0, 0.0)
	server.start_dodge()
	for i in range(10):
		server.advance(TICK_S)  # finish dodge, still on cooldown

	client.move_input = Vector2(1.0, 0.0)
	client.start_dodge()
	for i in range(10):
		client.advance(TICK_S)

	# Now try another dodge — should be rejected on both sides equally
	var dodge_input = {
		"seq": 1, "move_direction": Vector2(1.0, 0.0),
		"aim_direction": Vector2.RIGHT, "dodge_pressed": true, "input_seq": 100,
	}
	server.apply_input(dodge_input)
	client.apply_input(dodge_input)
	assert_eq(server.state, client.state,
		"Both sides must agree on state after rejected dodge")
	assert_eq(server.state, PlayerMovementState.WALKING,
		"Dodge on cooldown must not transition to DODGING")
