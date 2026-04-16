class_name HealthComponent
extends RefCounted

var current: int
var max_health: int

func _init(max_hp: int) -> void:
	max_health = max_hp
	current = max_hp

func take_damage(amount: int) -> Dictionary:
	# Guard against negative damage (would heal) and no-op at zero — keeps the
	# contract "take_damage never increases current".
	if amount <= 0:
		return { "damage_dealt": 0, "killed": current <= 0 }
	var actual = mini(amount, current)
	current -= actual
	return { "damage_dealt": actual, "killed": current <= 0 }

func heal(amount: int) -> int:
	var actual = mini(amount, max_health - current)
	current += actual
	return actual

func is_dead() -> bool:
	return current <= 0

func to_dict() -> Dictionary:
	return { "current": current, "max": max_health }

func from_dict(data: Dictionary) -> void:
	current = data.get("current", max_health)
	max_health = data.get("max", max_health)
