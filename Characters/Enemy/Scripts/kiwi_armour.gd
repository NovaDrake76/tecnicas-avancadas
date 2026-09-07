class_name KiwiArmour
extends Node3D


enum Kind { LASER, SNIPER }

const METAL_LIGHT := Color(0.24, 0.25, 0.27)
## the bones the kit rides: the middle of the spine carries the bob of the whole body, the head carries the helmet, each leg its greave.
const TORSO_BONE := "spine_01"
const HEAD_BONE := "head"
const LEG_L_BONE := "leg_stretch.l"
const LEG_R_BONE := "leg_stretch.r"

## the weak point box: the eyes are 77 mm apart, so this covers both with a little to spare.
@export var weak_size := Vector3(0.15, 0.09, 0.09)
## how far forward of the eye midpoint the weak point sits, so it is the first thing a bb from the front meets rather than the body capsule behind it.
@export var weak_forward := 0.015

var kind: Kind = Kind.LASER

var _kiwi: CharacterBody3D
var _eyes: LaserEyes
var _skeleton: Skeleton3D
var _rigs: Array[BoneRig] = []
var _head: BoneRig
var _torso: BoneRig
var _weak: WeakPoint
var _suit: KiwiSuit
var _flash := 0.0
var _shed := false
var _leader := false


func bind(kiwi: CharacterBody3D, eyes: LaserEyes) -> void:
	_kiwi = kiwi
	_eyes = eyes
	_skeleton = kiwi.find_child("Skeleton3D", true, false) as Skeleton3D
	var built := build_suit(kiwi, _skeleton, kind)
	_suit = built["suit"]
	_rigs = built["rigs"]
	_head = built["head"]
	_torso = built["torso"]
	var mid: Vector3 = built["mid"]
	_weak = WeakPoint.new()
	_weak.setup(kiwi, weak_size)
	_head.frame.add_child(_weak)
	_weak.position = mid + Vector3(0.0, 0.0, -weak_forward)


static func build_suit(kiwi: Node3D, skeleton: Skeleton3D, which: Kind) -> Dictionary:
	var torso := BoneRig.on(kiwi, skeleton, TORSO_BONE)
	var head := BoneRig.on(kiwi, skeleton, HEAD_BONE)
	var leg_l := BoneRig.on(kiwi, skeleton, LEG_L_BONE)
	var leg_r := BoneRig.on(kiwi, skeleton, LEG_R_BONE)
	var mid := eye_mid_at_rest(kiwi, skeleton)
	KiwiBody.fit(kiwi, skeleton, mid + KiwiSuit.HEAD_AT)
	var suit := KiwiSuit.new()
	suit.build(which, head.frame, torso.frame, leg_l.frame if leg_l.found else null,
		leg_r.frame if leg_r.found else null, mid)
	var rigs: Array[BoneRig] = [torso, head, leg_l, leg_r]
	return {"suit": suit, "rigs": rigs, "head": head, "torso": torso, "mid": mid}


static func eye_mid_at_rest(kiwi: Node3D, skeleton: Skeleton3D) -> Vector3:
	if skeleton != null:
		var left := -1
		var right := -1
		for i in skeleton.get_bone_count():
			var bone_name := skeleton.get_bone_name(i).to_lower()
			if bone_name.begins_with("eye.l"):
				left = i
			elif bone_name.begins_with("eye.r"):
				right = i
		if left >= 0 and right >= 0:
			var into := kiwi.global_transform.affine_inverse() * skeleton.global_transform
			var l := (into * skeleton.get_bone_global_rest(left)).origin
			var r := (into * skeleton.get_bone_global_rest(right)).origin
			return (l + r) * 0.5
	return Vector3(0.0, 0.509, -0.246)


func _process(delta: float) -> void:
	if _flash > 0.0 and _suit != null:
		_flash = maxf(0.0, _flash - delta * 6.0)
		_suit.flash(_flash)


func dent(at: Vector3) -> void:
	_flash = 1.0
	var world := get_tree().current_scene
	var where := at if at.is_finite() else global_position + Vector3.UP * 0.3
	BurstFx.spawn(world, where, Color(0.8, 0.8, 0.82), 12, 2.6, 0.35)
	BurstFx.spawn(world, where, Color(0.4, 0.4, 0.42), 8, 1.8, 0.4)
	Sfx.play(&"bb_dent", where)


func bounce(at: Vector3) -> void:
	_flash = 0.35
	var world := get_tree().current_scene
	var where := at if at.is_finite() else global_position + Vector3.UP * 0.3
	BurstFx.spawn(world, where, Color(1.0, 1.0, 1.0), 8, 2.2, 0.25)
	ImpactFx.flash(world, where, Color(1.0, 1.0, 0.95), 0.8, 0.08)
	Sfx.play(&"bb_plate", where)


func shed() -> void:
	if _shed:
		return
	_shed = true
	if _kiwi != null and is_instance_valid(_kiwi):
		Sfx.play(&"plates_shed", _kiwi.global_position + Vector3.UP * 0.3)
	var world := get_tree().current_scene
	if _suit != null:
		for p in _suit.plates:
			if p.visible:
				BurstFx.spawn(world, p.global_position, METAL_LIGHT, 10, 3.0, 0.5)
			p.visible = false
		for t in _suit.trims:
			t.visible = false
	if _weak != null:
		_weak.collision_layer = 0


func is_shed() -> bool:
	return _shed


func set_leader(leader: bool) -> void:
	_leader = leader
	if _suit != null:
		_suit.set_leader(leader)


func is_leader() -> bool:
	return _leader


func weak_point() -> WeakPoint:
	return _weak


func weak_centre() -> Vector3:
	return _weak.global_position if _weak != null else global_position


func hide_all() -> void:
	visible = false
	for rig in _rigs:
		if rig != null and is_instance_valid(rig):
			rig.visible = false
	if _weak != null:
		_weak.collision_layer = 0
	set_process(false)
