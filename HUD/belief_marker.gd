class_name BeliefMarker
extends Control

## where the COMPOUND thinks you are, drawn on the screen.
##
## the game already worked all of this out and kept it to itself. `Alarm.last_known` is the spot the
## garrison is working from, `knowledge_age()` is how old that belief is, and `search_point(seed)`
## fans each bird onto a ring that widens as it goes stale. the mortar shells that spot, hunters
## search it, a suppressing beam lights it -- and the player, who is the one person the whole thing
## is about, was never shown any of it. so being seen was a punishment and nothing else.
##
## this is Splinter Cell Conviction's last known position, which is the clearest thing the genre has
## ever done about this: the silhouette stays where the enemy last saw you, they commit to it, and
## you get to watch them do it. reviewers called it stealth training wheels and vital in the same
## paragraph, and it is the reason being spotted there is a play rather than a failure. ours is a
## marker rather than a ghost of the player, because ours also has to say how WIDE the search has
## got, which a silhouette cannot.
##
## it appears only once they have lost you (`REVEAL`). while a bird has eyes on you the compound's
## belief IS your position, and a diamond drawn on your own feet is noise on the screen at the exact
## moment the screen is busiest.

## CUT, at Nathan's call, and cut the way this project cuts things: the node stays wired, the rule
## below stays exactly as it was, and the drawing is switched off. Putting it back on screen is this
## one flag -- the same bargain a sound Nathan did not want keeps when it loses its clips and keeps
## its call site. What the compound believes is not the player's business to be shown; the birds
## still work from it, the mortar still shells it, and a player who wants to know where the search
## went has to read the birds instead of a diagram.
@export var shown := false

## seconds of nobody seeing you before the belief is worth drawing.
const REVEAL := 0.6
## how far inside the frame the marker may sit once it clamps to an edge.
const MARGIN := Vector2(90.0, 90.0)
const SIZE := 13.0
## up from the ground, so the diamond sits at chest height on the spot rather than at its ankles.
const LIFT := 1.0
## points around the search ring. it is drawn on the ground, so it reads as an area rather than
## as a halo around the marker.
const RING_STEPS := 40
## SEARCHING and ALARM, the same two colours the alert ring uses for the same two facts.
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


## worked out here rather than in _draw, the rule the extraction marker and the tags both follow:
## a headless probe can read a position and cannot read a drawing.
func _process(_delta: float) -> void:
	var was := _shown
	_shown = _believable()
	if visible != _shown:
		visible = _shown
	if _shown:
		_track()
	if _shown or was:
		queue_redraw()


## is there a belief worth drawing: the compound is looking for somebody, it has a spot to look at,
## and nobody can see the player right now.
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
	## behind the camera `unproject_position` mirrors the point through the centre, so a marker
	## placed with it swings to the wrong side and sends the player away from the thing it names.
	## the camera's own space answers it: the sign of z is in front or behind.
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


## the search ring, drawn flat on the ground at the spot. it is the honest half of the marker: the
## diamond says where they think you were, the ring says how much of that they still believe, and
## it is the difference between walking away and having to leave the area. drawn only when the
## WHOLE circle is in front of the camera -- a ring with points behind the eye comes back as a
## shape turned inside out, which reads as a bug rather than as a search.
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


## the point where the line from the middle of the screen out to the marker leaves the frame,
## taken as a ratio along that line: clamping x and y on their own moves the point off the line
## and the arrow then points at nothing.
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


## for the probe.
func is_shown() -> bool:
	return _shown


func marker_position() -> Vector2:
	return _where


func at_edge() -> bool:
	return _at_edge


## the search radius in METRES, which is what the ring is drawn at.
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


## hollow, and the same diamond the tags use, because it is the same claim: a thing is at this
## point. it is not the mark's solid colour, and it does not wear a name, so a marked bird and a
## place the garrison is searching can never be read as the same object.
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


## two facts and no more: they are looking, and they are looking THERE. the distance is what
## decides whether the player walks away or has to move now.
func _caption(at: Vector2, tint: Color) -> void:
	var text := "LAST SEEN  %d m" % roundi(_distance)
	var font := HudStyle.FACE
	if font == null:
		return
	var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE).x
	var where := at + Vector2(-wide * 0.5, SIZE + TEXT_SIZE + 4.0)
	draw_string_outline(font, where, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE, 5, INK)
	draw_string(font, where, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE, tint)
