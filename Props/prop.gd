@tool
class_name Prop
extends StaticBody3D


const VIEW := "__view"
const SHAPE := "__shape"

## what a bb sounds like landing on it: metal, wood, concrete, dirt, gravel or grass.
@export var material_tag := &""

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
	dress(self, model)


## the model on a body, and a box shape grown from what the model actually measures. static and
## shared, because a LooseProp is this same object with the physics let go of it.
static func dress(body: CollisionObject3D, packed: PackedScene) -> AABB:
	for built in [VIEW, SHAPE]:
		var old := body.get_node_or_null(NodePath(built))
		if old != null:
			body.remove_child(old)
			old.queue_free()
	if packed == null:
		return AABB()

	var view := packed.instantiate() as Node3D
	if view == null:
		return AABB()
	view.name = VIEW
	## no owner, on purpose: an owned child would be serialised into the level with every vertex.
	body.add_child(view)

	if Engine.is_editor_hint():
		return AABB()
	var box := bounds_of(body, view)
	if box.size == Vector3.ZERO:
		return box
	var shape := CollisionShape3D.new()
	shape.name = SHAPE
	var solid := BoxShape3D.new()
	solid.size = box.size
	shape.shape = solid
	shape.position = box.get_center()
	body.add_child(shape)
	return box


func bounds(root: Node3D) -> AABB:
	return bounds_of(self, root)


static func bounds_of(body: Node3D, root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var local := body.global_transform.affine_inverse() * mi.global_transform
		var part := local * mi.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func surface() -> StringName:
	if material_tag != &"":
		return material_tag
	var hint := model.resource_path.get_file().to_lower() if model != null else ""
	return Sfx.surface_from_name(hint + " " + name.to_lower())


func has_collision() -> bool:
	return get_node_or_null(NodePath(SHAPE)) != null
