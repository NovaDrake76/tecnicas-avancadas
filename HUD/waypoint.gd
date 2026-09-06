class_name Waypoint
extends Control


const MARGIN := Vector2(90.0, 90.0)
const SIZE := 14.0
const LIFT := 1.2
const COLOR := Color(0.45, 1.0, 0.62)
const INK := Color(0.0, 0.0, 0.0, 0.75)
const TEXT_SIZE := 20

var _target: Node3D
var _at_edge := false
var _where := Vector2.ZERO
var _distance := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	var want := _exfil()
	var on := want != null
	if visible != on:
		visible = on
	if not on:
		_target = null
		return
	_target = want
	_track()
	queue_redraw()


func _track() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _target == null or not is_instance_valid(_target):
		return
	var at := _target.global_position + Vector3.UP * LIFT
	_distance = cam.global_position.distance_to(at)
	var rect := Rect2(MARGIN, size - MARGIN * 2.0)
	var middle := size * 0.5
	var local := cam.global_transform.affine_inverse() * at
	var point := Vector2.ZERO
	if local.z < 0.0:
		point = cam.unproject_position(at)
	else:
		var away := Vector2(local.x, -local.y)
		if away.length_squared() < 0.0001:
			away = Vector2(0.0, 1.0)
		point = middle + away.normalized() * size.length()
	_at_edge = not rect.has_point(point)
	if _at_edge:
		point = _clamp_to(rect, middle, point)
	_where = point


func _exfil() -> Node3D:
	if Run.state != Run.State.PLAYING:
		return null
	for node in Run.objectives:
		var o := node as Objective
		if o == null or o.kind != Objective.Kind.EXFIL:
			continue
		if o.is_done() or not o.is_armed():
			continue
		return o
	return null


func marker_position() -> Vector2:
	return _where


func at_edge() -> bool:
	return _at_edge


func _draw() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if _at_edge:
		_arrow(_where, (_where - size * 0.5).normalized())
	else:
		_diamond(_where)
	_caption(_where)


func _clamp_to(rect: Rect2, middle: Vector2, point: Vector2) -> Vector2:
	var ray := point - middle
	if ray.length_squared() < 0.0001:
		return middle
	var half := rect.size * 0.5
	var reach := INF
	if absf(ray.x) > 0.0001:
		reach = minf(reach, half.x / absf(ray.x))
	if absf(ray.y) > 0.0001:
		reach = minf(reach, half.y / absf(ray.y))
	if reach == INF:
		return middle
	return middle + ray * reach


func _diamond(at: Vector2) -> void:
	var points := PackedVector2Array([
		at + Vector2(0.0, -SIZE), at + Vector2(SIZE, 0.0),
		at + Vector2(0.0, SIZE), at + Vector2(-SIZE, 0.0)])
	draw_polyline(points + PackedVector2Array([points[0]]), INK, 5.0, true)
	draw_polyline(points + PackedVector2Array([points[0]]), COLOR, 2.0, true)


func _arrow(at: Vector2, dir: Vector2) -> void:
	var side := Vector2(-dir.y, dir.x)
	var points := PackedVector2Array([
		at + dir * SIZE, at - dir * SIZE * 0.6 + side * SIZE * 0.8,
		at - dir * SIZE * 0.6 - side * SIZE * 0.8])
	draw_polyline(points + PackedVector2Array([points[0]]), INK, 5.0, true)
	draw_colored_polygon(points, COLOR)


func _caption(at: Vector2) -> void:
	var text := "EXTRACT  %d m" % roundi(_distance)
	var font := HudStyle.FACE
	var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE).x
	var where := at + Vector2(-wide * 0.5, SIZE + TEXT_SIZE + 4.0)
	draw_string_outline(font, where, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE, 5, INK)
	draw_string(font, where, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE, COLOR)
