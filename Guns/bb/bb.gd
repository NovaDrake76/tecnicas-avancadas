class_name BB
extends RigidBody3D

const AIR_DENSITY := 1.225
const DRAG_COEFF := 0.47
const BB_RADIUS := 0.003

@export_range(0.00001, 0.01, 0.00001, "or_greater") var bb_mass: float = 0.0002
@export_range(0.0, 0.01, 0.00001, "or_greater") var BackspinDrag: float = 0.0002
@export var lifetime: float = 5.0
@export var despawn_on_impact := true
@export var mark_surface := true

@export var draw_trail: bool = true
@export var trail_color: Color = Color(0.4, 0.9, 1.0)
@export var trail_fade_time: float = 0.0
@export var trail_every: int = 1

var _area: float = PI * BB_RADIUS * BB_RADIUS
var _frame := 0
var _impacted := false
var _crumb_mesh: SphereMesh
var _crumb_mat: StandardMaterial3D


func _ready() -> void:
	mass = bb_mass
	linear_damp = 0.0
	angular_damp = 0.0
	contact_monitor = true
	max_contacts_reported = 1
	if draw_trail:
		_build_crumb_assets()
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


## the first contact is the shot landing, everything after it is a bounce we do not care about.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _impacted or state.get_contact_count() == 0:
		return
	_impacted = true
	var point := state.get_contact_collider_position(0)
	var normal := state.get_contact_local_normal(0)
	## force the normal to oppose the incoming velocity, the engine's sign varies by body pair.
	if normal.dot(state.linear_velocity) > 0.0:
		normal = -normal
	_on_impact.call_deferred(point, normal)


func _on_impact(point: Vector3, normal: Vector3) -> void:
	var world := get_tree().current_scene
	ImpactFx.spawn(world, point, normal)
	if mark_surface:
		BulletHoles.mark(point, normal)
	if despawn_on_impact:
		queue_free()


func _physics_process(_delta: float) -> void:
	if draw_trail:
		_frame += 1
		if _frame % maxi(1, trail_every) == 0:
			_drop_crumb()

	var vel := linear_velocity
	var speed := vel.length()
	if speed < 0.01:
		return

	var dir := vel / speed

	var drag_mag := 0.5 * AIR_DENSITY * DRAG_COEFF * _area * speed * speed
	apply_central_force(-dir * drag_mag)

	var spin_axis := dir.cross(Vector3.UP)
	if spin_axis.length_squared() > 0.000001:
		spin_axis = spin_axis.normalized()
		var lift_dir := spin_axis.cross(dir).normalized()
		var lift_mag := sqrt(speed) * BackspinDrag
		apply_central_force(lift_dir * lift_mag)


func _build_crumb_assets() -> void:
	_crumb_mesh = SphereMesh.new()
	_crumb_mesh.radius = 0.12
	_crumb_mesh.height = 0.24
	_crumb_mesh.radial_segments = 6
	_crumb_mesh.rings = 3

	_crumb_mat = StandardMaterial3D.new()
	_crumb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crumb_mat.albedo_color = trail_color
	_crumb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _drop_crumb() -> void:
	var m := MeshInstance3D.new()
	m.mesh = _crumb_mesh
	m.material_override = _crumb_mat if trail_fade_time <= 0.0 else _crumb_mat.duplicate()
	get_tree().current_scene.add_child(m)
	m.global_position = global_position

	if trail_fade_time > 0.0:
		var tw := m.create_tween()
		tw.tween_property(m.material_override, "albedo_color:a", 0.0, trail_fade_time)
		tw.tween_callback(m.queue_free)