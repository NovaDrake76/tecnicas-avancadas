class_name RusherKiwi
extends Kiwi


const BAND := Color(0.72, 0.12, 0.1)
const CREST := Color(0.95, 0.25, 0.12)


func _ready() -> void:
	super()
	add_to_group("rusher")
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	build_kit(self, skeleton)
	if skeleton != null:
		for rig in skeleton.get_children():
			if rig is BoneRig:
				var frame := (rig as BoneRig).frame
				KitMesh.merge(frame, frame.find_children("*", "MeshInstance3D", true, false))


func _on_alarmed(from: Vector3) -> void:
	_begin_hunt(from)


func _errand_available() -> bool:
	return false


func _step_role(delta: float) -> void:
	var dist := global_position.distance_to(_player.global_position)
	if dist > peck_reach * 0.8:
		_play(run_clip, 0.15)
		_move_to(_player.global_position, hunt_speed, delta)
		return
	velocity.x = move_toward(velocity.x, 0.0, hunt_speed * 8.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, hunt_speed * 8.0 * delta)
	_turn_to(_player.global_position, turn_speed * 3.0, delta)


func kind_name() -> String:
	return "RUSHER"


static func build_kit(kiwi: Node3D, skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	var band := KitMesh.matte(BAND, 0.9, 0.05)
	var crest := KitMesh.glow(CREST, 0.8)
	KiwiBody.fit(kiwi, skeleton, KiwiArmour.eye_mid_at_rest(kiwi, skeleton) + KiwiSuit.HEAD_AT)
	var torso := BoneRig.on(kiwi, skeleton, KiwiArmour.TORSO_BONE)
	var head := BoneRig.on(kiwi, skeleton, KiwiArmour.HEAD_BONE)
	var sash := KiwiBody.body_patch(-PI, PI, 0.5, 0.64, 28, 2, 0.012, 0.005)
	KitMesh.put(sash, band, torso.frame, Vector3.ZERO, "Sash")
	var bib := KiwiBody.body_patch(-0.55, 0.55, 0.18, 0.5, 8, 4, 0.014, 0.006)
	KitMesh.put(bib, band, torso.frame, Vector3.ZERO, "Bib")
	var headband := KiwiBody.head_patch(-PI, PI, 0.28, 0.58, 24, 2, 0.008, 0.005)
	KitMesh.put(headband, band, head.frame, Vector3.ZERO, "Headband")
	for spike in [[0.0, 1.15], [0.0, 1.45], [PI, 1.2], [PI, 0.9]]:
		var az: float = spike[0]
		var el: float = spike[1]
		var base := KiwiBody.head_point(az, el, 0.004)
		var tip := base + KiwiBody.head_normal(az, el) * 0.055
		var rod := KitMesh.rod(head.frame, base, tip, 0.006, crest)
		rod.name = "Crest"
