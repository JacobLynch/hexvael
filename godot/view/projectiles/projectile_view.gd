class_name ProjectileView
extends Node2D

@export var projectile_system_path: NodePath

var _projectile_system: ProjectileSystem
var _net_client: NetClient  # For looking up interpolated entity positions
var _visuals: Dictionary = {}   # projectile_id -> Node2D
var _local_player_id: int = -1


func set_local_player_id(id: int) -> void:
	_local_player_id = id


func _ready() -> void:
	# Support two instantiation paths:
	# 1. Scene-instanced with projectile_system_path exported in the inspector
	# 2. Code-instanced via ProjectileView.new() with _projectile_system set directly
	#    before add_child() (see client_main.gd)
	if _projectile_system == null and not projectile_system_path.is_empty():
		_projectile_system = get_node(projectile_system_path)
	assert(_projectile_system != null,
		"ProjectileView: _projectile_system must be set before add_child, " +
		"or projectile_system_path must be exported")
	EventBus.projectile_spawned.connect(_on_spawned)
	EventBus.projectile_despawned.connect(_on_despawned)
	EventBus.projectile_adopted.connect(_on_adopted)


func _on_adopted(event: Dictionary) -> void:
	# Predicted projectile was rekeyed to its authoritative id.
	# Move the visual's _visuals entry to match.
	var temp_id: int = event["temp_id"]
	var new_id: int = event["new_id"]
	if not _visuals.has(temp_id):
		return
	_visuals[new_id] = _visuals[temp_id]
	_visuals.erase(temp_id)


func _process(_delta: float) -> void:
	if _projectile_system == null:
		return
	for id in _visuals.keys():
		var proj: ProjectileEntity = _projectile_system.projectiles.get(id)
		if proj != null:
			_visuals[id].position = proj.position


func _on_spawned(event: Dictionary) -> void:
	var id: int = event["projectile_id"]
	if _visuals.has(id):
		return
	var node := _make_visual(event["type_id"], event["owner_player_id"])
	node.position = event["position"]
	add_child(node)
	_visuals[id] = node


func _on_despawned(event: Dictionary) -> void:
	var id: int = event["projectile_id"]
	if not _visuals.has(id):
		return
	var node: Node2D = _visuals[id]
	_visuals.erase(id)

	var reason: int = event["reason"]
	var target_id: int = event.get("target_entity_id", -1)
	var final_pos: Vector2 = event["position"]

	# For entity collisions, snap to where the target APPEARS to be (interpolated),
	# not where it actually is. This compensates for the buffer delay — otherwise
	# projectiles appear to despawn before/after reaching moving targets.
	if target_id >= 0 and _net_client != null:
		if reason == ProjectileEntity.DespawnReason.ENEMY:
			var interp = _net_client.get_interpolated_enemy(target_id)
			if interp != null:
				final_pos = interp["position"]
		elif reason == ProjectileEntity.DespawnReason.PLAYER or \
			 reason == ProjectileEntity.DespawnReason.SELF:
			var interp_pos = _net_client.get_interpolated_position(target_id)
			if interp_pos != null:
				final_pos = interp_pos

	node.position = final_pos
	_play_despawn_effect(final_pos, reason)
	node.queue_free()


func _make_visual(type_id: int, owner_player_id: int) -> Node2D:
	var params: ProjectileParams = ProjectileType.get_params(type_id)

	if params == null:
		push_warning("ProjectileView: invalid type_id %d" % type_id)
		return _make_default_visual(owner_player_id)

	# If params specifies a visual scene, use it
	if not params.visual_scene.is_empty():
		var scene = load(params.visual_scene)
		if scene == null:
			push_warning("ProjectileView: failed to load visual_scene: %s" % params.visual_scene)
		else:
			var instance = scene.instantiate()
			if instance is Node2D:
				return instance
			else:
				push_warning("ProjectileView: visual_scene is not Node2D: %s" % params.visual_scene)
				instance.queue_free()

	# Default: procedural polygon
	return _make_default_visual(owner_player_id)


func _make_default_visual(owner_player_id: int) -> Node2D:
	var node := Node2D.new()
	var polygon := Polygon2D.new()
	polygon.color = _color_for_owner(owner_player_id)
	var verts := PackedVector2Array()
	for i in 12:
		var angle := TAU * float(i) / 12.0
		verts.append(Vector2(cos(angle), sin(angle)) * 6.0)
	polygon.polygon = verts
	node.add_child(polygon)
	return node


func _color_for_owner(owner_player_id: int) -> Color:
	if owner_player_id == _local_player_id:
		return Color(0.2, 1.0, 1.0, 1.0)   # bright cyan for local shooter
	return Color(0.2, 0.8, 0.8, 0.9)       # dimmer cyan for remote shooters


func _play_despawn_effect(pos: Vector2, reason: int) -> void:
	match reason:
		ProjectileEntity.DespawnReason.WALL:
			_spawn_particle_burst(pos, Color(0.6, 0.6, 0.65), 8)
		ProjectileEntity.DespawnReason.ENEMY:
			_spawn_particle_burst(pos, Color(0.2, 1.0, 1.0), 6)
		ProjectileEntity.DespawnReason.PLAYER:
			_spawn_particle_burst(pos, Color(1.0, 0.3, 0.3), 6)
		ProjectileEntity.DespawnReason.SELF:
			_spawn_particle_burst(pos, Color(1.0, 0.2, 0.2), 6)
		ProjectileEntity.DespawnReason.LIFETIME:
			pass  # soft fade only
		ProjectileEntity.DespawnReason.REJECTED:
			pass  # deliberately invisible


func _spawn_particle_burst(pos: Vector2, color: Color, count: int) -> void:
	var particles := CPUParticles2D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = count
	particles.lifetime = 0.25
	particles.direction = Vector2(0, -1)
	particles.spread = 180.0
	particles.initial_velocity_min = 40.0
	particles.initial_velocity_max = 90.0
	particles.color = color
	particles.gravity = Vector2.ZERO
	particles.position = pos
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(0.5).timeout.connect(particles.queue_free)


func _exit_tree() -> void:
	if EventBus.projectile_spawned.is_connected(_on_spawned):
		EventBus.projectile_spawned.disconnect(_on_spawned)
	if EventBus.projectile_despawned.is_connected(_on_despawned):
		EventBus.projectile_despawned.disconnect(_on_despawned)
	if EventBus.projectile_adopted.is_connected(_on_adopted):
		EventBus.projectile_adopted.disconnect(_on_adopted)
