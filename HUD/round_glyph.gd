class_name RoundGlyph
extends RefCounted


const TIP := 0.38
const RIM := 0.19
const DOME_STEPS := 8


## one round of ammunition seen from the side: a domed tip over a straight case. The fire mode row
## draws these to say SEMI or AUTO; the reload ring wears one, so a round means a round wherever it
## is on the screen.
static func outline(at: Vector2, box: Vector2) -> PackedVector2Array:
	var tip := box.y * TIP
	var points := PackedVector2Array()
	for i in DOME_STEPS + 1:
		var a := PI + PI * float(i) / float(DOME_STEPS)
		points.append(at + Vector2(box.x * 0.5 + cos(a) * box.x * 0.5, tip + sin(a) * tip))
	points.append(at + Vector2(box.x, box.y))
	points.append(at + Vector2(0.0, box.y))
	return points


static func draw_on(where: CanvasItem, at: Vector2, box: Vector2, tint: Color) -> void:
	where.draw_colored_polygon(outline(at, box), tint)
	var rim := box.y * RIM
	where.draw_line(at + Vector2(0.0, box.y - rim), at + Vector2(box.x, box.y - rim),
		Color(0.0, 0.0, 0.0, 0.45), maxf(1.0, box.y * 0.06))
