extends CanvasLayer

## play, options, quit. built in code so there is no layout file to keep in step with the script,
## and styled by the same helpers as the pause menu so the two cannot drift apart.

const TITLE := "KIWI EMPIRE"
const GAME_SCENE := "res://main.tscn"

var _root: Control
var _menu: VBoxContainer
var _options: OptionsPanel


func _ready() -> void:
	layer = 1
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	MenuStyle.scrim(_root)

	_menu = MenuStyle.column(_root)
	MenuStyle.title(_menu, TITLE)
	MenuStyle.label(_menu, "Total Kiwi Death", MenuStyle.T_LABEL)
	MenuStyle.spacer(_menu, 24)
	MenuStyle.button(_menu, "PLAY", start_game)
	MenuStyle.button(_menu, "OPTIONS", func() -> void: _show(_options))
	MenuStyle.button(_menu, "QUIT", func() -> void: get_tree().quit())

	_options = OptionsPanel.new()
	_options.visible = false
	_options.back_pressed.connect(func() -> void: _show(_menu))
	_root.add_child(_options)


func start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _show(which: Control) -> void:
	_menu.visible = which == _menu
	_options.visible = which == _options
	if which == _options:
		_options.reset_view()
