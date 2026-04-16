# godot/view/effects/damage_number_spawner.gd
extends Node

var DamageNumberScene: PackedScene = preload("res://view/effects/damage_number.tscn")
var _parent: Node2D = null


func initialize(parent: Node2D) -> void:
	_parent = parent
	EventBus.enemy_hit.connect(_on_hit)
	EventBus.player_hit.connect(_on_hit)


func _on_hit(event: Dictionary) -> void:
	var damage: int = event.get("damage", 0)
	if damage <= 0:
		return

	var pos: Vector2 = event.get("position", Vector2.ZERO)
	# Add slight random offset so multiple hits don't stack
	pos += Vector2((randf() - 0.5) * 20, (randf() - 0.5) * 10)

	var number = DamageNumberScene.instantiate()
	number.text = str(damage)
	number.position = pos
	_parent.add_child(number)


func _exit_tree() -> void:
	if EventBus.enemy_hit.is_connected(_on_hit):
		EventBus.enemy_hit.disconnect(_on_hit)
	if EventBus.player_hit.is_connected(_on_hit):
		EventBus.player_hit.disconnect(_on_hit)
