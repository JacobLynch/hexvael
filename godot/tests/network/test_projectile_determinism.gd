extends GutTest
## Two-client determinism: both clients receive the same PROJECTILE_SPAWNED bytes
## and must converge to identical projectile positions after N independent ticks.
##
## Pattern: semi-integration without a real WebSocket.
##   1. Server side: build a spawn event via ProjectileSpawnRouter.handle_fire.
##   2. Encode to PROJECTILE_SPAWNED bytes exactly as NetServer does.
##   3. Feed the encoded bytes to BOTH NetClient instances (broadcast simulation).
##   4. Advance each client's ProjectileSystem independently for 20 frames.
##   5. Assert positions are within 1 px.
##
## Client A had a predicted projectile (simulating the firing player).
## Client B had no prediction (simulating a remote observer).
## After adoption/fresh-spawn and 20 independent advance() calls, the dt-independent
## physics must produce the same position on both.

const PLAYER_ID := 1
const INPUT_SEQ := 11
const TICK      := 1

var NetClientScript = preload("res://simulation/network/net_client.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


# ---------------------------------------------------------------------------
# Helpers (reused from test_fire_round_trip.gd pattern)
# ---------------------------------------------------------------------------

func _run_server_fire_tick(aim: Vector2) -> Array:
	## Replicate the server-tick fire path; return spawn_events.
	var player: PlayerEntity = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.initialize(PLAYER_ID, Vector2(1200.0, 800.0))
	player.aim_direction = aim

	var ps    := ProjectileSystem.new()
	add_child_autofree(ps)
	var hist  := PlayerPositionHistory.new()
	var buf   := InputBuffer.new()

	hist.record(PLAYER_ID, TICK, player.position)

	var input := {
		"type":           MessageTypes.Binary.PLAYER_INPUT,
		"tick":           TICK,
		"move_direction": Vector2.ZERO,
		"aim_direction":  aim,
		"action_flags":   MessageTypes.InputActionFlags.FIRE,
		"input_seq":      INPUT_SEQ,
	}
	buf.add_input(PLAYER_ID, input)

	var spawn_events: Array = []
	for inp in buf.drain_inputs_for_player(PLAYER_ID):
		player.apply_input(inp)
		var ctx := {
			"authoritative":    true,
			"rtt_ms":           0,
			"position_history": hist,
			"tick":             TICK,
			"spawn_events":     spawn_events,
			"projectile_type":  "test",
		}
		ProjectileSpawnRouter.handle_fire(player, inp, ps, ctx)
	return spawn_events


func _make_client(client_ps: ProjectileSystem) -> NetClient:
	var client: NetClient = NetClientScript.new()
	add_child_autofree(client)
	client._local_player_id = PLAYER_ID
	client.set_projectile_system(client_ps)
	return client


# ---------------------------------------------------------------------------
# Test — two clients converge on the same spawn event
# ---------------------------------------------------------------------------

func test_two_clients_converge_on_same_spawn_event():
	# --- Server side: produce one spawn event ---
	var aim := Vector2.RIGHT
	var spawn_events := _run_server_fire_tick(aim)
	assert_eq(spawn_events.size(), 1, "server must produce exactly one spawn event")

	var spawn_msg: PackedByteArray = NetMessage.encode_projectile_spawned(spawn_events[0])
	var auth_id: int = spawn_events[0]["projectile_id"]

	# --- Client A: had a predicted projectile for this input (local player) ---
	var ps_a := ProjectileSystem.new()
	add_child_autofree(ps_a)
	ps_a.spawn_predicted(PLAYER_ID, ProjectileType.Id.TEST,
		Vector2(1200.0, 800.0), aim, INPUT_SEQ)
	var client_a := _make_client(ps_a)

	# --- Client B: no prediction (remote observer) ---
	var ps_b := ProjectileSystem.new()
	add_child_autofree(ps_b)
	var client_b := _make_client(ps_b)

	# --- Broadcast: deliver identical PROJECTILE_SPAWNED bytes to both ---
	client_a._handle_binary_message(spawn_msg)
	client_b._handle_binary_message(spawn_msg)

	assert_true(ps_a.projectiles.has(auth_id),
		"client A must hold the authoritative projectile after adoption")
	assert_true(ps_b.projectiles.has(auth_id),
		"client B must hold the authoritative projectile after fresh spawn")

	# --- Advance both independently for 20 frames (simulate rendering at 60 Hz) ---
	# ProjectileSystem.advance() takes a dt; both receive dt = 1/60 each frame.
	# No walls, no enemies, no players — purely testing motion determinism.
	const FRAMES := 20
	const FRAME_DT := 1.0 / 60.0

	for _i in range(FRAMES):
		ps_a.advance(FRAME_DT, [], [])
		ps_b.advance(FRAME_DT, [], [])

	# --- Assert convergence within 1 px ---
	assert_true(ps_a.projectiles.has(auth_id),
		"client A projectile must still be alive after 20 frames")
	assert_true(ps_b.projectiles.has(auth_id),
		"client B projectile must still be alive after 20 frames")

	var pos_a: Vector2 = ps_a.projectiles[auth_id].position
	var pos_b: Vector2 = ps_b.projectiles[auth_id].position
	var dist: float = pos_a.distance_to(pos_b)

	assert_lt(dist, 1.0,
		"both clients must converge to the same position within 1 px (got %.3f px)" % dist)
