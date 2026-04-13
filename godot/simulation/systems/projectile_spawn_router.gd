class_name ProjectileSpawnRouter

static func handle_fire(
		player: PlayerEntity,
		input: Dictionary,
		projectile_system: ProjectileSystem,
		context: Dictionary) -> void:

	var flags: int = input.get("action_flags", 0)
	if (flags & MessageTypes.InputActionFlags.FIRE) == 0:
		return
	if not projectile_system.can_fire(player.player_id):
		return

	var aim: Vector2 = player.aim_direction
	# Allow context to override projectile type (for weapons, abilities, etc.)
	# Default to "test" for backwards compatibility
	var type_name: String = context.get("projectile_type", "test")
	var type_id: int = ProjectileType.get_type_id(type_name)
	if type_id < 0:
		push_error("ProjectileSpawnRouter: unknown type '%s'" % type_name)
		return
	var params: ProjectileParams = ProjectileType.get_params(type_id)

	if context.get("authoritative", false):
		var rtt_ms: int = context["rtt_ms"]
		var history: PlayerPositionHistory = context["position_history"]
		var tick: int = context["tick"]
		var rewind_ticks: int = int(round((rtt_ms / 2.0) / MessageTypes.TICK_INTERVAL_MS))
		var rewound_pos: Vector2 = history.lookup(player.player_id, tick - rewind_ticks)
		var origin: Vector2 = rewound_pos + aim * params.spawn_offset
		var proj: ProjectileEntity = projectile_system.spawn_authoritative(
			player.player_id, type_id, origin, aim, input["input_seq"])
		proj.advance(rtt_ms / 2000.0, projectile_system.get_walls(), [], [])
		context["spawn_events"].append({
			"projectile_id": proj.projectile_id,
			"type_id": type_id,
			"owner_player_id": player.player_id,
			"origin": proj.position,   # server-now, post fast-forward
			"direction": aim,
			"input_seq": input["input_seq"],
			"queue_time_ms": Time.get_ticks_msec(),
		})
	else:
		var origin := player.position + aim * params.spawn_offset
		projectile_system.spawn_predicted(
			player.player_id, type_id, origin, aim, input["input_seq"])

	projectile_system.start_cooldown(player.player_id, type_id)
