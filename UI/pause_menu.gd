extends CanvasLayer


const MENU_SCENE := "res://UI/main_menu.tscn"

const RESTART := "RESTART MISSION"
const RESTART_ARMED := "PRESS AGAIN TO RESTART"

var _root: Control
var _menu: VBoxContainer
var _options: OptionsPanel
var _restart: Button
var _armed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	visible = false

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.01, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	MenuStyle.scrim(_root, 1060.0, 0.55)

	_menu = MenuStyle.column(_root)
	MenuStyle.title(_menu, "PAUSED", MenuStyle.T_HEADING)
	MenuStyle.spacer(_menu, 40)
	MenuStyle.button(_menu, "CONTINUE", close).set_meta(UiSfx.QUIET, true)
	_restart = MenuStyle.button(_menu, RESTART, _on_restart)
	MenuStyle.button(_menu, "OPTIONS", func() -> void: _show(_options))
	MenuStyle.button(_menu, "QUIT TO MENU", quit_to_menu)

	_options = OptionsPanel.new()
	_options.visible = false
	_options.back_pressed.connect(func() -> void: _show(_menu))
	_root.add_child(_options)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if visible:
		close()
	elif can_pause():
		open()
	get_viewport().set_input_as_handled()


func can_pause() -> bool:
	return Player.local(get_tree()) != null


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_options.reset_view()
	_disarm()
	_restart.visible = Run.state == Run.State.PLAYING
	_show(_menu)
	visible = true
	UiSfx.play("switch")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not visible:
		return
	visible = false
	_disarm()
	UiSfx.play("pause_close")
	get_tree().paused = false
	if can_pause() and DisplayServer.window_is_focused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func quit_to_menu() -> void:
	Net.leave()
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await Fade.cover()
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_restart() -> void:
	if not _armed:
		_armed = true
		_restart.text = RESTART_ARMED
		_restart.add_theme_color_override("font_color", MenuStyle.ACCENT)
		return
	_disarm()
	Run.restart_level()


func _disarm() -> void:
	if _restart == null:
		return
	_armed = false
	_restart.text = RESTART
	_restart.add_theme_color_override("font_color", MenuStyle.DIM)


func restart_armed() -> bool:
	return _armed


func _show(which: Control) -> void:
	if which != _menu:
		_disarm()
	_menu.visible = which == _menu
	_options.visible = which == _options
