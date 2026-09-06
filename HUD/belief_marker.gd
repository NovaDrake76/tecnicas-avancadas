class_name BeliefMarker
extends Control


## CUT, at Nathan's call, and cut the way this project cuts things: the node stays wired, the rule below stays exactly a...
@export var shown := false

const REVEAL := 0.6
const MARGIN := Vector2(90.0, 90.0)
const SIZE := 13.0
const LIFT := 1.0
const RING_STEPS := 40
const WARM := Color(0.98, 0.74, 0.24)
const HOT := Color(1.0, 0.42, 0.32)
const INK := Color(0.0, 0.0, 0.0, 0.75)
const TEXT_SIZE := 19

var _shown := false
var _at_edge := false
var _where := Vector2.ZERO
var _ring := PackedVector2Array()
var _radius := 0.0
var _distance := 0.0
var _hot := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	var was := _shown
	_shown = _believable()
	if visible != _shown:
		visible = _shown
	if _shown:
		_track()
	if _shown or was:
		queue_redraw()


func _believable() -> bool:
	if not shown:
		return false
	if Run.state != Run.State.PLAYING:
		return false
	if not Alarm.is_hot() or not Alarm.has_last_known:
		return false
	return Alarm.knowledge_age() >= REVEAL


func _track() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_shown = false
		return
	_hot = Alarm.stage == Alarm.Stage.ALARM
	_radius = Alarm.search_spread()
	var ground := Alarm.last_known
	var at := ground + Vector3.UP * LIFT
	_distance = cam.global_position.distance_to(at)

	var rect := Rect2(MARGIN, size - MARGIN * 2.0)
	var middle := size * 0.5
	var local := cam.to_local(at)
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
	_ring = _ring_points(cam, ground)


func _ring_points(cam: Camera3D, ground: Vector3) -> PackedVector2Array:
	var out := PackedVector2Array()
	if _radius <= 0.5:
		return out
	for i in RING_STEPS + 1:
		var a := TAU * float(i) / float(RING_STEPS)
		var spot := ground + Vector3(cos(a), 0.0, sin(a)) * _radius
		if cam.to_local(spot).z >= -0.2:
			return PackedVector2Array()
		out.append(cam.unproject_position(spot))
	return out


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


func is_shown() -> bool:
	return _shown


func marker_position() -> Vector2:
	return _where


func at_edge() -> bool:
	return _at_edge


func ring_radius() -> float:
	return _radius


func ring_drawn() -> bool:
	return _ring.size() > 2


func _draw() -> void:
	if not _shown:
		return
	var tint := HOT if _hot else WARM
	if _ring.size() > 2:
		draw_polyline(_ring, Color(INK.r, INK.g, INK.b, 0.5), 4.0, true)
		draw_polyline(_ring, Color(tint, 0.45), 1.5, true)
	if _at_edge:
		_arrow(_where, (_where - size * 0.5).normalized(), tint)
	else:
		_diamond(_where, tint)
	_caption(_where, tint)


func _diamond(at: Vector2, tint: Color) -> void:
	var points := PackedVector2Array([
		at + Vector2(0.0, -SIZE), at + Vector2(SIZE * 0.78, 0.0),
		at + Vector2(0.0, SIZE), at + Vector2(-SIZE * 0.78, 0.0),
		at + Vector2(0.0, -SIZE)])
	draw_polyline(points, INK, 5.0, true)
	draw_polyline(points, tint, 2.0, true)
	draw_line(at + Vector2(-SIZE * 0.34, 0.0), at + Vector2(SIZE * 0.34, 0.0), tint, 2.0)


func _arrow(at: Vector2, dir: Vector2, tint: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var points := PackedVector2Array([
		at + dir * SIZE, at - dir * SIZE * 0.6 + side * SIZE * 0.8,
		at - dir * SIZE * 0.6 - side * SIZE * 0.8])
	draw_polyline(points + PackedVector2Array([points[0]]), INK, 5.0, true)
	draw_colored_polygon(points, tint)


func _caption(at: Vector2, tint: Color) -> void:
	var text := "LAST SEEN  %d m" % roundi(_distance)
	var font := HudStyle.FACE
	if font == null:
		return
	var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE).x
	var where := at + Vector2(-wide * 0.5, SIZE + TEXT_SIZE + 4.0)
	draw_string_outline(font, where, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE, 5, INK)
	draw_string(font, where, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE, tint)
