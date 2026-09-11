class_name VisionCone
extends Node


signal awareness_changed(value: float)
signal spotted(target: Node3D)

const NOTICING := 0.02

@export_group("Head")
## the cone rides this bone, so the idle clips that turn the bird's head turn its cone with it.
@export var head_bone_hint := "head"

@export_group("Cone")
## how far it can pick a player out DEAD AHEAD.
@export var sight_range := 45.0
## half angle at POINT BLANK, so 55 is a 110 degree cone at your feet.
@export var half_angle_deg := 55.0
## half angle at the FAR EDGE of the range.
@export var focus_angle_deg := 22.0
## only used when there is no head bone to sit on.
@export var eye_height := 0.45
## closer than this and neither the cone nor crouching helps you.
@export var point_blank := 2.0

@export_group("Timing")
## seconds of unbroken exposure at the far edge of the cone before the alarm goes up.
@export var notice_time := 1.4
@export var forget_speed := 0.7
## the bar fills at BASE plus GAIN times exposure, and exposure falls off with the SQUARE of the distance, so how long a...
@export var notice_base := 0.30
@export var notice_gain := 1.5
## crouching cuts how far it can pick you out, which is what makes crouch a stealth tool.
@export_range(0.1, 1.0) var crouch_range_scale := 0.45
## and flat on the ground.
@export_range(0.05, 1.0) var prone_range_scale := 0.22

@export_group("Sight line")
## only the world blocks sight, so a kiwi is never hidden behind another kiwi.
@export_flags_3d_physics var sight_mask := 1

var awareness := 0.0
var alerted := false
var last_seen := Vector3.ZERO

var _body: Node3D
var _target: Node3D
var _sent := 0.0
var _skeleton: Skeleton3D
var _bone := -1
var _bone_forward := Vector3.FORWARD
var _seen_once := false


func _ready() -> void:
	set_physics_process(false)
	_body = get_parent() as Node3D
	_find_target.call_deferred()
	## deferred because the owner sets the model's yaw in its own _ready, which runs after ours.
	_bind_head.call_deferred()


func _find_target() -> void:
	_target = Player.nearest(get_tree(), _eye() if _body != null else Vector3.ZERO)


func _most_exposed() -> Array:
	var best: Node3D = null
	var most := 0.0
	for who in Player.all(get_tree()):
		var seen := exposure_to(who)
		if seen > most:
			most = seen
			best = who
	return [best, most]


func poll(delta: float) -> void:
	if _body == null:
		return
	var looked := _most_exposed()
	var who := looked[0] as Node3D
	var exposure: float = looked[1]
	if who != null:
		_target = who
	if _target == null or not is_instance_valid(_target):
		_find_target()
		if _target == null:
			return

	if alerted:
		if exposure > 0.0:
			## seeing is not the alarm, noticing is: this only pins the quiet clock.
			last_seen = _target.global_position
			_seen_once = true
			Alarm.report_contact(last_seen)
		return

	if exposure > 0.0:
		last_seen = _target.global_position
		_seen_once = true
		Alarm.report_contact(last_seen)
		awareness += (notice_base + notice_gain * exposure) * delta
	else:
		awareness -= forget_speed * delta
	awareness = clampf(awareness, 0.0, notice_time)

	_report()
	if awareness >= notice_time:
		alerted = true
		spotted.emit(_target)


func exposure_to(who: Node3D) -> float:
	if _body == null or who == null:
		return 0.0
	if who.global_position.distance_to(_body.global_position) > maxf(sight_range, point_blank) + 2.0:
		return 0.0

	var reach := sight_range
	match stance_of(who):
		1:
			reach *= crouch_range_scale
		2:
			reach *= prone_range_scale

	var eye := _eye()
	var at := sight_point(who)
	var to := at - eye
	var distance := to.length()
	if distance > maxf(reach, point_blank):
		return 0.0

	if distance > point_blank and not _within_cone(to, _angle_at(distance, reach)):
		return 0.0
	if not has_line_to(at):
		return 0.0

	var near := 1.0 - distance / maxf(reach, 0.01)
	return clampf(near * near, 0.05, 1.0)


func _angle_at(distance: float, reach: float) -> float:
	return lerpf(half_angle_deg, focus_angle_deg,
		clampf(distance / maxf(reach, 0.01), 0.0, 1.0))


func sees_point(point: Vector3, max_distance: float) -> bool:
	if _body == null:
		return false
	var to := point - _eye()
	if to.length() > max_distance:
		return false
	return _within_cone(to) and has_line_to(point)


static func sight_point(who: Node3D) -> Vector3:
	var lift := 1.2
	match stance_of(who):
		1:
			lift = 0.55
		2:
			lift = 0.25
	var at := who.global_position + Vector3.UP * lift
	if who.has_method("lean_offset"):
		at += who.lean_offset() as Vector3
	return at


static func stance_of(who: Node3D) -> int:
	if who == null:
		return 0
	if who.has_method("is_prone") and who.is_prone():
		return 2
	if who.has_method("is_crouching") and who.is_crouching():
		return 1
	return 0


func has_line_to(point: Vector3) -> bool:
	if _body == null:
		return false
	var space := _body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(_eye(), point, sight_mask)
	if _body is CollisionObject3D:
		query.exclude = [(_body as CollisionObject3D).get_rid()]
	return space.intersect_ray(query).is_empty()


func rearm() -> void:
	alerted = false
	awareness = 0.0
	_report()


func level() -> float:
	return awareness / maxf(notice_time, 0.001)


func is_noticing() -> bool:
	return level() > NOTICING


func has_last_seen() -> bool:
	return _seen_once


func target() -> Node3D:
	return _target


func _bind_head() -> void:
	if _body == null:
		return
	for node in _body.find_children("*", "Skeleton3D", true, false):
		_skeleton = node as Skeleton3D
		break
	if _skeleton == null:
		return

	var hint := head_bone_hint.to_lower()
	for i in _skeleton.get_bone_count():
		if hint in _skeleton.get_bone_name(i).to_lower():
			_bone = i
			break
	if _bone < 0:
		_skeleton = null
		return

	var rest := (_skeleton.global_transform.basis
		* _skeleton.get_bone_global_rest(_bone).basis).orthonormalized()
	_bone_forward = rest.inverse() * (-_body.global_transform.basis.z)


func has_head() -> bool:
	return _bone >= 0


func facing() -> Vector3:
	var forward := -_body.global_transform.basis.z
	if _bone >= 0:
		var head := (_skeleton.global_transform.basis
			* _skeleton.get_bone_global_pose(_bone).basis).orthonormalized()
		var looking := head * _bone_forward
		if absf(looking.x) + absf(looking.z) > 0.05:
			forward = looking
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


func _eye() -> Vector3:
	if _bone >= 0:
		return (_skeleton.global_transform * _skeleton.get_bone_global_pose(_bone)).origin
	return _body.global_position + Vector3.UP * eye_height


func _within_cone(to: Vector3, half_angle := -1.0) -> bool:
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.0001:
		return true
	var limit := half_angle if half_angle >= 0.0 else half_angle_deg
	return rad_to_deg(facing().angle_to(flat.normalized())) <= limit


func _report() -> void:
	var value := level()
	if absf(value - _sent) < 0.02 and value > 0.0 and value < 1.0:
		return
	_sent = value
	awareness_changed.emit(value)
