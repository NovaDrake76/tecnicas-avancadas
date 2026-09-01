class_name MenuStyle
extends RefCounted

## the look of every menu screen in one place, so the main menu and the pause menu cannot drift apart.
## static factories rather than a theme resource, because these screens are built in code.

const DIM := Color(0.72, 0.78, 0.7)
const BRIGHT := Color(0.95, 0.97, 0.92)
const HOT := Color(1.0, 0.82, 0.3)
const INK := Color(0.03, 0.05, 0.03)

const T_TITLE := 64
const T_HEADING := 40
const T_BODY := 22
const T_LABEL := 16


static func title(parent: Control, text: String, size := T_TITLE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", BRIGHT)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 8)
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
	b.custom_minimum_size = Vector2(300, 44)
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


## the dark gradient behind a menu column. it fades out, because a flat rectangle leaves a hard seam
## down the frame that reads as a rendering bug rather than as art.
static func scrim(parent: Control, width := 640.0, alpha := 0.72) -> TextureRect:
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


## the column every menu hangs its buttons on: anchored to the left edge, vertically centred.
static func column(parent: Control) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.position = Vector2(84, -170)
	col.custom_minimum_size = Vector2(320, 0)
	col.add_theme_constant_override("separation", 10)
	parent.add_child(col)
	return col
