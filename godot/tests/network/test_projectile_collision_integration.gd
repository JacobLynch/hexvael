extends GutTest
## Semi-integration tests for projectile wall and self-collision despawn flow.
##
## These tests use the direct-call semi-integration approach: projectiles are
## spawned via spawn_authoritative() directly (bypassing the fire round-trip)
## so collision scenarios can be set up precisely.  After each server-side
## advance() call we encode any despawn events and deliver them to a NetClient's
## _handle_binary_message(), verifying the client removes the projectile.
##
## The Task 27 test already covers the spawn/adopt round-trip.  These tests
## focus on the despawn path: WALL and SELF reasons propagate from the
## server ProjectileSystem through the wire to the client ProjectileSystem.

const PLAYER_ID  := 1
const TICK_DT    := 1.0 / 30.0   # 30 Hz server tick

var NetClientScript = preload("res://simulation/network/net_client.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_server_ps() -> ProjectileSystem:
	var ps := ProjectileSystem.new()
	add_child_autofree(ps)
	return ps


func _make_client_ps_with_proj(proj_id: int, origin: Vector2, dir: Vector2) -> ProjectileSystem:
	## Create a client-side ProjectileSystem that already holds an
	## authoritative projectile (as if PROJECTILE_SPAWNED was received).
	var ps := ProjectileSystem.new()
	add_child_autofree(ps)
	ps.adopt_authoritative(
		proj_id, PLAYER_ID, ProjectileType.Id.TEST,
		origin, dir, 1, 0)
	return ps


func _make_client(client_ps: ProjectileSystem) -> NetClient:
	var client: NetClient = NetClientScript.new()
	add_child_autofree(client)
	client._local_player_id = PLAYER_ID
	client.set_projectile_system(client_ps)
	return client


func _pump_until_despawn(
		server_ps: ProjectileSystem,
		players: Array,
		max_ticks: int) -> Dictionary:
	## Advance the server ProjectileSystem up to max_ticks times.
	## Returns the first despawn entry dict {"id", "reason", "position"},
	## or an empty dict if no despawn occurred within max_ticks.
	for _i in range(max_ticks):
		var despawns: Array = server_ps.advance(TICK_DT, players, [])
		if despawns.size() > 0:
			return despawns[0]
	return {}


func _deliver_despawn(client: NetClient, despawn: Dictionary) -> void:
	## Encode a despawn dict (as returned by advance()) and deliver it to
	## the client's binary handler — identical to the real server broadcast path.
	var bytes: PackedByteArray = NetMessage.encode_projectile_despawned({
		"projectile_id": despawn["id"],
		"reason":        despawn["reason"],
		"position":      despawn["position"],
	})
	client._handle_binary_message(bytes)


# ---------------------------------------------------------------------------
# Test 1 — projectile is destroyed when it reaches a wall
# ---------------------------------------------------------------------------

func test_projectile_destroyed_on_wall_hit():
	## Server-side: spawn projectile aimed right; wall to the right at x=1100.
	## Client: receives the PROJECTILE_DESPAWNED message and removes the entry.

	# Wall from x=1100 to x=1120, full-height slab.
	var wall := Rect2(Vector2(1100.0, 0.0), Vector2(20.0, 1600.0))

	# Server projectile system with wall registered.
	var srv_ps := _make_server_ps()
	srv_ps.set_walls([wall])

	# Spawn authoritative projectile: origin (1000, 800) aimed right.
	# Wall is 100 px to the right.  Radius=6; AABB overlap fires when
	# pos.x > 1094.  Speed=600 px/s, 30 Hz -> 20 px/tick.
	# Ticks to hit: ceil((1094-1000)/20) = ceil(4.7) = 5 ticks.
	var origin := Vector2(1000.0, 800.0)
	var srv_proj := srv_ps.spawn_authoritative(
		PLAYER_ID, ProjectileType.Id.TEST, origin, Vector2.RIGHT, 1)
	var proj_id: int = srv_proj.projectile_id

	# Client receives the spawn and holds an authoritative copy.
	var cli_ps   := _make_client_ps_with_proj(proj_id, origin, Vector2.RIGHT)
	var client   := _make_client(cli_ps)
	assert_true(cli_ps.projectiles.has(proj_id),
		"client must hold the projectile before wall hit")

	# Pump server until despawn (no players; test wall only).
	var despawn := _pump_until_despawn(srv_ps, [], 20)
	assert_false(despawn.is_empty(),
		"server must despawn projectile within 20 ticks")
	assert_eq(despawn["reason"], ProjectileEntity.DespawnReason.WALL,
		"despawn reason must be WALL")
	assert_eq(despawn["id"], proj_id,
		"despawn must reference the correct projectile id")

	# Deliver despawn to client.
	_deliver_despawn(client, despawn)

	# Client must have removed the projectile.
	assert_false(cli_ps.projectiles.has(proj_id),
		"client must remove projectile after receiving PROJECTILE_DESPAWNED(WALL)")


# ---------------------------------------------------------------------------
# Test 2 — owner self-collision fires after spawn grace expires
# ---------------------------------------------------------------------------

func test_projectile_self_collision_after_grace():
	## Server-side: spawn projectile aimed right; advance past grace period
	## (0.10 s = 3 ticks at 30 Hz) without the owner in the collision list.
	## Then teleport the owner into the projectile's path and pump one more tick.
	## The despawn reason must be SELF and the client must remove the projectile.

	# Server projectile system, no walls.
	var srv_ps := _make_server_ps()

	# Spawn authoritative projectile: origin (1200, 800) aimed right.
	var origin := Vector2(1200.0, 800.0)
	var srv_proj := srv_ps.spawn_authoritative(
		PLAYER_ID, ProjectileType.Id.TEST, origin, Vector2.RIGHT, 2)
	var proj_id: int = srv_proj.projectile_id

	# Client holds an authoritative copy.
	var cli_ps  := _make_client_ps_with_proj(proj_id, origin, Vector2.RIGHT)
	var client  := _make_client(cli_ps)
	assert_true(cli_ps.projectiles.has(proj_id),
		"client must hold the projectile before self-hit")

	# Pump 4 ticks WITHOUT the owner present so grace expires but no collision.
	# spawn_grace = 0.10s.  At 30 Hz, tick_dt = 1/30 ≈ 0.03333.  Three ticks of
	# 1/30 sum to 0.09999... (float) — still > 0.  Four ticks is -0.0333 — safely
	# negative, grace expired.  After 4 ticks: x = 1200 + 600*(4/30) = 1280.
	for _i in range(4):
		var d := srv_ps.advance(TICK_DT, [], [])
		assert_eq(d.size(), 0, "no despawn expected while pumping grace period")

	# Confirm projectile exists and grace has expired.
	assert_true(srv_ps.projectiles.has(proj_id),
		"projectile must still be alive after grace ticks")
	var proj: ProjectileEntity = srv_ps.projectiles[proj_id]
	assert_true(proj.spawn_grace_remaining < 0.01,
		"spawn_grace_remaining must be expired after 4 ticks (got %.6f)" % proj.spawn_grace_remaining)

	# Spin up an owner player entity and place it 10 px ahead of the projectile.
	# On the next tick, the projectile advances 20 px (600 px/s / 30 Hz); player
	# is 10 px ahead of the current position, so after motion the distance = 10 px
	# < combined radius (6+6=12 px) -> SELF collision.
	var player: PlayerEntity = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.player_id = PLAYER_ID
	player.position = proj.position + Vector2(10.0, 0.0)

	# Pump one more tick WITH the owner in the collision list.
	var despawn := _pump_until_despawn(srv_ps, [player], 5)
	assert_false(despawn.is_empty(),
		"server must despawn projectile on self-collision within 5 ticks")
	assert_eq(despawn["reason"], ProjectileEntity.DespawnReason.SELF,
		"despawn reason must be SELF")
	assert_eq(despawn["id"], proj_id,
		"despawn must reference the correct projectile id")

	# Deliver despawn to client.
	_deliver_despawn(client, despawn)

	# Client must have removed the projectile.
	assert_false(cli_ps.projectiles.has(proj_id),
		"client must remove projectile after receiving PROJECTILE_DESPAWNED(SELF)")
