class_name OptionsPanel
extends VBoxContainer

## video, audio and controls, shared by the main menu and the pause menu. a pure view onto the
## settings autoload: every control writes through and saves, so there is no apply or cancel to get wrong.

signal back_pressed

const TABS := ["VIDEO", "AUDIO", "CONTROLS"]

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(84, 64)
	custom_minimum_size = Vector2(560, 0)
	add_theme_constant_override("separation", 12)

	MenuStyle.title(self, "OPTIONS", MenuStyle.T_HEADING)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for i in TABS.size():
		var b := MenuStyle.button(row, TABS[i], _select_tab.bind(i))
		b.custom_minimum_size = Vector2(150, 40)
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
	return page


func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(540, 0)
	return v


func _slider(parent: Control, text: String, value: float, lo: float, hi: float, on_change: Callable) -> HSlider:
	MenuStyle.label(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(300, 22)
	s.value_changed.connect(on_change)
	parent.add_child(s)
	return s


func _dropdown(parent: Control, text: String, items: Array, selected: int, on_change: Callable) -> OptionButton:
	MenuStyle.label(parent, text)
	var ob := OptionButton.new()
	for item in items:
		ob.add_item(str(item))
	ob.select(clampi(selected, 0, items.size() - 1))
	ob.custom_minimum_size = Vector2(300, 32)
	ob.add_theme_font_size_override("font_size", MenuStyle.T_LABEL)
	ob.item_selected.connect(on_change)
	parent.add_child(ob)
	return ob
