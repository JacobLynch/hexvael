class_name DamageSystem
extends RefCounted


func apply_damage(target, amount: int, source_info: Dictionary) -> Dictionary:
	# Trust-boundary guard: any future AoE or chain trigger that re-applies to an
	# already-dead target would otherwise fire a second enemy_died/player_died
	# event and tear down view state twice.
	if target.health == null or target.health.is_dead():
		return { "damage_dealt": 0, "killed": false }
	var result = target.health.take_damage(amount)

	var event_data = {
		"target_entity_id": _get_entity_id(target),
		"source_entity_id": source_info.get("source_entity_id", -1),
		"damage": result.damage_dealt,
		"position": target.position,
		"element": source_info.get("element", "physical"),
		"projectile_id": source_info.get("projectile_id", -1),
		"chain_depth": source_info.get("chain_depth", 0),
		"remaining_health": target.health.current,
		"max_health": target.health.max_health,
	}

	if _is_player(target):
		EventBus.player_hit.emit(event_data)
	else:
		EventBus.enemy_hit.emit(event_data)

	if result.killed:
		_handle_death(target, event_data)

	return result


func _handle_death(target, event_data: Dictionary) -> void:
	if _is_player(target):
		target.enter_ghost_state()
		EventBus.player_died.emit(event_data)
	else:
		target.kill()
		EventBus.enemy_died.emit(event_data)


func _is_player(target) -> bool:
	return target is PlayerEntity


func _get_entity_id(target) -> int:
	if target is PlayerEntity:
		return target.player_id
	return target.entity_id
