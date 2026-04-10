class_name WallBump
extends Node2D

const VELOCITY_THRESHOLD: float = 40.0  # ignore sub-threshold touches

var _camera_rig: CameraRig
var _net_client: NetClient


func _ready():
	EventBus.player_collided.connect(_on_collided)


func initialize(camera_rig: CameraRig, net_client: NetClient) -> void:
	_camera_rig = camera_rig
	_net_client = net_client


func _on_collided(event: Dictionary):
	var vel: Vector2 = event["velocity"]
	if vel.length() < VELOCITY_THRESHOLD:
		return
	_spawn_burst(event["position"], event["normal"])
	# Only shake the local camera for the local player's collisions.
	# Remote players don't run sim locally today, but this guard prevents
	# incorrect shaking if that ever changes.
	if _camera_rig != null and _net_client != null and event["entity_id"] == _net_client.get_local_player_id():
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
	particles.finished.connect(particles.queue_free)
	add_child(particles)


func _exit_tree():
	if EventBus.player_collided.is_connected(_on_collided):
		EventBus.player_collided.disconnect(_on_collided)
