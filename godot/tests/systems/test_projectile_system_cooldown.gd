extends GutTest

var ProjectileSystemCls = preload("res://simulation/systems/projectile_system.gd")
var ProjectileType = preload("res://shared/projectiles/projectile_types.gd")

func test_can_fire_defaults_true():
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	assert_true(sys.can_fire(42))

func test_start_cooldown_blocks_can_fire():
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	sys.start_cooldown(42)
	assert_false(sys.can_fire(42))

func test_tick_cooldowns_decrements():
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	sys.start_cooldown(42)
	sys.tick_cooldowns(0.30)  # longer than 0.20 fire_cooldown
	assert_true(sys.can_fire(42))

func test_cooldown_is_per_player():
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	sys.start_cooldown(42)
	assert_false(sys.can_fire(42))
	assert_true(sys.can_fire(99))


## --- Credit-carry (fixes the hold-to-fire every-other-block bug) -----------
## The fire_cooldown (0.2s for TEST) is not a multiple of the 30 Hz tick_dt
## (0.0333s). Without credit-carry, the drain overshoots 0 on one tick and
## the old max(0, ...) clamp threw away that overshoot, so the effective
## cadence on the server rounded up to ceil(0.2/0.0333) = 7 ticks = 233.3ms
## — which doesn't match the client's wall-clock 200ms cadence. The residual
## must carry into the next cycle so sustained fire averages the configured
## rate exactly.

func test_negative_residual_carries_into_next_cooldown():
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	sys.start_cooldown(42)                       # cooldown = 0.2
	sys.tick_cooldowns(0.25)                     # over-drains to -0.05
	assert_true(sys.can_fire(42))
	sys.start_cooldown(42)                       # -0.05 + 0.2 = 0.15, NOT 0.2
	assert_almost_eq(sys._fire_cooldown[42], 0.15, 0.0001,
		"next start_cooldown must fold the previous negative residual in")


func test_cooldown_stops_draining_once_expired():
	# Without this, a player who doesn't fire for a long time would accumulate
	# unbounded negative cooldown and then be able to fire many times in a row
	# once they do press fire.
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	sys.start_cooldown(42)                       # 0.2
	sys.tick_cooldowns(0.25)                     # -> -0.05 (one overshoot drain)
	sys.tick_cooldowns(10.0)                     # idle for 10s
	sys.tick_cooldowns(10.0)                     # and more
	# Residual must stay at the single-drain overshoot, not -20.05.
	assert_almost_eq(sys._fire_cooldown[42], -0.05, 0.0001,
		"drain must halt at <= 0 so residual is bounded by one dt")


func test_tolerance_accepts_fire_up_to_one_tick_early():
	# Without tolerance, server's 33ms grain can't exactly match client's
	# finer cadence — shots arriving "half a tick early" get rejected on
	# alternating tries, and the orphaned predictions eventually time out
	# on the client and vanish. The tolerance parameter lets the server
	# accept those shots.
	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)
	sys.start_cooldown(42)                       # cooldown = 0.2
	sys.tick_cooldowns(0.18)                     # drain to 0.02 (not yet zero)
	assert_false(sys.can_fire(42),
		"strict check must reject fires while cooldown > 0")
	assert_true(sys.can_fire(42, 0.0333),
		"tolerance of one tick must accept shots just shy of ready")


func test_server_tolerance_accepts_every_shot_of_sustained_client_fire():
	# Regression for the "every 2nd or 3rd projectile vanishes when holding
	# fire" bug. A 60fps client firing every 15 frames (250ms) sends its
	# inputs to a 30Hz server; due to tick-grain alignment, roughly every
	# other shot lands on a server tick where cooldown is still +0.0167s,
	# which the strict check would reject. The server's one-tick tolerance
	# must accept every such shot so the client's predicted projectile
	# finds its adoption.
	#
	# Uses FROST_BOLT (fire_cooldown=0.25s) specifically: 0.25 / tick_dt =
	# 7.5 is fractional, which is exactly when the alternation manifests.
	# TEST params use 0.2s = 6 ticks exactly and wouldn't exercise the bug.
	const TICK_DT: float = 1.0 / 30.0
	const FRAME_DT: float = 1.0 / 60.0
	const FRAMES_PER_FIRE: int = 15              # 250ms cadence on 60fps client
	const N_CLIENT_FIRES: int = 20
	var type_id: int = ProjectileType.Id.FROST_BOLT

	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)

	var fires_accepted: int = 0
	var client_frame: int = 0
	var next_server_tick_at_s: float = TICK_DT
	var elapsed: float = 0.0
	var pending_arrivals: Array = []
	# Cap iterations — if the fix regresses, we shouldn't hang the test run.
	var max_frames: int = N_CLIENT_FIRES * FRAMES_PER_FIRE + 60

	while fires_accepted < N_CLIENT_FIRES and client_frame < max_frames:
		elapsed += FRAME_DT
		client_frame += 1

		if client_frame % FRAMES_PER_FIRE == 0:
			pending_arrivals.append(elapsed)

		while next_server_tick_at_s <= elapsed:
			sys.tick_cooldowns(TICK_DT)
			while pending_arrivals.size() > 0 and pending_arrivals[0] <= next_server_tick_at_s:
				pending_arrivals.pop_front()
				if sys.can_fire(1, TICK_DT):
					sys.start_cooldown(1, type_id)
					fires_accepted += 1
			next_server_tick_at_s += TICK_DT

	assert_eq(fires_accepted, N_CLIENT_FIRES,
		"every client fire must be accepted — no shots lost to tick-grain alternation")


func test_sustained_fire_matches_configured_rate():
	# Simulate 30 Hz server firing repeatedly, sending one FIRE input at the
	# earliest tick the cooldown permits. Over many fires, the total elapsed
	# time must equal N * fire_cooldown — i.e. the residual credit makes up
	# for tick-granularity rounding. Without credit-carry this test fails by
	# a ratio of ceil(cooldown/dt)*dt / cooldown (≈ +17% on 0.2s @ 30Hz).
	const TICK_DT: float = 1.0 / 30.0
	const FIRE_COOLDOWN: float = 0.2          # TEST projectile
	const N_FIRES: int = 20

	var sys = ProjectileSystemCls.new()
	add_child_autofree(sys)

	var fire_count: int = 0
	var elapsed: float = 0.0
	# Run a long pump — how long doesn't matter, only how many fires happen.
	# Cap iterations to avoid infinite loop on regression.
	for _i in range(600):
		if sys.can_fire(1):
			sys.start_cooldown(1)
			fire_count += 1
			if fire_count >= N_FIRES:
				break
		sys.tick_cooldowns(TICK_DT)
		elapsed += TICK_DT

	assert_eq(fire_count, N_FIRES, "test must complete N fires")
	# Expected: exactly (N-1) * cooldown between fire 1 and fire N.
	var expected: float = (N_FIRES - 1) * FIRE_COOLDOWN
	# Tolerance: one tick (the last fire may land at the tick boundary either
	# just before or just after the ideal time; credit-carry keeps the AVERAGE
	# on target but individual fires jitter by up to one tick).
	assert_almost_eq(elapsed, expected, TICK_DT,
		"sustained cadence must match N * fire_cooldown within one tick")
