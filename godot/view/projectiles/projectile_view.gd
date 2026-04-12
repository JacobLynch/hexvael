class_name ProjectileView
extends Node2D

@export var projectile_system_path: NodePath

var _projectile_system: ProjectileSystem
var _visuals: Dictionary = {}   # projectile_id -> Node2D
var _local_player_id: int = -1


func set_local_player_id(id: int) -> void:
	_local_player_id = id


func _ready() -> void:
	_projectile_system = get_node(projectile_system_path)
	EventBus.projectile_spawned.connect(_on_spawned)
	EventBus.projectile_despawned.connect(_on_despawned)


func _process(_delta: float) -> void:
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
	_play_despawn_effect(node.position, event["reason"])
	node.queue_free()


func _make_visual(type_id: int, owner_player_id: int) -> Node2D:
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


func _play_despawn_effect(_pos: Vector2, _reason: int) -> void:
	pass  # Task 26 fills this in
