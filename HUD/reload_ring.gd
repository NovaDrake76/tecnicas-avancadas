class_name ReloadRing
extends Control


@export var radius := 22.0
@export var thickness := 3.0
## the ring is never drawn from nothing.
@export var start_arc_deg := 24.0
@export var colour := Color(0.95, 0.97, 0.92)
@export var backing := Color(0.0, 0.0, 0.0, 0.35)

var _gun: Gun
var _job: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func watch(gun: Gun) -> void:
	_gun = gun
	queue_redraw()


func watch_job(job: Node) -> void:
	_job = job
	queue_redraw()


func job_running() -> bool:
	return _job != null and is_instance_valid(_job) and _job.is_working()


func is_showing() -> bool:
	if job_running():
		return true
	return _gun != null and is_instance_valid(_gun) and _gun.is_reloading()


func arc_deg() -> float:
	if not is_showing():
		return 0.0
	var done: float = _job.progress() if job_running() else _gun.reload_fraction()
	return start_arc_deg + (360.0 - start_arc_deg) * clampf(done, 0.0, 1.0)


func _process(_delta: float) -> void:
	## redrawn once more on the frame the reload ends, so the ring clears.
	if is_showing() or _was_showing:
		queue_redraw()
	_was_showing = is_showing()

var _was_showing := false


func _draw() -> void:
	if not is_showing():
		return
	var centre := size * 0.5
	var sweep := deg_to_rad(arc_deg())
	var from := -PI * 0.5
	draw_arc(centre, radius, 0.0, TAU, 48, backing, thickness + 2.0, true)
	draw_arc(centre, radius, from, from + sweep, 48, colour, thickness, true)
	if job_running():
		_draw_case(centre)
	else:
		_draw_round(centre)


func _draw_round(centre: Vector2) -> void:
	var box := glyph_box()
	RoundGlyph.draw_on(self, centre - box * 0.5, box, colour)


func glyph_box() -> Vector2:
	return Vector2(radius * 0.34, radius * 0.86)


## the outline the ring is wearing, for a check that it is the same round the fire mode row draws.
func glyph_points() -> PackedVector2Array:
	if job_running():
		return PackedVector2Array()
	var box := glyph_box()
	return RoundGlyph.outline(size * 0.5 - box * 0.5, box)


func _draw_case(centre: Vector2) -> void:
	var w := 11.0
	var h := 8.0
	draw_rect(Rect2(centre - Vector2(w, h) * 0.5, Vector2(w, h)), colour, false, 1.5)
	draw_line(centre - Vector2(w * 0.5, 0.0), centre + Vector2(w * 0.5, 0.0), colour, 1.5)
