class_name MarkTags
extends Control


const INK := Color(0.98, 0.86, 0.35)
const DIM := Color(0.98, 0.86, 0.35, 0.55)
const NEAR := 11.0
const FAR := 6.0

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


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for row in _rows:
		var at: Vector2 = row["at"]
		var away: float = row["away"]
		var alpha: float = row["fade"]
		var r: float = lerpf(NEAR, FAR, clampf(away / 90.0, 0.0, 1.0))
		var ink := Color(INK, alpha)
		draw_polyline(PackedVector2Array([
			at + Vector2(0.0, -r), at + Vector2(r * 0.72, 0.0),
			at + Vector2(0.0, r), at + Vector2(-r * 0.72, 0.0),
			at + Vector2(0.0, -r)]), ink, 2.0)
		if font == null:
			continue
		var label := "%s  %d m" % [String(row["name"]), int(round(away))]
		var wide := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x
		font.draw_string(get_canvas_item(), at + Vector2(-wide * 0.5, -r - 7.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(DIM, alpha))
