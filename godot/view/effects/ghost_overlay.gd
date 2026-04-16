extends CanvasLayer

var _overlay: ColorRect
var _timer_label: Label
var _ghost_timer: float = 0.0
var _is_ghost: bool = false
var _local_player_id: int = -1
var _player_views: Dictionary = {}


func initialize(local_player_id: int, player_views: Dictionary) -> void:
    _local_player_id = local_player_id
    _player_views = player_views

    # Screen overlay (blue tint)
    _overlay = ColorRect.new()
    _overlay.color = Color(0.1, 0.1, 0.3, 0.4)
    _overlay.anchors_preset = Control.PRESET_FULL_RECT
    _overlay.visible = false
    add_child(_overlay)

    # Countdown timer
    _timer_label = Label.new()
    _timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _timer_label.anchors_preset = Control.PRESET_CENTER
    _timer_label.add_theme_font_size_override("font_size", 48)
    _timer_label.add_theme_color_override("font_color", Color.WHITE)
    _timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
    _timer_label.add_theme_constant_override("outline_size", 4)
    _timer_label.visible = false
    add_child(_timer_label)

    EventBus.player_ghost_started.connect(_on_ghost_started)
    EventBus.player_respawned.connect(_on_respawned)


func _on_ghost_started(event: Dictionary) -> void:
    var entity_id: int = event.get("entity_id", -1)

    # Set player view to ghost visual
    _set_player_ghost_visual(entity_id, true)

    # Show overlay for local player
    if entity_id == _local_player_id:
        _is_ghost = true
        _ghost_timer = event.get("duration", 5.0)
        _overlay.visible = true
        _timer_label.visible = true


func _on_respawned(event: Dictionary) -> void:
    var entity_id: int = event.get("entity_id", -1)

    # Clear ghost visual
    _set_player_ghost_visual(entity_id, false)

    # Hide overlay for local player
    if entity_id == _local_player_id:
        _is_ghost = false
        _overlay.visible = false
        _timer_label.visible = false


func _set_player_ghost_visual(entity_id: int, is_ghost: bool) -> void:
    var view = _player_views.get(entity_id)
    if view != null and view.has_method("set_ghost_visual"):
        view.set_ghost_visual(is_ghost)


func _process(delta: float) -> void:
    if _is_ghost:
        _ghost_timer = maxf(0.0, _ghost_timer - delta)
        _timer_label.text = "%.1f" % _ghost_timer


func _exit_tree() -> void:
    if EventBus.player_ghost_started.is_connected(_on_ghost_started):
        EventBus.player_ghost_started.disconnect(_on_ghost_started)
    if EventBus.player_respawned.is_connected(_on_respawned):
        EventBus.player_respawned.disconnect(_on_respawned)
