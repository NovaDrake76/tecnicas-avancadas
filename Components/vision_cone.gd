class_name VisionCone
extends Node

## what one kiwi can see. it owns only "have I noticed the player", never what to do about it.
## the owner drives it by hand so a downed body simply stops looking.

signal awareness_changed(value: float)
signal spotted(target: Node3D)

@export_group("Head")
## the cone rides this bone, so the idle clips that turn the bird's head turn its cone with it.
## anything without a matching bone falls back to the way its body is facing.
@export var head_bone_hint := "head"

@export_group("Cone")
@export var sight_range := 20.0
## half angle, so 55 is a 110 degree cone in front of the bird.
@export var half_angle_deg := 55.0
## only used when there is no head bone to sit on.
@export var eye_height := 0.45
## closer than this and neither the cone nor crouching helps you.
@export var point_blank := 2.0

@export_group("Timing")
## seconds of unbroken exposure at the far edge of the cone before the alarm goes up.
@export var notice_time := 1.4
@export var forget_speed := 0.7
## crouching cuts how far it can pick you out, which is what makes crouch a stealth tool.
@export_range(0.1, 1.0) var crouch_range_scale := 0.45

@export_group("Sight line")
## only the world blocks sight, so a kiwi is never hidden behind another kiwi.
@export_flags_3d_physics var sight_mask := 1

var awareness := 0.0
var alerted := false

var _body: Node3D
var _target: Node3D
var _sent := 0.0
var _skeleton: Skeleton3D
var _bone := -1
var _bone_forward := Vector3.FORWARD


func _ready() -> void:
	set_physics_process(false)
	_body = get_parent() as Node3D
	_find_target.call_deferred()
	## deferred because the owner sets the model's yaw in its own _ready, which runs after ours.
	_bind_head.call_deferred()


func _find_target() -> void:
	_target = get_tree().get_first_node_in_group("player") as Node3D


## called by the owner every physics tick while it is still standing.
func poll(delta: float) -> void:
	if alerted or _body == null:
		return
	if _target == null or not is_instance_valid(_target):
		_find_target()
		return

	var exposure := exposure_to(_target)
	if exposure > 0.0:
		## standing in the open right in front of it is noticed in a moment, a far edge sighting takes a while.
		awareness += (0.55 + exposure) * delta
	else:
		awareness -= forget_speed * delta
	awareness = clampf(awareness, 0.0, notice_time)

	_report()
	if awareness >= notice_time:
		alerted = true
		spotted.emit(_target)


## 0 when unseen, otherwise how plainly, which is what makes closer mean quicker.
func exposure_to(target: Node3D) -> float:
	if _body == null or target == null:
		return 0.0

	var reach := sight_range
	if target.has_method("is_crouching") and target.is_crouching():
		reach *= crouch_range_scale

	var eye := _eye()
	var at := target.global_position + Vector3.UP * 0.9
	var to := at - eye
	var distance := to.length()
	if distance > maxf(reach, point_blank):
		return 0.0

	if distance > point_blank and not _within_cone(to):
		return 0.0
	if not has_line_to(at):
		return 0.0

	return clampf(1.0 - distance / maxf(reach, 0.01), 0.12, 1.0)


## the same eyes pointed at a spot rather than at the player, for the witness rule.
func sees_point(point: Vector3, max_distance: float) -> bool:
	if _body == null:
		return false
	var to := point - _eye()
	if to.length() > max_distance:
		return false
	return _within_cone(to) and has_line_to(point)


func has_line_to(point: Vector3) -> bool:
	if _body == null:
		return false
	var space := _body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(_eye(), point, sight_mask)
	if _body is CollisionObject3D:
		query.exclude = [(_body as CollisionObject3D).get_rid()]
	return space.intersect_ray(query).is_empty()


## lets an owner that has finished reacting go back to watching without counting twice.
func rearm() -> void:
	alerted = false
	awareness = 0.0
	_report()


func level() -> float:
	return awareness / maxf(notice_time, 0.001)


## the rig's bone axes are the rigger's business, so nothing here assumes one. at rest the bird
## looks where its body looks, and that one comparison fixes the direction for good.
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


## where the eyes are pointing, flattened. pitch is left out on purpose: a bird that dips its
## beak to peck would go blind, and the player cannot read that from behind.
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


func _within_cone(to: Vector3) -> bool:
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.0001:
		return true
	return rad_to_deg(facing().angle_to(flat.normalized())) <= half_angle_deg


## the hud draws this, so it may not fire every tick for every bird on the map.
func _report() -> void:
	var value := level()
	if absf(value - _sent) < 0.02 and value > 0.0 and value < 1.0:
		return
	_sent = value
	awareness_changed.emit(value)
