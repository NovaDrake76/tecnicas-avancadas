class_name Searchlight
extends Node3D


@export var half_angle_deg := 11.0
@export var reach := 80.0
@export var energy := 7.0
@export var colour := Color(1.0, 0.96, 0.85)

var _spot: SpotLight3D
var _cone: MeshInstance3D
var _aim := Vector3.ZERO
var _has_aim := false


func _ready() -> void:
	_spot = SpotLight3D.new()
	_spot.spot_angle = half_angle_deg
	_spot.spot_range = reach
	_spot.light_energy = energy
	_spot.light_color = colour
	_spot.shadow_enabled = false
	_spot.spot_attenuation = 0.6
	add_child(_spot)

	## an additive cone reads as a beam; an additive quad would read as a rectangle.
	_cone = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.25
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 14
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	_cone.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(colour, 0.11)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	_cone.material_override = mat
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cone)
	_cone.top_level = true
	_cone.visible = false


func aim_at(point: Vector3) -> void:
	_aim = point
	_has_aim = true
	var d := point - global_position
	if d.length_squared() < 0.01:
		return
	look_at(point, Vector3.FORWARD if absf(d.normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP)
	var length := d.length()
	var radius := tan(deg_to_rad(half_angle_deg)) * length
	_cone.visible = true
	_stretch(_cone, point, global_position, radius)


func aim_point() -> Vector3:
	return _aim


func sees(point: Vector3) -> bool:
	if not _has_aim:
		return false
	var to := point - global_position
	if to.length() > reach or to.length_squared() < 0.01:
		return false
	var axis := -global_transform.basis.z
	if rad_to_deg(axis.angle_to(to.normalized())) > half_angle_deg:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position, point, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func set_lit(on: bool) -> void:
	_spot.visible = on
	_cone.visible = on and _has_aim


static func _stretch(mi: MeshInstance3D, wide_at: Vector3, narrow_at: Vector3, radius: float) -> void:
	var d := narrow_at - wide_at
	var length := d.length()
	if length < 0.01:
		mi.visible = false
		return
	var y := d / length
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	mi.global_transform = Transform3D(Basis(x * radius, y * length, z * radius), wide_at + d * 0.5)
