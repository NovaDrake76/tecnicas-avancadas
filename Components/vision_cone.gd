class_name VisionCone
extends Node

## what one kiwi can see. it owns only "have I noticed the player", never what to do about it.
## the owner drives it by hand so a downed body simply stops looking.

signal awareness_changed(value: float)
signal spotted(target: Node3D)

## the level at which a bird counts as NOTICING you: the hud puts an arc on the ring at its
## bearing, and the bird itself stops and squares up to you. one number, so what you can see on
## screen and what the bird is doing about it can never disagree.
const NOTICING := 0.02

@export_group("Head")
## the cone rides this bone, so the idle clips that turn the bird's head turn its cone with it.
## anything without a matching bone falls back to the way its body is facing.
@export var head_bone_hint := "head"

@export_group("Cone")
## how far it can pick a player out DEAD AHEAD. these are soldiers on watch, not birds: MGSV's
## guards spot a standing player at 70-80 m by day and 50-60 m at night, Far Cry 5's outpost guards
## are described as reaching about 50, and Breakpoint's rule is that grunts are shorter than snipers
## and drones. 45 is that band scaled to levels about 200 m across, and it is per bird so the tiers
## are real: the sniper's scene sets 70 and the mortar's 20, because a crew looking down a tube is
## not scanning the treeline.
@export var sight_range := 45.0
## half angle at POINT BLANK, so 55 is a 110 degree cone at your feet.
@export var half_angle_deg := 55.0
## half angle at the FAR EDGE of the range. the cone narrows with distance, which is the standard
## production shape (a narrow focused cone that reaches far plus a wide peripheral one that does
## not) written as one continuous rule, the way The Last of Us makes the angle of view inversely
## proportional to distance. without it, tripling the range would also mean being picked out at
## 40 m from 54 degrees off the bird's nose, and that is what makes long sight feel like cheating.
@export var focus_angle_deg := 22.0
## only used when there is no head bone to sit on.
@export var eye_height := 0.45
## closer than this and neither the cone nor crouching helps you.
@export var point_blank := 2.0

@export_group("Timing")
## seconds of unbroken exposure at the far edge of the cone before the alarm goes up.
@export var notice_time := 1.4
@export var forget_speed := 0.7
## the bar fills at BASE plus GAIN times exposure, and exposure falls off with the SQUARE of the
## distance, so how long a bird needs to be sure is what range actually buys the player: about
## 0.8 s at its feet, 2 s at half range and 3.7 s at the edge. that gap is the whole reason long
## sight is fair -- the ring puts an arc up at 2 percent of the bar, so a distant bird noticing you
## is something you can see coming and break, rather than a gotcha.
@export var notice_base := 0.30
@export var notice_gain := 1.5
## crouching cuts how far it can pick you out, which is what makes crouch a stealth tool.
@export_range(0.1, 1.0) var crouch_range_scale := 0.45

@export_group("Sight line")
## only the world blocks sight, so a kiwi is never hidden behind another kiwi.
@export_flags_3d_physics var sight_mask := 1

var awareness := 0.0
var alerted := false
## where the target was the last time these eyes actually had it. the owner turns to this when
## the head goes back to centre, which is what stops the bird's own idle clip from swinging the
## cone off something it has already half noticed.
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
	_target = get_tree().get_first_node_in_group("player") as Node3D


## called by the owner every physics tick while it is still standing.
func poll(delta: float) -> void:
	if _body == null:
		return
	if _target == null or not is_instance_valid(_target):
		_find_target()
		return

	## a bird that has already raised the alarm stops FILLING its bar, because there is nothing left
	## to warn about, but it does not stop LOOKING. while it can see you, the compound's last known
	## spot is where you actually are: that is what the mortar shells, what a beam suppresses and
	## what the gunship orbits. without this every one of them worked from the place you were
	## standing when the bird first caught you, for the rest of the fight.
	if alerted:
		if exposure_to(_target) > 0.0:
			last_seen = _target.global_position
			_seen_once = true
			Alarm.report_contact(last_seen)
		return

	var exposure := exposure_to(_target)
	if exposure > 0.0:
		last_seen = _target.global_position
		_seen_once = true
		## eyes on the player keep the garrison from calming down. seeing is not the alarm, noticing
		## is, so this only pins the quiet clock.
		Alarm.report_contact(last_seen)
		## standing in the open right in front of it is noticed in a moment, a far edge sighting takes a while.
		awareness += (notice_base + notice_gain * exposure) * delta
	else:
		awareness -= forget_speed * delta
	awareness = clampf(awareness, 0.0, notice_time)

	_report()
	if awareness >= notice_time:
		alerted = true
		spotted.emit(_target)


## 0 when unseen, otherwise how plainly, which is what makes closer mean quicker.
func exposure_to(who: Node3D) -> float:
	if _body == null or who == null:
		return 0.0

	var reach := sight_range
	if who.has_method("is_crouching") and who.is_crouching():
		reach *= crouch_range_scale

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


## the half angle this bird can pick a player out at, at that distance: wide at its feet, narrow at
## the edge of its range.
func _angle_at(distance: float, reach: float) -> float:
	return lerpf(half_angle_deg, focus_angle_deg,
		clampf(distance / maxf(reach, 0.01), 0.0, 1.0))


## the same eyes pointed at a spot rather than at the player, for the witness rule. this one keeps
## the FULL cone at every distance: it is asked about a body going down inside witness_radius and
## about a player a hunter is already closing on, both near and actively looked for. narrowing it
## with distance the way exposure_to does would quietly shrink the witness rule, which is its own
## promise and its own number.
func sees_point(point: Vector3, max_distance: float) -> bool:
	if _body == null:
		return false
	var to := point - _eye()
	if to.length() > max_distance:
		return false
	return _within_cone(to) and has_line_to(point)


## where on the player the eyes test: shoulder standing, chest crouched. a kiwi's eye is 0.35 m up,
## so this is what decides whether an 0.85 m barricade at your side hides you. it does, crouched.
static func sight_point(who: Node3D) -> Vector3:
	var crouched: bool = who.has_method("is_crouching") and who.is_crouching()
	var at := who.global_position + Vector3.UP * (0.55 if crouched else 1.2)
	## a lean moves the head, not the body, so the point tested moves with it. without this a
	## player could see round a corner from inside cover and never be seen back.
	if who.has_method("lean_offset"):
		at += who.lean_offset() as Vector3
	return at


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


## more than a flicker of awareness: the bird has half caught something and is acting on it.
func is_noticing() -> bool:
	return level() > NOTICING


func has_last_seen() -> bool:
	return _seen_once


func target() -> Node3D:
	return _target


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


## a negative half angle means the full cone, which is what sees_point wants.
func _within_cone(to: Vector3, half_angle := -1.0) -> bool:
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.0001:
		return true
	var limit := half_angle if half_angle >= 0.0 else half_angle_deg
	return rad_to_deg(facing().angle_to(flat.normalized())) <= limit


## the hud draws this, so it may not fire every tick for every bird on the map.
func _report() -> void:
	var value := level()
	if absf(value - _sent) < 0.02 and value > 0.0 and value < 1.0:
		return
	_sent = value
	awareness_changed.emit(value)
