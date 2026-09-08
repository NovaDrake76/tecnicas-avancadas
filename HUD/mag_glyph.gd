class_name MagGlyph
extends RefCounted


const SLANT := 0.28
const PLATE := 0.1
const WINDOW := 0.34


## the silhouette of a magazine seen from the side: the body LEANS as it falls, so the feed lips sit
## forward of the baseplate and the shape reads as a magazine rather than as a box. `top` cuts it at
## a fraction of its height, which is how the fill and the outline stay the same shape.
static func body(corner: Vector2, box: Vector2, top := 0.0) -> PackedVector2Array:
	var slant := box.x * SLANT
	var y0 := box.y * top
	var x0 := slant * (1.0 - top)
	return PackedVector2Array([
		corner + Vector2(x0, y0),
		corner + Vector2(x0 + box.x, y0),
		corner + Vector2(box.x, box.y),
		corner + Vector2(0.0, box.y)])


static func draw_on(where: CanvasItem, corner: Vector2, box: Vector2, fill: float, tint: Color,
		backing := Color(0.0, 0.0, 0.0, 0.0), line := 1.5) -> void:
	var outline := body(corner, box)
	if backing.a > 0.0:
		where.draw_colored_polygon(_grow(outline, line * 2.0), backing)
	var filled := clampf(fill, 0.0, 1.0)
	if filled > 0.0:
		where.draw_colored_polygon(body(corner, box, 1.0 - filled), Color(tint, 0.85))
	where.draw_polyline(outline + PackedVector2Array([outline[0]]), tint, line, true)
	var plate := box.y * PLATE
	where.draw_rect(Rect2(corner + Vector2(-line, box.y - plate), Vector2(box.x + line * 2.0, plate)), tint, true)
	var win_y := box.y * WINDOW
	var wx := box.x * SLANT * (1.0 - win_y / box.y)
	where.draw_line(corner + Vector2(wx + line * 2.5, win_y),
		corner + Vector2(wx + box.x - line * 2.5, win_y), Color(tint, 0.6), line * 0.7)


static func _grow(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var centre := Vector2.ZERO
	for p in poly:
		centre += p
	centre /= float(poly.size())
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + (p - centre).normalized() * by)
	return out
