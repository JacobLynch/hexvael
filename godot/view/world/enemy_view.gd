extends Node2D

var entity_id: int = -1
var _target_position: Vector2 = Vector2.ZERO
var _facing: Vector2 = Vector2.RIGHT
var _state: int = 0
var _spawn_timer: float = 0.0
var _spawn_duration: float = 0.5
var _visual: ColorRect
var _facing_line: Line2D
var _time: float = 0.0

const WOBBLE_FREQ: float = 3.0
const WOBBLE_AMOUNT: float = 0.03

var _pop_tween: Tween = null

const ENEMY_COLOR = Color(0.4, 0.75, 0.3)


func _ready():
	_visual = ColorRect.new()
	_visual.size = Vector2(16, 16)
	_visual.position = Vector2(-8, -8)
	_visual.color = ENEMY_COLOR
	_visual.name = "Visual"
	add_child(_visual)

	_facing_line = Line2D.new()
	_facing_line.width = 2.0
	_facing_line.default_color = Color(0.9, 0.9, 0.3)
	_facing_line.points = PackedVector2Array([Vector2.ZERO, Vector2(4, 0)])
	_facing_line.name = "FacingLine"
	add_child(_facing_line)


func initialize(id: int, pos: Vector2) -> void:
	entity_id = id
	position = pos
	_target_position = pos


func update_from_data(data: Dictionary) -> void:
	_target_position = data["position"]
	_facing = data.get("facing", Vector2.RIGHT)
	var new_state = data.get("state", 0)

	if _state == 0 and new_state != 0:
		_play_spawn_pop()

	if new_state == 0 and _spawn_timer > 0.0:
		_spawn_duration = maxf(_spawn_duration, data.get("spawn_timer", 0.5))

	_state = new_state
	_spawn_timer = data.get("spawn_timer", 0.0)

	_facing_line.points = PackedVector2Array([Vector2.ZERO, _facing * 4.0])


func _process(delta: float):
	position = _target_position
	_time += delta

	if _state == 0:  # SPAWNING
		var progress = 1.0 - clampf(_spawn_timer / _spawn_duration, 0.0, 1.0)
		modulate.a = lerpf(0.2, 0.8, progress)
		scale = Vector2.ONE * lerpf(0.5, 0.8, progress)
	elif _state == 1:  # IDLE
		modulate.a = 1.0
		var wobble = 1.0 + sin(_time * WOBBLE_FREQ * TAU) * WOBBLE_AMOUNT
		if _pop_tween == null or not _pop_tween.is_running():
			scale = Vector2(wobble, wobble)
	else:  # CHASING
		modulate.a = 1.0
		if _pop_tween == null or not _pop_tween.is_running():
			scale = Vector2.ONE


func _play_spawn_pop() -> void:
	if _pop_tween != null and _pop_tween.is_running():
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.07)
	_pop_tween.tween_property(self, "scale", Vector2.ONE, 0.08)
