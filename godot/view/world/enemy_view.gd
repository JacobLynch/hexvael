extends Node2D

var entity_id: int = -1
var _target_position: Vector2 = Vector2.ZERO
var _facing: Vector2 = Vector2.RIGHT
var _state: int = 0
var _spawn_timer: float = 0.0
var _spawn_duration: float = 0.5
var _visual: ColorRect
var _facing_line: Line2D
var _warning_outer: ColorRect  # pulsing outline square during SPAWNING
var _warning_cross_h: ColorRect
var _warning_cross_v: ColorRect
var _time: float = 0.0

const WOBBLE_FREQ: float = 3.0
const WOBBLE_AMOUNT: float = 0.03

var _pop_tween: Tween = null

const ENEMY_COLOR = Color(0.4, 0.75, 0.3)
const WARNING_COLOR = Color(0.85, 0.2, 0.15)


func _ready():
	# Warning indicator — visible during SPAWNING
	# Outer pulsing square (hollow look via a colored border-sized rect)
	_warning_outer = ColorRect.new()
	_warning_outer.size = Vector2(24, 24)
	_warning_outer.position = Vector2(-12, -12)
	_warning_outer.color = WARNING_COLOR
	_warning_outer.name = "WarningOuter"
	add_child(_warning_outer)

	# Cross lines inside the warning
	_warning_cross_h = ColorRect.new()
	_warning_cross_h.size = Vector2(16, 2)
	_warning_cross_h.position = Vector2(-8, -1)
	_warning_cross_h.color = WARNING_COLOR
	add_child(_warning_cross_h)

	_warning_cross_v = ColorRect.new()
	_warning_cross_v.size = Vector2(2, 16)
	_warning_cross_v.position = Vector2(-1, -8)
	_warning_cross_v.color = WARNING_COLOR
	add_child(_warning_cross_v)

	# Enemy body — hidden during SPAWNING, shown on pop
	_visual = ColorRect.new()
	_visual.size = Vector2(16, 16)
	_visual.position = Vector2(-8, -8)
	_visual.color = ENEMY_COLOR
	_visual.name = "Visual"
	_visual.visible = false
	add_child(_visual)

	_facing_line = Line2D.new()
	_facing_line.width = 2.0
	_facing_line.default_color = Color(0.9, 0.9, 0.3)
	_facing_line.points = PackedVector2Array([Vector2.ZERO, Vector2(4, 0)])
	_facing_line.name = "FacingLine"
	_facing_line.visible = false
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

	if new_state == 0 and _spawn_duration < 0.01:
		_spawn_duration = maxf(0.5, data.get("spawn_timer", 0.5))

	_state = new_state
	_spawn_timer = data.get("spawn_timer", 0.0)

	_facing_line.points = PackedVector2Array([Vector2.ZERO, _facing * 4.0])


func _process(delta: float):
	position = _target_position
	_time += delta

	if _state == 0:  # SPAWNING
		_visual.visible = false
		_facing_line.visible = false
		_set_warning_visible(true)

		var progress = 1.0 - clampf(_spawn_timer / _spawn_duration, 0.0, 1.0)

		# Pulse faster as spawn approaches, sharper square wave feel
		var pulse_speed = 6.0 + progress * 20.0
		var pulse_raw = sin(_time * pulse_speed)
		var pulse = 1.0 + pulse_raw * 0.2

		# Warning grows and becomes more opaque
		var base_scale = 0.3 + progress * 0.7
		_warning_outer.scale = Vector2.ONE * base_scale * pulse
		_warning_cross_h.scale = Vector2.ONE * base_scale * pulse
		_warning_cross_v.scale = Vector2.ONE * base_scale * pulse

		var alpha = 0.2 + progress * 0.8
		var flash_alpha = alpha * (0.7 + pulse_raw * 0.3)
		_warning_outer.modulate.a = flash_alpha
		_warning_cross_h.modulate.a = flash_alpha
		_warning_cross_v.modulate.a = flash_alpha

		# Color shifts from dark red to bright red-orange near the end
		var warn_color = WARNING_COLOR.lerp(Color(1.0, 0.4, 0.1), progress * progress)
		_warning_outer.color = warn_color
		_warning_cross_h.color = warn_color
		_warning_cross_v.color = warn_color

	elif _state == 1:  # IDLE
		_visual.visible = true
		_facing_line.visible = true
		_set_warning_visible(false)
		modulate.a = 1.0
		var wobble = 1.0 + sin(_time * WOBBLE_FREQ * TAU) * WOBBLE_AMOUNT
		if _pop_tween == null or not _pop_tween.is_running():
			scale = Vector2(wobble, wobble)
	else:  # CHASING
		_visual.visible = true
		_facing_line.visible = true
		_set_warning_visible(false)
		modulate.a = 1.0
		if _pop_tween == null or not _pop_tween.is_running():
			scale = Vector2.ONE


func _set_warning_visible(vis: bool) -> void:
	_warning_outer.visible = vis
	_warning_cross_h.visible = vis
	_warning_cross_v.visible = vis


func _play_spawn_pop() -> void:
	_set_warning_visible(false)
	_visual.visible = true
	_facing_line.visible = true
	modulate.a = 1.0

	# Punch scale: 0 → 1.5 → 1.0 with elastic overshoot
	if _pop_tween != null and _pop_tween.is_running():
		_pop_tween.kill()
	scale = Vector2.ZERO
	_pop_tween = create_tween()
	_pop_tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.08).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_pop_tween.tween_property(self, "scale", Vector2(0.85, 0.85), 0.06).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	_pop_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.05).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_pop_tween.tween_property(self, "scale", Vector2.ONE, 0.06).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# White flash → enemy color
	_visual.color = Color(1.0, 1.0, 0.85)
	var color_tween = create_tween()
	color_tween.tween_property(_visual, "color", ENEMY_COLOR, 0.25)


## Flash the enemy visual to indicate a hit.
func flash_hit(color: Color, duration: float) -> void:
	if _visual == null:
		return
	var original_color = ENEMY_COLOR
	_visual.color = color
	var tween = create_tween()
	tween.tween_property(_visual, "color", original_color, duration)
