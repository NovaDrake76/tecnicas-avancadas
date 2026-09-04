class_name HitMarker
extends Control

## the four diagonal strokes that snap onto the crosshair when a bb lands on something, white for a
## hit and red for one that put the target down. it is its OWN node rather than part of the
## crosshair, because the crosshair fades out while you are aiming and the confirmation you most
## want is the one for the shot you took down the sights.
##
## it is SILENT on purpose: the mark is the whole of the feedback. a game whose promise is that a
## missed bb makes no noise has no business making one for a hit.

@export var inner := 5.0
@export var outer := 14.0
@export var thickness := 3.0
## the kill marker is bigger and stays a little longer, so the two read differently at a glance.
@export var life := 0.28
@export var kill_life := 0.42
@export var kill_scale := 1.25
@export var hit_colour := Color(1.0, 1.0, 1.0, 0.95)
@export var kill_colour := Color(1.0, 0.28, 0.22)
## it snaps out to this and settles back, which is what makes it read as an impact and not a fade.
@export var pop := 1.4

const ARMS: Array[Vector2] = [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]

var _left := 0.0
var _span := 0.28
var _lethal := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(false)


func strike(killed := false) -> void:
	_lethal = killed
	_span = kill_life if killed else life
	_left = _span
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_left = maxf(0.0, _left - delta)
	if _left <= 0.0:
		set_process(false)
	queue_redraw()


func showing() -> bool:
	return _left > 0.0


func lethal() -> bool:
	return _lethal


func _draw() -> void:
	if _left <= 0.0:
		return
	var u := _left / _span
	var mid := size * 0.5
	## the pop is on u squared so it is nearly gone by the time the fade is halfway: a snap, then a
	## steady mark that fades, rather than a shape that shrinks all the way out.
	var grow := lerpf(1.0, pop, u * u) * (kill_scale if _lethal else 1.0)
	var colour := kill_colour if _lethal else hit_colour
	colour.a *= u
	for dark in [true, false]:
		var col := Color(0.0, 0.0, 0.0, 0.5 * u) if dark else colour
		var wide := thickness + 2.0 if dark else thickness
		for arm in ARMS:
			var dir := arm.normalized()
			draw_line(mid + dir * inner * grow, mid + dir * outer * grow, col, wide)
