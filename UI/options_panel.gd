class_name OptionsPanel
extends VBoxContainer

## video, audio and controls, shared by the main menu and the pause menu. a pure view onto the
## settings autoload: every control writes through and saves, so there is no apply or cancel to get wrong.

signal back_pressed

const TABS := ["VIDEO", "AUDIO", "CONTROLS"]

## caption, then the actions whose keys it prints. one row can carry several, which is how the
## four movement keys and the two lean keys read as one line each.
const KEYS := [
	["MOVE", ["move_forward", "move_left", "move_back", "move_right"]],
	["SPRINT", ["sprint"]],
	["CROUCH", ["crouch"]],
	["JUMP", ["jump"]],
	["LEAN (HOLD, THEN A / D)", ["lean_mode"]],
	["FIRE", ["fire"]],
	["AIM", ["aim"]],
	["RELOAD", ["reload"]],
	["FIRE MODE", ["toggle_fire_mode"]],
	["INTERACT", ["interact"]],
	["CYCLE WEAPON", ["weapon_next", "weapon_prev"]],
	["WEAPON SLOTS", ["weapon_1", "weapon_2", "weapon_3", "weapon_4"]],
]

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(140, 106)
	custom_minimum_size = Vector2(920, 0)
	add_theme_constant_override("separation", 20)

	MenuStyle.title(self, "OPTIONS", MenuStyle.T_HEADING)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for i in TABS.size():
		var b := MenuStyle.button(row, TABS[i], _select_tab.bind(i))
		b.custom_minimum_size = Vector2(250, 66)
		_tab_buttons.append(b)

	_pages = [_video(), _audio(), _controls()]
	for page in _pages:
		add_child(page)

	MenuStyle.spacer(self, 8)
	MenuStyle.button(self, "BACK", func() -> void: back_pressed.emit())
	_select_tab(0)


func reset_view() -> void:
	_select_tab(0)


func _select_tab(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == index
		_tab_buttons[i].add_theme_color_override("font_color",
			MenuStyle.HOT if i == index else MenuStyle.DIM)


func _video() -> Control:
	var page := _page()
	_dropdown(page, "WINDOW MODE", ["Windowed", "Fullscreen", "Borderless"], Settings.window_mode,
		func(i: int) -> void:
			Settings.window_mode = i
			Settings.commit())
	_dropdown(page, "V-SYNC", ["Off", "On", "Adaptive"], Settings.vsync,
		func(i: int) -> void:
			Settings.vsync = i
			Settings.commit())
	var labels := ["Uncapped", "60", "120", "144", "240"]
	_dropdown(page, "MAX FPS", labels, maxi(Settings.FPS_CAPS.find(Settings.max_fps), 0),
		func(i: int) -> void:
			Settings.max_fps = Settings.FPS_CAPS[i]
			Settings.commit())
	return page


func _audio() -> Control:
	var page := _page()
	_slider(page, "MASTER VOLUME", Settings.master_volume, 0.0, 1.0, func(x: float) -> void:
		Settings.master_volume = x
		Settings.commit())
	return page


func _controls() -> Control:
	var page := _page()
	_slider(page, "MOUSE SENSITIVITY", Settings.look_scale, 0.25, 3.0, func(x: float) -> void:
		Settings.look_scale = x
		Settings.commit())
	var invert := CheckButton.new()
	invert.text = "INVERT LOOK"
	invert.button_pressed = Settings.invert_look
	invert.add_theme_font_size_override("font_size", MenuStyle.T_LABEL)
	invert.add_theme_color_override("font_color", MenuStyle.DIM)
	invert.toggled.connect(func(on: bool) -> void:
		Settings.invert_look = on
		Settings.commit())
	page.add_child(invert)

	MenuStyle.sheet_section(page, "KEYS")
	for row in KEYS:
		MenuStyle.sheet_kv(page, String(row[0]), _binding(row[1] as Array))
	MenuStyle.sheet_kv(page, "HOP-UP", "MOUSE WHEEL")
	return page


## every key here is resolved from the input map, so the sheet says what the game actually
## listens for rather than what someone typed the day it was written.
func _binding(actions: Array) -> String:
	var keys: Array[String] = []
	for action in actions:
		for event in InputMap.action_get_events(StringName(action)):
			if event is InputEventKey:
				keys.append(OS.get_keycode_string((event as InputEventKey).physical_keycode).to_upper())
				break
			if event is InputEventMouseButton:
				keys.append(_mouse_name((event as InputEventMouseButton).button_index))
				break
	return "  ".join(keys)


func _mouse_name(button: int) -> String:
	match button:
		MOUSE_BUTTON_LEFT:
			return "LEFT MOUSE"
		MOUSE_BUTTON_RIGHT:
			return "RIGHT MOUSE"
		MOUSE_BUTTON_MIDDLE:
			return "MIDDLE MOUSE"
	return "MOUSE %d" % button


func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	v.custom_minimum_size = Vector2(900, 0)
	return v


func _slider(parent: Control, text: String, value: float, lo: float, hi: float, on_change: Callable) -> HSlider:
	MenuStyle.label(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(500, 36)
	s.value_changed.connect(on_change)
	parent.add_child(s)
	return s


func _dropdown(parent: Control, text: String, items: Array, selected: int, on_change: Callable) -> OptionButton:
	MenuStyle.label(parent, text)
	var ob := OptionButton.new()
	for item in items:
		ob.add_item(str(item))
	ob.select(clampi(selected, 0, items.size() - 1))
	ob.custom_minimum_size = Vector2(500, 52)
	ob.add_theme_font_size_override("font_size", MenuStyle.T_LABEL)
	ob.item_selected.connect(on_change)
	parent.add_child(ob)
	return ob
