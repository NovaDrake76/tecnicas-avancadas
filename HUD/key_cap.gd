class_name KeyCap
extends Control

## a key, drawn as a KEY: a rounded cap with a thicker bottom edge, the letter centred on it. it
## replaces the "[E]" the prompts used to be written with.
##
## the brackets were doing two jobs badly. they read as punctuation in the middle of a sentence, so
## "[E]  Take it" is four words the eye has to parse before it knows which one is the instruction;
## and at a glance a bracketed letter looks like the rest of the text, which is exactly what a
## control prompt must not do. a cap is a PICTURE of the thing the hand is being asked to press, and
## it is found by shape before any of it is read.
##
## the letter is resolved from the InputMap every time, never typed in, so a rebind can never leave
## the screen naming a key that does nothing -- the same rule the bracketed version already followed
## and the reason this is a node rather than a string helper.

## the action whose bound key this cap shows.
@export var action: StringName = &"":
	set(value):
		action = value
		if is_node_ready():
			refresh()
## the letter's size. the cap is built around it, so this is the only size to set.
@export var text_size := 20:
	set(value):
		text_size = value
		if is_node_ready():
			refresh()

@export_group("Look")
@export var face := Color(0.09, 0.11, 0.10, 0.92)
@export var edge := Color(0.78, 0.85, 0.82, 0.55)
@export var ink := Color(0.95, 0.97, 0.92)

## breathing room either side of the letter. a wide label (SHIFT, LMB) grows the cap; a single
## letter leaves it square, which is what makes it read as a key rather than as a button.
const PAD := 8.0

var _text := "?"
var _cap: StyleBoxFlat
var _font: Font
var _font_size := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap = StyleBoxFlat.new()
	_cap.bg_color = face
	_cap.set_border_width_all(1)
	## a heavier bottom edge is the whole of the three dimensions: it reads as the lip of a key.
	_cap.border_width_bottom = 3
	_cap.border_color = edge
	_cap.set_corner_radius_all(5)
	_cap.corner_detail = 12
	refresh()


## point it at another action, or at the same one after a rebind.
func refresh() -> void:
	_text = label_for(action)
	_font = HudStyle.FACE
	_font_size = text_size
	var wide := _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, _font_size).x
	var tall := roundf(float(text_size) * 1.65)
	custom_minimum_size = Vector2(maxf(tall, wide + PAD * 2.0), tall)
	if _cap != null:
		_cap.bg_color = face
		_cap.border_color = edge
	queue_redraw()


## what this cap is showing, for anything that needs the word rather than the picture.
func key_text() -> String:
	return _text


func _draw() -> void:
	if _cap == null or _font == null:
		return
	draw_style_box(_cap, Rect2(Vector2.ZERO, size))
	## centred on the cap by the FONT's own metrics rather than on half its height: a line's box
	## carries room for descenders no capital letter uses, so splitting it leaves every letter
	## sitting low. the border's heavier bottom edge is taken off the same way.
	var mid := (size.y - 2.0 + _font.get_ascent(_font_size) - _font.get_descent(_font_size)) * 0.5
	draw_string(_font, Vector2(0.0, mid), _text, HORIZONTAL_ALIGNMENT_CENTER, size.x, _font_size, ink)


## the printed key for an action. static, so a probe or a page of text can ask without building one.
##
## the map binds PHYSICAL keycodes, which are the US layout's, so this asks the display server what
## that physical key actually prints on the keyboard in front of the player: on an AZERTY board the
## key our map calls W is the one marked Z, and telling them to press W would be a lie. the headless
## server has no layout and complains, so the probes get the physical name instead.
static func label_for(act: StringName) -> String:
	if act == &"" or not InputMap.has_action(act):
		return "?"
	for event in InputMap.action_get_events(act):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode
			if code == 0:
				code = key.keycode
			if code == 0:
				continue
			if key.physical_keycode != 0 and DisplayServer.get_name() != "headless":
				var printed := DisplayServer.keyboard_get_label_from_physical(key.physical_keycode)
				if printed == 0:
					printed = DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
				if printed != 0:
					code = printed
			return OS.get_keycode_string(code)
		if event is InputEventMouseButton:
			match (event as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT:
					return "LMB"
				MOUSE_BUTTON_RIGHT:
					return "RMB"
				MOUSE_BUTTON_MIDDLE:
					return "MMB"
				MOUSE_BUTTON_WHEEL_UP:
					return "WHEEL+"
				MOUSE_BUTTON_WHEEL_DOWN:
					return "WHEEL-"
	return "?"
