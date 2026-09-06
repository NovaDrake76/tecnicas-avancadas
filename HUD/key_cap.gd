class_name KeyCap
extends Control


## the action whose bound key this cap shows.
@export var action: StringName = &"":
	set(value):
		action = value
		if is_node_ready():
			refresh()
## the letter's size.
@export var text_size := 20:
	set(value):
		text_size = value
		if is_node_ready():
			refresh()

@export_group("Look")
@export var face := Color(0.09, 0.11, 0.10, 0.92)
@export var edge := Color(0.78, 0.85, 0.82, 0.55)
@export var ink := Color(0.95, 0.97, 0.92)

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
	_cap.border_width_bottom = 3
	_cap.border_color = edge
	_cap.set_corner_radius_all(5)
	_cap.corner_detail = 12
	refresh()


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


func key_text() -> String:
	return _text


func _draw() -> void:
	if _cap == null or _font == null:
		return
	draw_style_box(_cap, Rect2(Vector2.ZERO, size))
	var mid := (size.y - 2.0 + _font.get_ascent(_font_size) - _font.get_descent(_font_size)) * 0.5
	draw_string(_font, Vector2(0.0, mid), _text, HORIZONTAL_ALIGNMENT_CENTER, size.x, _font_size, ink)


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
