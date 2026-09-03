class_name AlertRing
extends Control

## one arc per kiwi that is currently noticing you, sitting on a ring around the crosshair at the
## bearing of that bird. a single bar in the middle says how close you are to being seen but never
## says by whom, which is the one thing you need in order to do something about it.

@export var radius := 92.0
@export var thickness := 8.0
@export var arc_degrees := 30.0
@export var calm := Color(1.0, 0.82, 0.35)
@export var alarmed := Color(1.0, 0.35, 0.3)
@export var backing := Color(0.0, 0.0, 0.0, 0.45)

var _watchers := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## the state arrives by signal. only the BEARING is recomputed per frame, because the player
## turning is what moves the arc, and that is drawing rather than asking the world anything.
func set_watcher(who: Node3D, value: float) -> void:
	if who == null:
		return
	## the same threshold the bird itself acts on, so an arc on the ring means a bird that has
	## stopped and squared up to you, never a bird still wandering about.
	if value <= VisionCone.NOTICING:
		_watchers.erase(who)
	else:
		_watchers[who] = value
	queue_redraw()


func clear() -> void:
	_watchers.clear()
	queue_redraw()


func watcher_count() -> int:
	return _watchers.size()


## 0 straight ahead, positive to the right, +-PI behind you.
static func bearing_to(cam: Camera3D, point: Vector3) -> float:
	var local := cam.global_transform.affine_inverse() * point
	return atan2(local.x, -local.z)


func _process(_delta: float) -> void:
	if not _watchers.is_empty():
		queue_redraw()


func _draw() -> void:
	if _watchers.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var centre := size * 0.5
	var span := deg_to_rad(arc_degrees)
	for who in _watchers.keys():
		if not is_instance_valid(who):
			_watchers.erase(who)
			continue
		var value: float = clampf(float(_watchers[who]), 0.0, 1.0)
		## screen angles run from +X and clockwise, so straight ahead is a quarter turn up.
		var mid := bearing_to(cam, (who as Node3D).global_position) - PI * 0.5
		draw_arc(centre, radius, mid - span * 0.5, mid + span * 0.5, 20,
			backing, thickness + 5.0, true)
		draw_arc(centre, radius, mid - span * 0.5 * value, mid + span * 0.5 * value, 20,
			calm.lerp(alarmed, value), thickness, true)
