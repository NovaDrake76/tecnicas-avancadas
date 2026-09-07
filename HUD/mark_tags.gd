class_name MarkTags
extends Control


const INK := Color(0.98, 0.86, 0.35)
const DIM := Color(0.98, 0.86, 0.35, 0.55)
const NEAR := 14.0
const FAR := 9.0

var _rows: Array = []
var _optic: BinocularView


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	var was := _rows.size()
	_rows.clear()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		queue_redraw()
		return
	var eye := Player.local(get_tree())
	if _optic == null or not is_instance_valid(_optic):
		_optic = get_parent().find_child("BinocularView", true, false) as BinocularView
	var field := _optic.field_rect() if _optic != null else Rect2(Vector2.ZERO, size)
	for node in get_tree().get_nodes_in_group("kiwi"):
		var bird := node as Kiwi
		if bird == null or not is_instance_valid(bird) or not bird.is_marked():
			continue
		var at := bird.global_position + Vector3.UP * 0.95
		var local := cam.to_local(at)
		if local.z >= -0.2:
			continue
		var where := cam.unproject_position(at)
		if not field.has_point(where):
			continue
		var away := at.distance_to(eye.global_position) if eye != null else -local.z
		_rows.append({"at": where, "name": bird.kind_name(), "away": away,
			"fade": clampf(bird.mark_left() / 3.0, 0.25, 1.0)})
	if was != _rows.size() or not _rows.is_empty():
		queue_redraw()


func shown() -> int:
	return _rows.size()


func spot_of(kind: String) -> Vector2:
	for row in _rows:
		if String(row["name"]) == kind:
			return row["at"] as Vector2
	return Vector2.ONE * 99999.0


static func strokes(kind: String, at: Vector2, r: float) -> Array[PackedVector2Array]:
	match kind:
		"SNIPER":
			return _scope(at, r)
		"LASER":
			return _shield(at, r)
		"SENTRY":
			return _speaker(at, r)
		"MORTAR":
			return _bomb(at, r)
		"RUSHER":
			return _chevrons(at, r)
	var plain: Array[PackedVector2Array] = [_diamond(at, r)]
	return plain


static func _diamond(at: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([at + Vector2(0.0, -r), at + Vector2(r * 0.72, 0.0),
		at + Vector2(0.0, r), at + Vector2(-r * 0.72, 0.0), at + Vector2(0.0, -r)])


static func _arc(at: Vector2, r: float, from: float, to: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps + 1:
		var a := from + (to - from) * float(i) / float(steps)
		out.append(at + Vector2(cos(a), sin(a)) * r)
	return out


static func _line(a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, b])


static func _scope(at: Vector2, r: float) -> Array[PackedVector2Array]:
	var far := r * 1.4
	var gap := r * 0.35
	var out: Array[PackedVector2Array] = [_arc(at, r, 0.0, TAU, 28),
		_line(at + Vector2(-far, 0.0), at + Vector2(-gap, 0.0)),
		_line(at + Vector2(gap, 0.0), at + Vector2(far, 0.0)),
		_line(at + Vector2(0.0, -far), at + Vector2(0.0, -gap)),
		_line(at + Vector2(0.0, gap), at + Vector2(0.0, far))]
	return out


static func _shield(at: Vector2, r: float) -> Array[PackedVector2Array]:
	var w := r * 0.85
	var out: Array[PackedVector2Array] = [PackedVector2Array([at + Vector2(-w, -r), at + Vector2(w, -r),
		at + Vector2(w, r * 0.15), at + Vector2(0.0, r * 1.05), at + Vector2(-w, r * 0.15),
		at + Vector2(-w, -r)]),
		_line(at + Vector2(0.0, -r * 0.55), at + Vector2(0.0, r * 0.6))]
	return out


static func _speaker(at: Vector2, r: float) -> Array[PackedVector2Array]:
	var left := at + Vector2(-r, 0.0)
	var mouth := at + Vector2(r * 0.1, 0.0)
	var out: Array[PackedVector2Array] = [PackedVector2Array([left + Vector2(0.0, -r * 0.4),
		left + Vector2(r * 0.5, -r * 0.4), mouth + Vector2(0.0, -r), mouth + Vector2(0.0, r),
		left + Vector2(r * 0.5, r * 0.4), left + Vector2(0.0, r * 0.4), left + Vector2(0.0, -r * 0.4)]),
		_arc(mouth, r * 0.5, -0.9, 0.9, 8),
		_arc(mouth, r * 0.95, -0.9, 0.9, 10)]
	return out


static func _chevrons(at: Vector2, r: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for row in [-0.45, 0.25]:
		var tip := at + Vector2(0.0, r * row - r * 0.35)
		out.append(PackedVector2Array([tip + Vector2(-r * 0.75, r * 0.6), tip, tip + Vector2(r * 0.75, r * 0.6)]))
	return out


static func _bomb(at: Vector2, r: float) -> Array[PackedVector2Array]:
	var c := at + Vector2(r * 0.12, r * 0.22)
	var rr := r * 0.78
	var up := Vector2.from_angle(-PI * 0.75)
	var neck := c + up * rr
	var tip := neck + up * r * 0.5
	var out: Array[PackedVector2Array] = [_arc(c, rr, 0.0, TAU, 28),
		_line(neck, tip),
		_line(tip, tip + Vector2.from_angle(-PI * 0.75 - 0.7) * r * 0.32),
		_line(tip, tip + up * r * 0.32),
		_line(tip, tip + Vector2.from_angle(-PI * 0.75 + 0.7) * r * 0.32)]
	return out


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for row in _rows:
		var at: Vector2 = row["at"]
		var away: float = row["away"]
		var alpha: float = row["fade"]
		var r: float = lerpf(NEAR, FAR, clampf(away / 90.0, 0.0, 1.0))
		var ink := Color(INK, alpha)
		var kind := String(row["name"])
		for stroke: PackedVector2Array in strokes(kind, at, r):
			draw_polyline(stroke, ink, 2.0, true)
		if font == null:
			continue
		var label := "%s  %d m" % [kind, int(round(away))]
		var wide := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x
		font.draw_string(get_canvas_item(), at + Vector2(-wide * 0.5, -r * 1.5 - 6.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(DIM, alpha))
