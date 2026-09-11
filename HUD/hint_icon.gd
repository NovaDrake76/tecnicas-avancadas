class_name HintIcon
extends Control


enum Kind { MAGAZINE, WHEEL, HOPUP, GRENADE, BINOCULARS, ROUND }

## which small picture this is.
@export var kind: Kind = Kind.MAGAZINE:
	set(value):
		kind = value
		queue_redraw()
@export var colour := Color(0.95, 0.97, 0.92):
	set(value):
		colour = value
		queue_redraw()
@export var side := 28.0
## how full the magazine picture is: half, so the picture is a magazine WITH rounds and not a box.
@export_range(0.0, 1.0) var magazine_fill := 0.5
@export var shadow := Color(0.0, 0.0, 0.0, 0.55)
## the key cap's dark plate under the picture: only for a picture that IS the thing you press (the wheel).
@export var plated := false
@export var plate := Color(0.09, 0.11, 0.10, 0.92)
@export var plate_edge := Color(0.78, 0.85, 0.82, 0.55)

var _plate: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(side, side)
	if plated:
		_plate = StyleBoxFlat.new()
		_plate.bg_color = plate
		_plate.set_border_width_all(1)
		_plate.border_width_bottom = 3
		_plate.border_color = plate_edge
		_plate.set_corner_radius_all(5)
		_plate.corner_detail = 12


func _draw() -> void:
	if _plate != null:
		draw_style_box(_plate, Rect2(Vector2.ZERO, size))
	var c := size * 0.5 - Vector2(0.0, 1.0)
	var line := 1.5
	match kind:
		Kind.MAGAZINE:
			var box := Vector2(side * 0.34, side * 0.66)
			MagGlyph.draw_on(self, c - box * 0.5, box, magazine_fill, colour, shadow, line)
		Kind.ROUND:
			var box := Vector2(side * 0.26, side * 0.64)
			RoundGlyph.draw_on(self, c - box * 0.5, box, colour)
		Kind.WHEEL:
			var w := side * 0.36
			var h := side * 0.64
			var body := StyleBoxFlat.new()
			body.bg_color = Color(colour, 0.12)
			body.border_color = colour
			body.set_border_width_all(1)
			body.set_corner_radius_all(int(w * 0.45))
			body.corner_detail = 8
			draw_style_box(body, Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)))
			var slot := Vector2(w * 0.24, h * 0.3)
			draw_rect(Rect2(c - Vector2(slot.x * 0.5, h * 0.5 - h * 0.12), slot), colour, true)
			var tip := c + Vector2(w * 0.7, 0.0)
			draw_line(tip + Vector2(0.0, -h * 0.28), tip + Vector2(0.0, h * 0.28), colour, line)
			draw_line(tip + Vector2(0.0, -h * 0.34), tip + Vector2(-3.0, -h * 0.34 + 3.0), colour, line)
			draw_line(tip + Vector2(0.0, -h * 0.34), tip + Vector2(3.0, -h * 0.34 + 3.0), colour, line)
			draw_line(tip + Vector2(0.0, h * 0.34), tip + Vector2(-3.0, h * 0.34 - 3.0), colour, line)
			draw_line(tip + Vector2(0.0, h * 0.34), tip + Vector2(3.0, h * 0.34 - 3.0), colour, line)
		Kind.HOPUP:
			var bb := c + Vector2(side * 0.3, side * 0.28)
			draw_circle(bb, side * 0.13, colour)
			var r := side * 0.62
			var centre := bb - Vector2(r, 0.0)
			draw_arc(centre, r, PI * 1.28, TAU, 16, colour, line, true)
			var end := centre + Vector2(cos(PI * 1.28), sin(PI * 1.28)) * r
			draw_line(end, end + Vector2(5.0, 0.5), colour, line)
			draw_line(end, end + Vector2(1.0, 5.0), colour, line)
		Kind.GRENADE:
			var body_r := side * 0.3
			var body_c := c + Vector2(0.0, side * 0.12)
			draw_arc(body_c, body_r, 0.0, TAU, 20, colour, line, true)
			draw_circle(body_c, body_r * 0.55, Color(colour, 0.35))
			var neck := Rect2(body_c + Vector2(-side * 0.1, -body_r - side * 0.18), Vector2(side * 0.2, side * 0.2))
			draw_rect(neck, colour, false, line)
			draw_line(neck.position + Vector2(neck.size.x, 0.0), neck.position + Vector2(neck.size.x + side * 0.22, side * 0.16), colour, line)
		Kind.BINOCULARS:
			var bw := side * 0.3
			var bh := side * 0.66
			var gap := side * 0.08
			var barrel := StyleBoxFlat.new()
			barrel.bg_color = Color(colour, 0.18)
			barrel.border_color = colour
			barrel.set_border_width_all(1)
			barrel.set_corner_radius_all(int(bw * 0.4))
			barrel.corner_detail = 8
			for sx in [-1.0, 1.0]:
				var corner := c + Vector2(sx * (gap * 0.5 + bw * 0.5) - bw * 0.5, -bh * 0.5)
				draw_style_box(barrel, Rect2(corner, Vector2(bw, bh)))
				draw_circle(corner + Vector2(bw * 0.5, bh - bw * 0.5), bw * 0.28, colour)
			draw_rect(Rect2(c + Vector2(-gap * 0.5 - 1.0, -bh * 0.5 + bw * 0.35), Vector2(gap + 2.0, bh * 0.28)), colour, true)
