extends GutTest
## Semi-integration test for the fire round-trip message flow.
##
## We do NOT spin up a real NetServer (its _ready() opens a TCP listener, which
## is unreliable in a headless test runner).  Instead we replicate the exact code
## path that _server_tick() and _handle_binary_message() execute:
##
##   1. Server side: InputBuffer → ProjectileSpawnRouter.handle_fire → spawn_events list
##   2. Encode the spawn event to PROJECTILE_SPAWNED bytes (same as NetServer does)
##   3. Client side: NetClient._handle_binary_message(bytes) → adopt_authoritative / fresh spawn
##
## This covers the full encode/decode round-trip plus the projection-system adoption
## logic without relying on WebSocket I/O, which cannot be reliably driven synchronously
## in a headless GUT session.

const PLAYER_ID := 1
const INPUT_SEQ := 7
const TICK     := 1

var NetClientScript = preload("res://simulation/network/net_client.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_server_side() -> Dictionary:
	## Returns a dict with the server-side objects needed for one fire tick.
	var player: PlayerEntity = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(PLAYER_ID, Vector2(1200.0, 800.0))

	var ps := ProjectileSystem.new()
	add_child_autofree(ps)

	var history := PlayerPositionHistory.new()
	var buffer  := InputBuffer.new()

	return {
		"player":  player,
		"ps":      ps,
		"history": history,
		"buffer":  buffer,
	}


func _run_server_fire_tick(srv: Dictionary, aim: Vector2) -> Array:
	## Replicates the input-processing section of NetServer._server_tick() for
	## one player firing one input.  Returns the spawn_events array (same as the
	## server collects before broadcasting).
	var player: PlayerEntity = srv["player"]
	var ps: ProjectileSystem  = srv["ps"]
	var history: PlayerPositionHistory = srv["history"]
	var buffer: InputBuffer   = srv["buffer"]

	# Record position (NetServer does this at start of each tick)
	history.record(PLAYER_ID, TICK, player.position)

	# Build and queue the fire input
	var input := {
		"type":          MessageTypes.Binary.PLAYER_INPUT,
		"tick":          TICK,
		"move_direction": Vector2.ZERO,
		"aim_direction": aim,
		"action_flags":  MessageTypes.InputActionFlags.FIRE,
		"input_seq":     INPUT_SEQ,
	}
	buffer.add_input(PLAYER_ID, input)

	# Drain and process exactly as _server_tick() does
	var spawn_events: Array = []
	var inputs: Array = buffer.drain_inputs_for_player(PLAYER_ID)
	for inp in inputs:
		player.apply_input(inp)
		var context := {
			"authoritative":    true,
			"rtt_ms":           0,
			"position_history": history,
			"tick":             TICK,
			"spawn_events":     spawn_events,
		}
		ProjectileSpawnRouter.handle_fire(player, inp, ps, context)

	return spawn_events


func _make_client(client_ps: ProjectileSystem) -> NetClient:
	## Create a NetClient with its projectile system attached.
	## We also set _local_player_id so adopt_authoritative knows who the local
	## player is (used internally but does not affect the adoption logic here).
	var client: NetClient = NetClientScript.new()
	add_child_autofree(client)
	client._local_player_id = PLAYER_ID
	client.set_projectile_system(client_ps)
	return client


# ---------------------------------------------------------------------------
# Test 1 – predicted → adopted
# The client fired locally (spawn_predicted) before the server confirmed.
# When the PROJECTILE_SPAWNED message arrives, the predicted entry must be
# replaced by an authoritative one with id > 0.
# ---------------------------------------------------------------------------

func test_fire_input_results_in_adopted_authoritative_projectile():
	var srv := _make_server_side()
	var spawn_events := _run_server_fire_tick(srv, Vector2.RIGHT)

	assert_eq(spawn_events.size(), 1, "server must produce exactly one spawn event")

	# Client side: pre-existing predicted projectile for this input_seq
	var client_ps := ProjectileSystem.new()
	add_child_autofree(client_ps)

	# spawn_predicted stores the projectile under id = -INPUT_SEQ
	client_ps.spawn_predicted(PLAYER_ID, ProjectileType.Id.TEST,
		Vector2(1200.0, 800.0), Vector2.RIGHT, INPUT_SEQ)
	assert_true(client_ps.projectiles.has(-INPUT_SEQ),
		"predicted projectile must exist before adopt")

	var client := _make_client(client_ps)

	# Encode the server's spawn event exactly as NetServer._server_tick() does
	var spawn_msg: PackedByteArray = NetMessage.encode_projectile_spawned(spawn_events[0])
	assert_eq(spawn_msg.size(), MessageTypes.Layout.PROJECTILE_SPAWNED_SIZE,
		"encoded message must be the expected size")

	# Deliver to the client's binary handler (same path a real WebSocket packet
	# would take)
	client._handle_binary_message(spawn_msg)

	# The predicted entry must be gone and an authoritative one must be present
	assert_false(client_ps.projectiles.has(-INPUT_SEQ),
		"predicted entry must be removed after adoption")

	var auth_id: int = spawn_events[0]["projectile_id"]
	assert_true(client_ps.projectiles.has(auth_id),
		"authoritative projectile must be present under the server-assigned id")

	var adopted: ProjectileEntity = client_ps.projectiles[auth_id]
	assert_not_null(adopted, "adopted entity must not be null")
	assert_false(adopted.is_predicted, "adopted projectile must not be flagged as predicted")
	assert_eq(adopted.owner_player_id, PLAYER_ID,
		"adopted projectile must carry the correct owner")


# ---------------------------------------------------------------------------
# Test 2 – no prediction, fresh spawn
# Client never fired locally (e.g. remote player or prediction was pruned).
# The PROJECTILE_SPAWNED message must produce a fresh authoritative entry.
# ---------------------------------------------------------------------------

func test_fire_round_trip_without_prediction_spawns_fresh_authoritative():
	var srv := _make_server_side()
	var spawn_events := _run_server_fire_tick(srv, Vector2(0.0, -1.0))  # aim up

	assert_eq(spawn_events.size(), 1, "server must produce exactly one spawn event")

	# Client has no predicted projectile for this input_seq
	var client_ps := ProjectileSystem.new()
	add_child_autofree(client_ps)
	assert_eq(client_ps.projectiles.size(), 0,
		"client must start with no projectiles")

	var client := _make_client(client_ps)

	var spawn_msg: PackedByteArray = NetMessage.encode_projectile_spawned(spawn_events[0])
	client._handle_binary_message(spawn_msg)

	assert_eq(client_ps.projectiles.size(), 1,
		"client must have exactly one projectile after receiving PROJECTILE_SPAWNED")

	var auth_id: int = spawn_events[0]["projectile_id"]
	assert_true(client_ps.projectiles.has(auth_id),
		"projectile must be stored under the authoritative server id")

	var proj: ProjectileEntity = client_ps.projectiles[auth_id]
	assert_false(proj.is_predicted, "fresh remote projectile must not be flagged as predicted")
	assert_eq(proj.owner_player_id, PLAYER_ID,
		"owner must match the server-assigned owner_player_id")
	assert_gt(auth_id, 0, "authoritative id must be positive")


# ---------------------------------------------------------------------------
# Test 3 – encode/decode round-trip preserves all fields
# Guards against silent field corruption in the binary layout that would cause
# the client to adopt under the wrong id or owner.
# ---------------------------------------------------------------------------

func test_projectile_spawned_message_preserves_all_fields_through_codec():
	var event := {
		"projectile_id":   42,
		"type_id":         ProjectileType.Id.TEST,
		"owner_player_id": PLAYER_ID,
		"origin":          Vector2(123.5, 456.75),
		"direction":       Vector2.RIGHT,
		"input_seq":       INPUT_SEQ,
	}
	var bytes: PackedByteArray = NetMessage.encode_projectile_spawned(event)
	var decoded: Dictionary = NetMessage.decode_projectile_spawned(bytes)

	assert_eq(decoded["projectile_id"],   42)
	assert_eq(decoded["type_id"],         ProjectileType.Id.TEST)
	assert_eq(decoded["owner_player_id"], PLAYER_ID)
	assert_almost_eq(decoded["origin"].x, 123.5,  0.01)
	assert_almost_eq(decoded["origin"].y, 456.75, 0.01)
	assert_almost_eq(decoded["direction"].x, 1.0, 0.01)
	assert_almost_eq(decoded["direction"].y, 0.0, 0.01)
	assert_eq(decoded["input_seq"], INPUT_SEQ)
