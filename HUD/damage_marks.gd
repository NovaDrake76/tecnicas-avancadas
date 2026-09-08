class_name DamageMarks
extends Control


## how long a mark lives after the last hit from that direction.
@export var life := 1.6
## the width of the smear along the edge, at full strength.
@export var span_degrees := 42.0
## how far in from the edge the smear reaches, as a fraction of the half screen.
@export_range(0.2, 0.9) var depth := 0.4
@export var colour := Color(0.9, 0.08, 0.05)
## hits from within this distance of an earlier one refresh its mark instead of adding another.
@export var merge_within := 1.5

const SEGMENTS := 12

var _marks: Array = []
var _player: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func watch(player: Node) -> void:
	if _player != null and is_instance_valid(_player) and _player.hurt.is_connected(_on_hurt):
		_player.hurt.disconnect(_on_hurt)
	_player = player
	if _player != null and _player.has_signal("hurt"):
		_player.hurt.connect(_on_hurt)


func _on_hurt(amount: float, from: Vector3) -> void:
	var strength := clampf(amount / 25.0, 0.35, 1.0)
	for m in _marks:
		if (m["from"] as Vector3).distance_to(from) <= merge_within:
			m["from"] = from
			m["left"] = life
			m["strength"] = maxf(float(m["strength"]), strength)
			queue_redraw()
			return
	_marks.append({"from": from, "left": life, "strength": strength})
	queue_redraw()


func _process(delta: float) -> void:
	if _player != null and not is_instance_valid(_player):
		_player = null
		watch(Player.local(get_tree()))
	if _marks.is_empty():
		return
	for i in range(_marks.size() - 1, -1, -1):
		_marks[i]["left"] = float(_marks[i]["left"]) - delta
		if float(_marks[i]["left"]) <= 0.0:
			_marks.remove_at(i)
	queue_redraw()


func _draw() -> void:
	if _marks.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var centre := size * 0.5
	var span := deg_to_rad(span_degrees)
	for m in _marks:
		var strength := float(m["strength"])
		var fade := clampf(float(m["left"]) / life, 0.0, 1.0)
		_wedge(centre, _screen_angle(cam, m["from"]), span * lerpf(0.7, 1.0, strength), strength * fade * fade)


func _screen_angle(cam: Camera3D, from: Vector3) -> float:
	return AlertRing.bearing_to(cam, from) - PI * 0.5


func _wedge(centre: Vector2, mid: float, span: float, alpha: float) -> void:
	var inner := centre * (1.0 - depth)
	var outer := centre * 1.08
	for i in SEGMENTS:
		var a0 := mid - span * 0.5 + span * float(i) / SEGMENTS
		var a1 := mid - span * 0.5 + span * float(i + 1) / SEGMENTS
		var w0 := 0.5 - 0.5 * cos(TAU * float(i) / SEGMENTS)
		var w1 := 0.5 - 0.5 * cos(TAU * float(i + 1) / SEGMENTS)
		var points := PackedVector2Array([
			centre + Vector2(cos(a0) * inner.x, sin(a0) * inner.y),
			centre + Vector2(cos(a0) * outer.x, sin(a0) * outer.y),
			centre + Vector2(cos(a1) * outer.x, sin(a1) * outer.y),
			centre + Vector2(cos(a1) * inner.x, sin(a1) * inner.y)])
		var colours := PackedColorArray([Color(colour, 0.0), Color(colour, alpha * w0),
			Color(colour, alpha * w1), Color(colour, 0.0)])
		draw_polygon(points, colours)


func count() -> int:
	return _marks.size()


func mark_point(index: int) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null or index < 0 or index >= _marks.size():
		return Vector2.INF
	var centre := size * 0.5
	var a := _screen_angle(cam, _marks[index]["from"])
	return centre + Vector2(cos(a) * centre.x, sin(a) * centre.y)
