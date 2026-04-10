class_name FootstepDust
extends Node2D

const STEP_DISTANCE: float = 24.0

var _distance_accum: Dictionary = {}  # entity_id -> accumulated px


func _ready():
	EventBus.player_moved.connect(_on_player_moved)


func _on_player_moved(event: Dictionary):
	var entity_id: int = event["entity_id"]
	var vel: Vector2 = event["velocity"]
	var step = vel.length() * get_process_delta_time()
	_distance_accum[entity_id] = _distance_accum.get(entity_id, 0.0) + step
	if _distance_accum[entity_id] >= STEP_DISTANCE:
		_distance_accum[entity_id] = 0.0
		_spawn_puff(event["position"])


func _spawn_puff(pos: Vector2) -> void:
	var particles = CPUParticles2D.new()
	particles.position = pos
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 4
	particles.lifetime = 0.3
	particles.explosiveness = 1.0
	particles.initial_velocity_min = 8.0
	particles.initial_velocity_max = 16.0
	particles.direction = Vector2.UP
	particles.spread = 40.0
	particles.gravity = Vector2(0, 0)
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 2.5
	particles.color = Color(0.7, 0.7, 0.65, 0.5)
	add_child(particles)
	# Clean up after lifetime elapses
	await get_tree().create_timer(particles.lifetime + 0.1).timeout
	particles.queue_free()


func _exit_tree():
	if EventBus.player_moved.is_connected(_on_player_moved):
		EventBus.player_moved.disconnect(_on_player_moved)
