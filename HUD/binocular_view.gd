class_name BinocularView
extends Control


const FIELD := Vector2(0.80, 0.78)
const EDGE := Color(0.86, 0.92, 0.88)
const LINE := Color(0.78, 0.86, 0.82)

var _binocs: Binoculars
var _t := 0.0
var _mag := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bind.call_deferred()


func _bind() -> void:
	_binocs = get_tree().get_first_node_in_group("binoculars") as Binoculars


func _process(_delta: float) -> void:
	## re-found, because quitting to the menu frees the player and this with it, and a freed node compares equal to null.
	if _binocs == null or not is_instance_valid(_binocs):
		_bind()
		if _binocs == null:
			return
	var want := _binocs.amount()
	var mag := _binocs.magnification()
	if is_equal_approx(want, _t) and is_equal_approx(mag, _mag):
		return
	_t = want
	_mag = mag
	queue_redraw()


func amount() -> float:
	return _t


func field_rect() -> Rect2:
	if _t <= 0.5:
		return Rect2(Vector2.ZERO, size)
	var half := Vector2(size.x * FIELD.x, size.y * FIELD.y) * 0.5
	return Rect2(size * 0.5 - half, half * 2.0)


func _draw() -> void:
	if _t <= 0.01:
		return
	var middle := size * 0.5
	var half := Vector2(size.x * FIELD.x, size.y * FIELD.y) * 0.5
	var ink := Color(0.0, 0.0, 0.0, _t)

	draw_rect(Rect2(0.0, 0.0, size.x, middle.y - half.y), ink)
	draw_rect(Rect2(0.0, middle.y + half.y, size.x, size.y - (middle.y + half.y)), ink)
	draw_rect(Rect2(0.0, middle.y - half.y, middle.x - half.x, half.y * 2.0), ink)
	draw_rect(Rect2(middle.x + half.x, middle.y - half.y, size.x - (middle.x + half.x), half.y * 2.0), ink)
	var cut := minf(half.x, half.y) * 0.42
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := middle + Vector2(half.x * sx, half.y * sy)
			draw_colored_polygon(PackedVector2Array([
				corner,
				corner - Vector2(cut * sx, 0.0),
				corner - Vector2(0.0, cut * sy)]), ink)

	var edge := Color(EDGE, 0.5 * _t)
	var pts := PackedVector2Array([
		middle + Vector2(-half.x + cut, -half.y), middle + Vector2(half.x - cut, -half.y),
		middle + Vector2(half.x, -half.y + cut), middle + Vector2(half.x, half.y - cut),
		middle + Vector2(half.x - cut, half.y), middle + Vector2(-half.x + cut, half.y),
		middle + Vector2(-half.x, half.y - cut), middle + Vector2(-half.x, -half.y + cut),
		middle + Vector2(-half.x + cut, -half.y)])
	draw_polyline(pts, edge, 2.0)

	var mark := Color(LINE, 0.55 * _t)
	var span := half.x * 0.55
	draw_line(middle - Vector2(span, 0.0), middle + Vector2(span, 0.0), mark, 1.0)
	var step := span / 5.0
	for i in range(-5, 6):
		if i == 0:
			continue
		var tall := 9.0 if i % 5 == 0 else 5.0
		var x := step * float(i)
		draw_line(middle + Vector2(x, -tall), middle + Vector2(x, tall), mark, 1.0)
	draw_line(middle - Vector2(0.0, 16.0), middle + Vector2(0.0, 16.0), mark, 1.0)

	var font := ThemeDB.fallback_font
	if font != null:
		var label := "%.1fx" % _mag
		var at := middle + Vector2(half.x - 16.0, half.y - 14.0)
		var wide := font.get_string_size(label, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, 20).x
		font.draw_string(get_canvas_item(), at - Vector2(wide, 0.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(EDGE, 0.7 * _t))
