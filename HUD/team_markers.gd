class_name TeamMarkers
extends Control

## the two things a teammate needs to be able to find: what they pointed at, and where they fell.
##
## both are the same screen-space job the extraction marker does, so they are one node: a world
## point, drawn where it is, sliding to the edge as an arrow when it is off the frame. they inherit
## that node's two hard lessons -- `unproject_position` MIRRORS a point behind the camera, so the
## sign of z in the camera's own space is what says in front or behind; and the clamp is taken as a
## ratio along the line from the middle of the screen, because clamping x and y separately moves
## the point off that line and the arrow then points at nothing.
##
## a DOWNED operative is the one marker here that is not allowed to be missed, and it is the reason
## this node exists at all: the game had a revive verb, a three second hold and a ring for it, and
## no way whatsoever to find the person it was for. in a two hundred metre compound that is a verb
## that does not exist. it is drawn through everything, at any distance, and it never clips away --
## the whole point of it is the moment when you cannot see them.
##
## the local operative is never drawn. you know where you are.

const MARGIN := Vector2(80.0, 80.0)
const SIZE := 12.0
const TEXT_SIZE := 18
const INK := Color(0.0, 0.0, 0.0, 0.75)
## a ping is the team's colour, cool and quiet; a body on the floor is the one urgent thing on
## the screen and wears the same red the alarm strip does.
const PING := Color(0.55, 0.86, 0.95)
const DOWN := Color(1.0, 0.36, 0.32)
## a downed operative is lifted to chest height, a ping is drawn on the thing it landed on.
const DOWN_LIFT := 1.0

var _rows: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## worked out here rather than in _draw, so a headless probe can read positions: a drawing cannot
## be read at all in a run with no window.
func _process(_delta: float) -> void:
	var was := _rows.size()
	_rows.clear()
	var cam := get_viewport().get_camera_3d()
	if cam != null and Run.state == Run.State.PLAYING:
		var me := Player.local(get_tree())
		for who in Player.downed(get_tree()):
			if who == me:
				continue
			_add(cam, who.global_position + Vector3.UP * DOWN_LIFT, "REVIVE", DOWN, true)
		for row in Pinger.all(get_tree()):
			_add(cam, row["at"] as Vector3, String(row["label"]), PING, false)
	if was != _rows.size() or not _rows.is_empty():
		queue_redraw()


func _add(cam: Camera3D, at: Vector3, label: String, tint: Color, urgent: bool) -> void:
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
	var edge := not rect.has_point(point)
	if edge:
		point = _clamp_to(rect, middle, point)
	_rows.append({"at": point, "label": label, "tint": tint, "edge": edge, "urgent": urgent,
		"away": cam.global_position.distance_to(at)})


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


## for the probe: how many markers are on screen, and where a named one is.
func shown() -> int:
	return _rows.size()


func has(label: String) -> bool:
	for row in _rows:
		if String(row["label"]) == label:
			return true
	return false


func spot_of(label: String) -> Vector2:
	for row in _rows:
		if String(row["label"]) == label:
			return row["at"] as Vector2
	return Vector2.ONE * 99999.0


func at_edge(label: String) -> bool:
	for row in _rows:
		if String(row["label"]) == label:
			return bool(row["edge"])
	return false


func _draw() -> void:
	var font := HudStyle.FACE
	for row in _rows:
		var at: Vector2 = row["at"]
		var tint: Color = row["tint"]
		if bool(row["edge"]):
			_arrow(at, (at - size * 0.5).normalized(), tint)
		elif bool(row["urgent"]):
			_cross(at, tint)
		else:
			_pip(at, tint)
		if font == null:
			continue
		var text := "%s  %d m" % [String(row["label"]), roundi(row["away"])]
		var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE).x
		var where := at + Vector2(-wide * 0.5, -SIZE - 8.0)
		draw_string_outline(font, where, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE, 5, INK)
		draw_string(font, where, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE, tint)


## a ping: a ring with a dot in it. deliberately not the mark's diamond and not the belief's hollow
## one -- three markers that all draw a diamond are three things the player has to read the words
## on to tell apart, and the words are the slowest part of a screen.
func _pip(at: Vector2, tint: Color) -> void:
	draw_arc(at, SIZE, 0.0, TAU, 24, INK, 4.0, true)
	draw_arc(at, SIZE, 0.0, TAU, 24, tint, 1.8, true)
	draw_circle(at, 2.6, tint)


## a downed operative: a cross, which is the one shape on this screen that means a person.
func _cross(at: Vector2, tint: Color) -> void:
	var r := SIZE * 1.1
	for pass_i in 2:
		var ink := INK if pass_i == 0 else tint
		var thick := 5.0 if pass_i == 0 else 2.4
		draw_line(at + Vector2(-r, 0.0), at + Vector2(r, 0.0), ink, thick)
		draw_line(at + Vector2(0.0, -r), at + Vector2(0.0, r), ink, thick)


func _arrow(at: Vector2, dir: Vector2, tint: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var points := PackedVector2Array([
		at + dir * SIZE, at - dir * SIZE * 0.6 + side * SIZE * 0.8,
		at - dir * SIZE * 0.6 - side * SIZE * 0.8])
	draw_polyline(points + PackedVector2Array([points[0]]), INK, 5.0, true)
	draw_colored_polygon(points, tint)
