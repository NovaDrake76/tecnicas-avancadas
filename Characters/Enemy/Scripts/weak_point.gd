class_name WeakPoint
extends StaticBody3D


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


func take_bb_hit(_damage := 1.0, at := Vector3.INF, _energy := -1.0) -> void:
	if _kiwi != null and is_instance_valid(_kiwi) and _kiwi.has_method("take_weak_hit"):
		_kiwi.take_weak_hit(at)


func is_down() -> bool:
	return _kiwi != null and is_instance_valid(_kiwi) and _kiwi.is_down()
