class_name Waypoint
extends Control

## the way out, drawn ON THE SCREEN rather than on the ground.
##
## it was a green ring lying in the grass, and a ring on the ground can only be seen from somewhere
## it can be seen from: with a hill, a container or a wall between the player and the extraction it
## says nothing at all, which is exactly the moment the player needs telling. worse, it reads as a
## piece of level -- a glowing circle among crates and barrels looks like something to interact with,
## not like a direction to walk in.
##
## a screen marker has neither problem. it is a direction and a DISTANCE, it survives anything being
## in the way, and when the point is off the frame it slides to the edge and becomes an arrow, so it
## can still be followed while the player is looking somewhere else entirely.
##
## it only ever draws the way out, and only once the way out is armed. the objectives themselves are
## deliberately not marked: finding them is the mission, and leaving is not.

## how far inside the frame the marker is allowed to sit once it clamps to an edge.
const MARGIN := Vector2(90.0, 90.0)
## the diamond's radius on screen.
const SIZE := 14.0
## up from the objective's own origin, so the marker sits at head height instead of at the ankles of
## whatever is standing on the spot.
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


## polled rather than driven by a signal: the projection changes every time the player turns, so
## this control is redrawing every frame regardless, and asking Run for the objective in the same
## place keeps "is there a way out yet" and "where is it on screen" as one answer per frame.
##
## WHERE the marker goes is worked out here and not in _draw. a drawing function that also decides
## things can only be checked by drawing, and this project has been bitten three times by layout
## measured off the wrong thing; with the position settled in _process a probe can read it in a
## headless run, where nothing is drawn at all.
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
	## behind the camera unproject_position mirrors the point through the centre, so a marker placed
	## with it would swing to the WRONG side of the screen and lead the player away from the thing
	## they are being sent to. the camera's own space answers it: the sign of z is in front or
	## behind, and x and y are the direction to turn either way.
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


## the way out, once there IS one. armed means every required objective is done, which is the same
## test the objective itself uses to decide whether it can be stood on.
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


## where the marker sits for a probe to read, in screen pixels, and whether it had to clamp.
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


## the point where the line from the middle of the screen out to the marker leaves the frame. done
## as a ratio on each axis rather than by clamping x and y on their own: clamping both moves the
## point OFF that line and into a corner, and the arrow then points somewhere nothing is.
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
	## the dark pass first and wider, for the same reason the crosshair has one: a thin bright line
	## over a lit background has no edge of its own and disappears into whatever is behind it.
	draw_polyline(points + PackedVector2Array([points[0]]), INK, 5.0, true)
	draw_polyline(points + PackedVector2Array([points[0]]), COLOR, 2.0, true)


func _arrow(at: Vector2, dir: Vector2) -> void:
	var side := Vector2(-dir.y, dir.x)
	var points := PackedVector2Array([
		at + dir * SIZE, at - dir * SIZE * 0.6 + side * SIZE * 0.8,
		at - dir * SIZE * 0.6 - side * SIZE * 0.8])
	draw_polyline(points + PackedVector2Array([points[0]]), INK, 5.0, true)
	draw_colored_polygon(points, COLOR)


## the distance is the half of this that is actually information: the direction is already the
## marker's position, and how far it is decides whether the player runs or sneaks the rest of it.
func _caption(at: Vector2) -> void:
	var text := "EXTRACT  %d m" % roundi(_distance)
	var font := HudStyle.FACE
	var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE).x
	var where := at + Vector2(-wide * 0.5, SIZE + TEXT_SIZE + 4.0)
	draw_string_outline(font, where, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE, 5, INK)
	draw_string(font, where, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE, COLOR)
