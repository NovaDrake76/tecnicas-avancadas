class_name WeakPoint
extends StaticBody3D

## the one place on an armoured kiwi that a bb puts down regardless of how hard it arrives: the
## eyes. it is a BODY and not an area because the bb reports contacts against bodies, so an Area3D
## would never be hit. it sits on the target layer like the kiwi itself and detects nothing of its
## own, so the player never bumps into a floating box and no ray meant for the world finds it. it
## rides the head, so the idle clips that turn the bird's head move the target with it, exactly as
## they move the vision cone: one bone, so the two can never disagree about where the head is.

var _kiwi: Node


func setup(kiwi: Node, size: Vector3) -> void:
	_kiwi = kiwi
	collision_layer = 8
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)


## a bb landed on the eyes. energy does not matter here: one precise shot, any range, any kit.
func take_bb_hit(_damage := 1.0, at := Vector3.INF, _energy := -1.0) -> void:
	if _kiwi != null and is_instance_valid(_kiwi) and _kiwi.has_method("take_weak_hit"):
		_kiwi.take_weak_hit(at)


## the hit marker asks whoever it hit whether that put them down; the answer is the bird's.
func is_down() -> bool:
	return _kiwi != null and is_instance_valid(_kiwi) and _kiwi.is_down()
