extends GutTest
## Unit-level test: ProjectileSpawnRouter.handle_fire uses the rewound shooter
## position, not the current authoritative position.
##
## No WebSocket or NetServer needed.  We directly call handle_fire with a
## crafted PlayerPositionHistory and assert that the resulting spawn origin is
## much closer to the rewound-position calculation than to the current-position
## calculation.
##
## Rewind math for this test:
##   rtt_ms = 100, tick = 103
##   one_way_ms = 50
##   rewind_ticks = round(50 / TICK_INTERVAL_MS) = round(50 / 33.33) = round(1.5) = 2
##   lookup(42, 101) = (133, 500)
##   origin = (133+40, 500) = (173, 500)   [spawn_offset = 40]
##   fast-forward 0.05 s at 600 px/s = +30 px
##   expected spawn_events[0]["origin"].x ≈ 203
##
##   current-position-based (wrong) would give: 200 + 40 + 30 = 270
##   rewound-position-based (correct) gives:    133 + 40 + 30 = 203

var PlayerPositionHistory = preload("res://simulation/systems/player_position_history.gd")
var ProjectileSystemCls   = preload("res://simulation/systems/projectile_system.gd")
var ProjectileType        = preload("res://shared/projectiles/projectile_types.gd")
var PlayerEntityScene     = preload("res://simulation/entities/player_entity.tscn")


func test_server_rewind_uses_past_shooter_position():
	var sys: ProjectileSystem = ProjectileSystemCls.new()
	add_child_autofree(sys)
	var history := PlayerPositionHistory.new()

	# Shooter moves from (100, 500) at tick 100 to (200, 500) at tick 103.
	history.record(42, 100, Vector2(100, 500))
	history.record(42, 101, Vector2(133, 500))
	history.record(42, 102, Vector2(166, 500))
	history.record(42, 103, Vector2(200, 500))

	var player: PlayerEntity = PlayerEntityScene.instantiate()
	add_child_autofree(player)
	player.player_id = 42
	player.position = Vector2(200, 500)   # current authoritative position
	player.aim_direction = Vector2.RIGHT

	var spawn_events: Array = []
	# 100 ms RTT → 50 ms one-way → round(50/33.3) = ~2 ticks rewind from tick 103 → tick 101
	# Which maps to (133, 500)
	var context := {
		"authoritative":    true,
		"rtt_ms":           100,
		"position_history": history,
		"tick":             103,
		"spawn_events":     spawn_events,
	}
	var input := {
		"action_flags": MessageTypes.InputActionFlags.FIRE,
		"input_seq":    1,
	}
	ProjectileSpawnRouter.handle_fire(player, input, sys, context)

	assert_eq(spawn_events.size(), 1,
		"handle_fire must produce exactly one spawn event")

	var origin: Vector2 = spawn_events[0]["origin"]

	# Expected: rewound pos (133, 500) + spawn_offset (40, 0) + fast-forward (rtt/2000 * 600 = 30, 0)
	#         = (203, 500)
	var rewound_based_x := 133.0 + 40.0 + 30.0   # = 203
	var current_based_x  := 200.0 + 40.0 + 30.0  # = 270

	var err_rewound: float = absf(origin.x - rewound_based_x)
	var err_current: float = absf(origin.x - current_based_x)

	assert_lt(err_rewound, err_current,
		("server must rewind shooter position, not use current: " +
		 "origin.x=%.2f, err_rewound=%.2f, err_current=%.2f") % [
		 	origin.x, err_rewound, err_current])
