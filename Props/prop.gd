@tool
class_name Prop
extends StaticBody3D

## one node per placed object: drop a model in, position it, done. the mesh shows in the editor and
## the collision box is built from the mesh bounds when the game runs. neither is ever saved into
## the level file, which is what keeps a level of two hundred props a few kilobytes.

const VIEW := "__view"
const SHAPE := "__shape"

@export var model: PackedScene:
	set(value):
		model = value
		if is_inside_tree():
			_rebuild()


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_rebuild()


func _rebuild() -> void:
	for name in [VIEW, SHAPE]:
		var old := get_node_or_null(NodePath(name))
		if old != null:
			remove_child(old)
			old.queue_free()
	if model == null:
		return

	var view := model.instantiate() as Node3D
	if view == null:
		return
	view.name = VIEW
	## no owner, on purpose. an owned child would be serialised into the level with every vertex.
	add_child(view)

	if Engine.is_editor_hint():
		return
	var box := bounds(view)
	if box.size == Vector3.ZERO:
		return
	var shape := CollisionShape3D.new()
	shape.name = SHAPE
	var solid := BoxShape3D.new()
	solid.size = box.size
	shape.shape = solid
	shape.position = box.get_center()
	add_child(shape)


## the model's meshes, unioned, in this node's own space.
func bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var local := global_transform.affine_inverse() * mi.global_transform
		var part := local * mi.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func has_collision() -> bool:
	return get_node_or_null(NodePath(SHAPE)) != null
