class_name WallBump
extends Node2D

const VELOCITY_THRESHOLD: float = 40.0  # ignore sub-threshold touches

var _camera_rig: CameraRig


func _ready():
	EventBus.player_collided.connect(_on_collided)


func initialize(camera_rig: CameraRig) -> void:
	_camera_rig = camera_rig


func _on_collided(event: Dictionary):
	var vel: Vector2 = event["velocity"]
	if vel.length() < VELOCITY_THRESHOLD:
		return
	_spawn_burst(event["position"], event["normal"])
	if _camera_rig != null:
		_camera_rig.add_shake(1.5, 0.08)


func _spawn_burst(pos: Vector2, normal: Vector2) -> void:
	var particles = CPUParticles2D.new()
	particles.position = pos
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 5
	particles.lifetime = 0.25
	particles.explosiveness = 1.0
	particles.initial_velocity_min = 30.0
	particles.initial_velocity_max = 60.0
	particles.direction = normal
	particles.spread = 30.0
	particles.gravity = Vector2(0, 0)
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 3.0
	particles.color = Color(0.8, 0.75, 0.6, 0.7)
	add_child(particles)
	await get_tree().create_timer(particles.lifetime + 0.1).timeout
	particles.queue_free()


func _exit_tree():
	if EventBus.player_collided.is_connected(_on_collided):
		EventBus.player_collided.disconnect(_on_collided)
