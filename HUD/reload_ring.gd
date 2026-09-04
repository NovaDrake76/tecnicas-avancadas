class_name ReloadRing
extends Control

## how long is left on the thing the player is waiting for: a ring that closes around the point of
## aim. there is no animation to watch for either of them, so this is the only readout of the one
## thing being decided in that moment, whether there is time.
##
## it serves a RELOAD and a mission JOB, on purpose. taking a case and putting a charge on a crate
## were unreadable without it -- press once and stand still looks identical to press once and
## nothing happened -- and inventing a second dial for it would have taught the player two shapes
## for one sentence. a magazine is drawn inside for a reload, a case for a job.

@export var radius := 22.0
@export var thickness := 3.0
## the ring is never drawn from nothing. at zero it is invisible for the first tenth of a second,
## which is exactly when the player is asking whether to hold their ground.
@export var start_arc_deg := 24.0
@export var colour := Color(0.95, 0.97, 0.92)
@export var backing := Color(0.0, 0.0, 0.0, 0.35)

var _gun: Gun
## anything that answers is_working() and progress(): an Objective, in practice.
var _job: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## the hud hands over the weapon in hand. the ring reads that one node's timer each frame while it
## reloads, which is drawing a state that already exists, not asking the scene for it.
func watch(gun: Gun) -> void:
	_gun = gun
	queue_redraw()


## the hud hands over the job the player has started. null clears it.
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
	## redrawn while a reload runs and once more on the frame it ends, so the ring clears.
	if is_showing() or _was_showing:
		queue_redraw()
	_was_showing = is_showing()

var _was_showing := false


func _draw() -> void:
	if not is_showing():
		return
	var centre := size * 0.5
	var sweep := deg_to_rad(arc_deg())
	## from twelve o'clock, clockwise, the way every progress dial the player has seen fills.
	var from := -PI * 0.5
	draw_arc(centre, radius, 0.0, TAU, 48, backing, thickness + 2.0, true)
	draw_arc(centre, radius, from, from + sweep, 48, colour, thickness, true)
	if job_running():
		_draw_case(centre)
	else:
		_draw_magazine(centre)


## a small magazine glyph: a body with a rounded base plate and a feed lip, all in one colour.
func _draw_magazine(centre: Vector2) -> void:
	var w := radius * 0.32
	var h := radius * 0.55
	var body := Rect2(centre + Vector2(-w * 0.5, -h * 0.5), Vector2(w, h))
	draw_rect(body, colour, false, 1.5)
	var t := radius * 0.11
	draw_rect(Rect2(body.position + Vector2(-t * 0.4, h - t), Vector2(w + t * 0.8, t)), colour, true)
	draw_line(body.position + Vector2(t * 0.6, t), body.position + Vector2(w - t * 0.6, t), colour, radius * 0.045)


## a case rather than a magazine, so the player can tell at a glance which of the two waits they are
## in without reading anything.
func _draw_case(centre: Vector2) -> void:
	var w := 11.0
	var h := 8.0
	draw_rect(Rect2(centre - Vector2(w, h) * 0.5, Vector2(w, h)), colour, false, 1.5)
	draw_line(centre - Vector2(w * 0.5, 0.0), centre + Vector2(w * 0.5, 0.0), colour, 1.5)
