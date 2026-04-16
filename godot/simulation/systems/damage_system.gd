class_name DamageSystem
extends RefCounted


func apply_damage(target, amount: int, source_info: Dictionary) -> Dictionary:
	var result = target.health.take_damage(amount)

	var entity_id = _get_entity_id(target)
	var event_data = {
		"entity_id": entity_id,  # Primary key for consumers
		"target_entity_id": entity_id,  # Alias for consistency with hit events
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
