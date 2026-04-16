class_name FrostBoltStreak
extends Node2D
## Launch streak that trails behind frost bolt for first few frames.
## Tracks projectile position briefly, then fades out.

const TRACK_DURATION: float = 0.08  ## How long to follow bolt
const FADE_DURATION: float = 0.1
const LINE_WIDTH: float = 2.5
const LINE_COLOR: Color = Color(0.7, 0.9, 1.0, 0.9)

var _line: Line2D
var _track_timer: float = 0.0
var _fading: bool = false
var _projectile_id: int = -1
var _projectile_system: Node  # ProjectileSystem reference


func initialize(start_pos: Vector2, proj_id: int, proj_system: Node) -> void:
	_projectile_id = proj_id
	_projectile_system = proj_system
	global_position = start_pos
	_create_line()


func _create_line() -> void:
	_line = Line2D.new()
	_line.width = LINE_WIDTH
	_line.default_color = LINE_COLOR
	_line.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_line)


func _process(delta: float) -> void:
	if _fading:
		return

	if _track_timer < TRACK_DURATION:
		# Update endpoint to projectile position
		if _projectile_system != null:
			var proj = _projectile_system.projectiles.get(_projectile_id)
			if proj != null:
				_line.points[1] = proj.position - global_position
		_track_timer += delta
	else:
		_start_fade()


func _start_fade() -> void:
	_fading = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(queue_free)
