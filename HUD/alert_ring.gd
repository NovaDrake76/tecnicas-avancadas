class_name AlertRing
extends Control


@export var radius := 92.0
@export var thickness := 8.0
@export var arc_degrees := 30.0
@export var calm := Color(1.0, 0.82, 0.35)
@export var alarmed := Color(1.0, 0.35, 0.3)
@export var backing := Color(0.0, 0.0, 0.0, 0.45)

var _watchers := {}
var _tiers := {}
var _blink := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_watcher(who: Node3D, value: float) -> void:
	if who == null:
		return
	if value <= VisionCone.NOTICING:
		_watchers.erase(who)
	else:
		_watchers[who] = value
	queue_redraw()


func set_tier(who: Node3D, tier: int) -> void:
	if who == null:
		return
	if tier <= Kiwi.Alert.CURIOUS:
		_tiers.erase(who)
	else:
		_tiers[who] = tier
		if tier >= Kiwi.Alert.HUNTING:
			_watchers[who] = 1.0
	queue_redraw()


func clear() -> void:
	_watchers.clear()
	_tiers.clear()
	queue_redraw()


func watcher_count() -> int:
	return _watchers.size()


func watching(who: Node3D) -> bool:
	return _watchers.has(who)


static func bearing_to(cam: Camera3D, point: Vector3) -> float:
	var local := cam.global_transform.affine_inverse() * point
	return atan2(local.x, -local.z)


func _process(delta: float) -> void:
	_blink += delta
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
			_tiers.erase(who)
			continue
		var tier: int = int(_tiers.get(who, Kiwi.Alert.SUSPICIOUS))
		var value: float = clampf(float(_watchers[who]), 0.0, 1.0)
		var shade := calm.lerp(alarmed, value)
		if tier == Kiwi.Alert.CALLING:
			shade = alarmed if fmod(_blink, 0.24) < 0.12 else backing.lerp(alarmed, 0.35)
		elif tier == Kiwi.Alert.ENGAGED:
			shade = alarmed
		elif tier == Kiwi.Alert.HUNTING:
			shade = calm
		var mid := bearing_to(cam, (who as Node3D).global_position) - PI * 0.5
		draw_arc(centre, radius, mid - span * 0.5, mid + span * 0.5, 20,
			backing, thickness + 5.0, true)
		draw_arc(centre, radius, mid - span * 0.5 * value, mid + span * 0.5 * value, 20,
			shade, thickness, true)
