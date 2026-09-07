class_name BoneRig
extends BoneAttachment3D


var frame: Node3D
var found := false


static func on(creature: Node3D, skeleton: Skeleton3D, bone_contains: String) -> BoneRig:
	var rig := BoneRig.new()
	rig.name = "Rig_" + bone_contains.replace(".", "_")
	rig.frame = Node3D.new()
	rig.frame.name = "Frame"
	var idx := -1
	if skeleton != null:
		for i in skeleton.get_bone_count():
			if bone_contains in skeleton.get_bone_name(i).to_lower():
				idx = i
				break
	if idx < 0:
		creature.add_child(rig)
		rig.add_child(rig.frame)
		return rig
	skeleton.add_child(rig)
	rig.bone_idx = idx
	## an attachment is only placed when the skeleton next updates, which an unanimated skeleton (the editor, a bird before its first clip) may never do: place it on the bone now.
	rig.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(idx)
	rig.add_child(rig.frame)
	var rest := skeleton.global_transform * skeleton.get_bone_global_rest(idx)
	## the frame is the creature's own frame carried by the bone: authored in body space, it lands where it was measured at rest and rides the bone from there.
	rig.frame.transform = rest.affine_inverse() * creature.global_transform
	rig.found = true
	return rig
