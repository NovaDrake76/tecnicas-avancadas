extends CanvasLayer

## the pause menu, as an autoload: every level gets it for free and there is exactly one of it.
## escape freezes the whole tree, so this node must keep processing or it would freeze itself shut.

const MENU_SCENE := "res://UI/main_menu.tscn"

var _root: Control
var _menu: VBoxContainer
var _options: OptionsPanel


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
	MenuStyle.button(_menu, "CONTINUE", close)
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


## only a level can be paused. the main menu has no player, and escape there must do nothing rather
## than freeze one menu behind another.
func can_pause() -> bool:
	return get_tree().get_first_node_in_group("player") != null


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_options.reset_view()
	_show(_menu)
	visible = true
	UiSfx.play("switch")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not visible:
		return
	visible = false
	UiSfx.play("back")
	get_tree().paused = false
	## the cursor goes back only if there is a game to give it to.
	if can_pause() and DisplayServer.window_is_focused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## the run is abandoned, not saved. main.tscn starts a fresh one the next time play is pressed.
func quit_to_menu() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await Fade.cover()
	get_tree().change_scene_to_file(MENU_SCENE)


func _show(which: Control) -> void:
	_menu.visible = which == _menu
	_options.visible = which == _options
