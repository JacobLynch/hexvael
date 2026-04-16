extends GutTest
## Multiplayer integration test for the respawn + in-flight damage race.
##
## Scenario the hotfix (cc5907e) and subsequent review surfaced:
##   1. Two projectiles are in flight toward the same target player.
##   2. The first projectile lands the killing blow — target enters GHOST state,
##      player_died fires exactly once.
##   3. The second projectile continues through the ghosted target — it MUST NOT
##      re-damage the player, MUST NOT fire a second player_died.
##   4. The ghost timer expires — target respawns at full health in WALKING.
##   5. The full sequence must produce exactly one player_died event.

const TICK_DT: float = 1.0 / 30.0

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var DamageSystemCls = preload("res://simulation/systems/damage_system.gd")
var PlayerEntityScene = preload("res://simulation/entities/player_entity.tscn")


func _make_killing_projectile(system: ProjectileSystem, origin: Vector2,
		owner: int, input_seq: int, damage: int) -> ProjectileEntity:
	var proj = system.spawn_authoritative(
		owner, ProjectileType.Id.TEST, origin, Vector2.RIGHT, input_seq)
	# Duplicate params so we can mutate damage/grace without affecting the shared .tres
	proj.params = proj.params.duplicate()
	proj.params.damage = damage
	proj.params.spawn_grace = 0.0
	proj.spawn_grace_remaining = 0.0
	return proj


func test_respawn_with_in_flight_projectile():
	var projectile_system: ProjectileSystem = ProjectileSystemCls.new()
	var damage_system = DamageSystemCls.new()
	projectile_system.set_damage_system(damage_system)
	add_child_autofree(projectile_system)

	var shooter_id: int = 1
	var target: PlayerEntity = PlayerEntityScene.instantiate()
	add_child_autofree(target)
	target.initialize(2, Vector2(100, 0))
	# Server-authoritative respawn is OFF for this entity — _advance_ghost
	# should respawn via ghost_timer expiration.
	target.server_authoritative_respawn = false

	# Projectile 1 at x=80 — one tick at 500 px/s (~16.67 px/tick) won't reach.
	# Speed is data-driven via params (default 600); use duplicated params at 600.
	# After 1 tick at 600 px/s, moves 20 px: 80 -> 100 hits target at x=100.
	var proj1: ProjectileEntity = _make_killing_projectile(
		projectile_system, Vector2(80, 0), shooter_id, 1, 100)  # one-shot kill
	proj1.params.speed = 600.0

	# Projectile 2 at x=0 — needs ~5 ticks to reach the target.
	var proj2: ProjectileEntity = _make_killing_projectile(
		projectile_system, Vector2(0, 0), shooter_id, 2, 100)
	proj2.params.speed = 600.0

	# GDScript lambdas capture primitives by value, so int counters won't
	# survive `+= 1` inside the closure. A Dictionary is a reference type —
	# the lambda captures the reference, mutations land on the outer dict.
	var counts: Dictionary = {"died": 0, "hit": 0}
	var counter_died := func(_e: Dictionary) -> void:
		counts["died"] += 1
	var counter_hit := func(_e: Dictionary) -> void:
		counts["hit"] += 1
	EventBus.player_died.connect(counter_died)
	EventBus.player_hit.connect(counter_hit)

	# --- Tick 1: projectile 1 hits target, target enters GHOST.
	projectile_system.advance(TICK_DT, [target], [])
	target.advance(TICK_DT)
	assert_eq(target.state, PlayerMovementState.GHOST,
		"target must enter GHOST after lethal hit")
	assert_eq(target.health.current, 0)
	assert_eq(counts["died"], 1, "player_died fires exactly once on first kill")
	assert_eq(counts["hit"], 1, "player_hit fires exactly once for the killing blow")

	# --- Ticks 2–6: projectile 2 travels through the target. Ghost players
	# are skipped by projectile collision (projectile_entity.gd:104-107), so
	# proj2 must NOT despawn with PLAYER reason and must NOT re-emit any hit
	# or death events.
	for _i in range(5):
		projectile_system.advance(TICK_DT, [target], [])
		target.advance(TICK_DT)

	assert_eq(counts["died"], 1,
		"second in-flight projectile must not fire a second player_died on the ghost")
	assert_eq(counts["hit"], 1,
		"second in-flight projectile must not fire a second player_hit on the ghost")
	assert_eq(target.state, PlayerMovementState.GHOST,
		"target remains ghost while timer runs")

	# --- Advance through remaining ghost duration in tick-sized steps so
	# _advance_ghost converges exactly like a server tick loop would.
	var remaining: float = target.ghost_timer + 0.05
	var steps: int = int(ceil(remaining / TICK_DT))
	for _i in range(steps):
		target.advance(TICK_DT)

	assert_eq(target.state, PlayerMovementState.WALKING,
		"ghost_timer expiration must respawn to WALKING")
	assert_eq(target.health.current, target.health.max_health,
		"respawn must restore health to max")
	assert_eq(counts["died"], 1,
		"entire sequence produces exactly one player_died event")
	assert_eq(counts["hit"], 1,
		"entire sequence produces exactly one player_hit event")

	EventBus.player_died.disconnect(counter_died)
	EventBus.player_hit.disconnect(counter_hit)
