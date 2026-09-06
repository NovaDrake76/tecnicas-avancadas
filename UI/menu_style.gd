class_name MenuStyle
extends RefCounted


const FACE_BOLD := preload("res://Fonts/IBMPlexSansCondensed-Bold.ttf")
const FACE_MEDIUM := preload("res://Fonts/IBMPlexSansCondensed-SemiBold.ttf")

const DIM := Color(0.72, 0.78, 0.7)
const BRIGHT := Color(0.95, 0.97, 0.92)
const HOT := Color(1.0, 0.82, 0.3)
const INK := Color(0.03, 0.05, 0.03)
const ACCENT := Color(0.86, 0.3, 0.22)
const HAIRLINE := Color(1.0, 1.0, 1.0, 0.09)
const CARD := Color(0.085, 0.09, 0.085)
const CARD_HOVER := Color(0.13, 0.135, 0.13)

const T_TITLE := 104
const T_HEADING := 64
const T_BODY := 34
const T_LABEL := 24


static func title(parent: Control, text: String, size := T_TITLE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FACE_BOLD)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", BRIGHT)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 12)
	parent.add_child(l)
	return l


static func label(parent: Control, text: String, size := T_LABEL) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", DIM)
	parent.add_child(l)
	return l


static func button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(500, 72)
	b.add_theme_font_override("font", FACE_MEDIUM)
	b.add_theme_font_size_override("font_size", T_BODY)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", HOT)
	b.add_theme_color_override("font_focus_color", HOT)
	b.add_theme_color_override("font_pressed_color", HOT)
	b.pressed.connect(on_press)
	parent.add_child(b)
	## a stable name from the label, so a probe can find a button by what it says.
	b.name = text.to_upper().replace(" ", "_").replace("-", "_")
	return b


static func spacer(parent: Control, height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


static func scrim(parent: Control, width := 1060.0, alpha := 0.72) -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, Color(INK, alpha))
	grad.set_color(1, Color(INK, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 4
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	r.offset_right = width
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


static func column(parent: Control) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.position = Vector2(140, -280)
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 16)
	parent.add_child(col)
	return col


const OK := Color(0.55, 0.85, 0.6)
const GRADE_COLORS := {
	"A+": Color(1.0, 0.86, 0.35), "A": Color(1.0, 0.86, 0.35), "B": Color(0.55, 0.85, 0.6),
	"C": Color(0.88, 0.92, 0.96), "D": Color(1.0, 0.62, 0.28), "F": Color(1.0, 0.35, 0.3),
}


static func grade_color(letter: String) -> Color:
	return GRADE_COLORS.get(letter, BRIGHT)


const SHEET_EDGE := 64
const SHEET_TOP := 36
const SHEET_BOTTOM := 72


static func sheet_margins(margin: MarginContainer) -> void:
	margin.add_theme_constant_override("margin_left", SHEET_EDGE)
	margin.add_theme_constant_override("margin_right", SHEET_EDGE)
	margin.add_theme_constant_override("margin_top", SHEET_TOP)
	margin.add_theme_constant_override("margin_bottom", SHEET_BOTTOM)


static func sheet_text(parent: Control, text: String, size: int, colour: Color, wrapped := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrapped:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


static func sheet_section(parent: Control, text: String) -> void:
	sheet_gap(parent, 2)
	sheet_text(parent, text, 13, DIM)
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = HAIRLINE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	sheet_gap(parent, 4)


static func sheet_gap(parent: Control, h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)


static func sheet_kv(parent: Control, key: String, value: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var k := sheet_text(row, key, 14, DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := sheet_text(row, value, 18, BRIGHT)
	v.add_theme_font_override("font", FACE_MEDIUM)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = HAIRLINE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)


static func sheet_card(parent: Control, selected: bool, on_click: Callable) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.content_margin_left = 16.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	if selected:
		style.border_width_left = 3
		style.border_color = ACCENT
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	if on_click.is_valid():
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				UiSfx.play("click")
				on_click.call())
		panel.mouse_entered.connect(func() -> void:
			style.bg_color = CARD_HOVER
			UiSfx.play("hover"))
		panel.mouse_exited.connect(func() -> void: style.bg_color = CARD)
	return col


static func sheet_scroller(parent: Control, share: float) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = share
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size = Vector2(4, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.04)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(1, 1, 1, 0.18)
	for k in ["scroll", "scroll_focus"]:
		bar.add_theme_stylebox_override(k, track)
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(k, grab)
	return scroll


static func sheet_column(scroll: ScrollContainer) -> VBoxContainer:
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 18)
	scroll.add_child(pad)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	pad.add_child(col)
	return col


static func sheet_solid(parent: Control, text: String, cb: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(230, 44)
	b.add_theme_font_override("font", FACE_MEDIUM)
	b.add_theme_font_size_override("font_size", 16)
	var normal := StyleBoxFlat.new()
	normal.bg_color = ACCENT if accent else Color(0.12, 0.125, 0.12)
	normal.content_margin_left = 24.0
	normal.content_margin_right = 24.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.95, 0.4, 0.3) if accent else Color(0.2, 0.21, 0.2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_stylebox_override("disabled", normal)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(k, BRIGHT)
	b.pressed.connect(cb)
	b.name = text.to_upper().replace(" ", "_")
	parent.add_child(b)
	return b


static func sheet_clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return out
