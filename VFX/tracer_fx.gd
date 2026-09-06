class_name TracerFx
extends Node3D


static var _mesh: BoxMesh
static var _mats := {}


static func _tracer_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html(false)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(color.r, color.g, color.b, 0.85)
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 4.0
		m.disable_receive_shadows = true
		_mats[key] = m
	return _mats[key]


static func warm() -> void:
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = Vector3.ONE
	_tracer_mat(Color(1.0, 0.95, 0.2))


static func spawn(world: Node, from: Vector3, to: Vector3, color := Color(1.0, 0.95, 0.2)) -> void:
	if world == null:
		return
	var seg := to - from
	var length := seg.length()
	if length < 0.05:
		return
	if _mesh == null:
		warm()

	var node := MeshInstance3D.new()
	node.mesh = _mesh
	node.material_override = _tracer_mat(color)
	world.add_child(node)
	node.global_position = from + seg * 0.5

	var dir := seg.normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.985 else Vector3.FORWARD
	node.look_at(to, up)
	node.scale = Vector3(0.03, 0.03, length)

	var tw := node.create_tween()
	tw.tween_property(node, "transparency", 1.0, 0.08)
	tw.tween_callback(node.queue_free)
