@tool
class_name ViewmodelMotion
extends Node3D


@export_group("Idle sway")
## breathing pace, not walking pace.
@export var idle_sway_frequency := 0.3
@export var idle_sway_amplitude := Vector2(0.003, 0.002)
@export var idle_noise_amount := 0.6
@export var idle_noise_speed := 0.25
@export var idle_sway_stiffness := 40.0
@export var idle_sway_damping := 6.0

@export_group("Weapon bob")
@export var weapon_bob := true
@export var bob_amplitude := Vector2(0.012, 0.014)
@export var bob_max_speed := 10.0
@export var bob_stiffness := 90.0
@export var bob_damping := 12.0

@export_group("Look sway")
@export var look_sway_position := 0.004
@export var look_sway_rotation_deg := 0.9
@export var look_sway_max := 0.012
@export var look_sway_max_rot_deg := 3.0
@export var look_sway_stiffness := 150.0
@export var look_sway_damping := 14.0

@export_group("Strafe tilt")
@export var strafe_tilt_max_deg := 4.0
@export var strafe_tilt_stiffness := 90.0
@export var strafe_tilt_damping := 11.0

@export_group("Recoil")
@export var recoil_kick_back := 0.05
@export var recoil_kick_up_deg := 4.0
@export var recoil_random_deg := 1.2
@export var recoil_stiffness := 110.0
@export var recoil_damping := 12.0

@export_group("Run pose")
@export var run_pose_offset := Vector3(0.03, -0.06, 0.05)
@export var run_pose_tilt_deg := Vector3(-25.0, 22.0, 0.0)
@export var run_pose_stiffness := 55.0
@export var run_pose_damping := 10.0

@export_group("Air pose")
@export var air_pose_offset := Vector3(0.0, -0.04, 0.0)
@export var air_pose_stiffness := 60.0
@export var air_pose_damping := 10.0

@export_group("Reload pose")
## there is no reload animation.
@export var reload_pose_offset := Vector3(0.02, -0.36, 0.10)
@export var reload_pose_tilt_deg := Vector3(-38.0, 30.0, 12.0)
@export var reload_pose_stiffness := 42.0
@export var reload_pose_damping := 9.5

@export_group("Check pose")
## the weapon turned to show its magazine while the reload key is held; the same springs as the reload pose.
@export var check_pose_offset := Vector3(-0.03, -0.04, 0.08)
@export var check_pose_tilt_deg := Vector3(12.0, -18.0, -35.0)

@export_group("Aim down sights")
## drag these two in the editor to say where the weapon sits.
@export var hip_pose: Node3D
@export var aim_pose: Node3D
## used only when no marker is assigned, so an unwired weapon still aims somewhere sane.
@export var sights_position := Vector3(0.0, -0.0871, -0.1485)
@export var sights_pitch_deg := 0.96

## how much aiming damps sway and bob, a braced gun does not breathe like a hip held one.
@export_range(0.0, 1.0) var ads_steadiness := 0.8
## how much of the recoil TRAVEL survives while aimed.
@export_range(0.0, 1.0) var ads_recoil_travel := 0.25

@export_group("Editor preview")
## editor only.
@export var aim_preview := false:
	set(value):
		aim_preview = value
		_apply_preview()
## takes whatever you dragged the weapon to and writes it into the marker, then unticks itself.
@export var save_to_aim_pose := false:
	set(value):
		if value:
			capture_into(aim_node())
		save_to_aim_pose = false
@export var save_to_hip_pose := false:
	set(value):
		if value:
			capture_into(hip_node())
		save_to_hip_pose = false
## the fov to put back when the preview goes off.
@export var resting_fov := 0.0

const CROSSHAIR := "__AimPreviewCrosshair"

@export_group("Wall avoidance")
@export var wall_probe_dist := 0.85
@export var wall_max_pullback := 0.45
@export var wall_pullback_down := 0.25
@export var wall_stiffness := 95.0
@export var wall_damping := 13.0

const WALL_MASK := 0b1

var _noise := FastNoiseLite.new()
var _idle_time := 0.0
var _idle_phase := 0.0
var _was_idle := false
var _idle_x := Vector2.ZERO
var _idle_y := Vector2.ZERO
var _bob_x := Vector2.ZERO
var _bob_y := Vector2.ZERO
var _look_x := Vector2.ZERO
var _look_y := Vector2.ZERO
var _rot_pitch := Vector2.ZERO
var _rot_yaw := Vector2.ZERO
var _rot_roll := Vector2.ZERO
var _last_look := Vector2.ZERO
var _look_primed := false

var _run_pos := Vector3.ZERO
var _run_pos_vel := Vector3.ZERO
var _run_rot := Vector3.ZERO
var _run_rot_vel := Vector3.ZERO
var _air_pos := Vector3.ZERO
var _air_pos_vel := Vector3.ZERO
var _reload_pos := Vector3.ZERO
var _reload_pos_vel := Vector3.ZERO
var _reload_rot := Vector3.ZERO
var _reload_rot_vel := Vector3.ZERO
var _reloading := false
var _checking := false
var _recoil_pos := Vector3.ZERO
var _recoil_pos_vel := Vector3.ZERO
var _recoil_rot := Vector3.ZERO
var _recoil_rot_vel := Vector3.ZERO
var _wall_pos := Vector3.ZERO
var _wall_pos_vel := Vector3.ZERO

var _player: CharacterBody3D
var _head: Node3D
var _gun: Node3D
var _hip_position := Vector3.ZERO
var _hip_pitch := 0.0
var _ads := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	## a preview left switched on must never reach the game with the camera still zoomed in.
	if aim_preview:
		aim_preview = false
	add_to_group("viewmodel")
	_noise.seed = randi()
	_noise.frequency = 1.0
	_bind.call_deferred()


func _apply_preview() -> void:
	if not is_inside_tree():
		return
	var cam := get_parent() as Camera3D
	if cam == null:
		return
	if aim_preview:
		if resting_fov <= 0.0:
			resting_fov = cam.fov
		cam.fov = _aiming_fov(cam.fov)
		transform = Transform3D.IDENTITY
		_park_on(aim_node())
	else:
		if resting_fov > 0.0:
			cam.fov = resting_fov
		_park_on(hip_node())
	_show_crosshair(cam, aim_preview)


func _show_crosshair(cam: Camera3D, on: bool) -> void:
	var old := cam.get_node_or_null(NodePath(CROSSHAIR)) as Node
	if old != null:
		cam.remove_child(old)
		old.queue_free()
	if not on:
		return

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for dir in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT]:
		mesh.surface_add_vertex(dir * 0.004)
		mesh.surface_add_vertex(dir * 0.026)
	mesh.surface_end()

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 1.0, 0.3)
	mat.no_depth_test = true
	mat.disable_fog = true
	mat.render_priority = 10

	var node := MeshInstance3D.new()
	node.name = CROSSHAIR
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = Vector3(0.0, 0.0, -1.0)
	cam.add_child(node)


func _aiming_fov(fallback: float) -> float:
	var root: Node = owner
	if root == null and Engine.is_editor_hint():
		root = get_tree().edited_scene_root
	if root == null:
		return fallback
	for node in root.find_children("*", "AimScope", true, false):
		return (node as AimScope).ads_fov
	return fallback


func _park_on(pose: Node3D) -> void:
	var gun := weapon()
	if gun != null and pose != null:
		gun.transform = pose.transform


func capture_into(pose: Node3D) -> void:
	var gun := weapon()
	if gun == null or pose == null:
		return
	pose.transform = transform * gun.transform
	gun.transform = pose.transform
	transform = Transform3D.IDENTITY
	print("viewmodel: %s set to %v, pitch %.2f deg" % [pose.name, pose.position,
		rad_to_deg(pose.rotation.x)])


func weapon() -> Node3D:
	if _gun != null and is_instance_valid(_gun):
		return _gun
	var hip := hip_node()
	var aim := aim_node()
	for child in get_children():
		if child is Node3D and child != hip and child != aim:
			return child as Node3D
	return null


func _bind() -> void:
	_player = Player.local(get_tree())
	if _player != null:
		_head = _player.get_node_or_null("Head")
	var rack := get_tree().get_first_node_in_group("weapon_rack") as WeaponRack
	if rack != null:
		_gun = rack
		for g in rack.weapons():
			g.fired.connect(_on_fired)
			g.reload_started.connect(func(_d: float) -> void: set_reloading(true))
			g.reload_finished.connect(func(_m: Magazine) -> void: set_reloading(false))
			g.reload_cancelled.connect(func() -> void: set_reloading(false))
			g.check_started.connect(func() -> void: set_checking(true))
			g.check_ended.connect(func() -> void: set_checking(false))
	else:
		var gun := get_tree().get_first_node_in_group("weapon") as Gun
		if gun != null:
			gun.fired.connect(_on_fired)
			_gun = gun
	if _gun != null:
		_hip_position = _gun.position
		_hip_pitch = _gun.rotation.x


func set_reloading(on: bool) -> void:
	_reloading = on


func set_checking(on: bool) -> void:
	_checking = on


func set_ads(t: float) -> void:
	_ads = clampf(t, 0.0, 1.0)


func _on_fired(_speed: float, _mass_kg: float) -> void:
	apply_recoil()


func apply_recoil(amount := 1.0) -> void:
	_recoil_pos_vel += Vector3(0.0, 0.0, recoil_kick_back * amount) * 12.0
	_recoil_rot_vel += Vector3(
		deg_to_rad(recoil_kick_up_deg * amount),
		deg_to_rad(randf_range(-recoil_random_deg, recoil_random_deg)),
		deg_to_rad(randf_range(-recoil_random_deg, recoil_random_deg))) * 12.0


func apply_punch(amount := 1.0) -> void:
	_recoil_pos_vel += Vector3(0.02, -0.05, -0.16) * amount * 12.0
	_recoil_rot_vel += Vector3(deg_to_rad(-7.0), deg_to_rad(5.0), deg_to_rad(9.0)) * amount * 12.0


func _process(delta: float) -> void:
	## a frame hitch must not destabilise the springs; the damping term flips negative past about 1/6 s.
	delta = minf(delta, 1.0 / 30.0)

	var idle_target := Vector2.ZERO
	var bob_target := Vector2.ZERO
	var look_pos_target := Vector2.ZERO
	var rot_target := Vector3.ZERO
	var run_pos_target := Vector3.ZERO
	var run_rot_target := Vector3.ZERO
	var air_pos_target := Vector3.ZERO
	var reload_pos_target := Vector3.ZERO
	var reload_rot_target := Vector3.ZERO
	if _reloading:
		reload_pos_target = reload_pose_offset
		reload_rot_target = Vector3(deg_to_rad(reload_pose_tilt_deg.x),
			deg_to_rad(reload_pose_tilt_deg.y), deg_to_rad(reload_pose_tilt_deg.z))
	elif _checking:
		reload_pos_target = check_pose_offset
		reload_rot_target = Vector3(deg_to_rad(check_pose_tilt_deg.x),
			deg_to_rad(check_pose_tilt_deg.y), deg_to_rad(check_pose_tilt_deg.z))
	var wall_target := Vector3.ZERO

	if _player != null:
		var hspeed := Vector2(_player.velocity.x, _player.velocity.z).length()
		var grounded := _player.is_on_floor()

		var is_idle := hspeed < 0.2 and grounded
		if is_idle:
			if not _was_idle:
				_idle_phase = randf() * TAU
			_idle_time += delta
			var fig8 := Vector2(
				sin(_idle_time * TAU * idle_sway_frequency + _idle_phase),
				sin(_idle_time * TAU * idle_sway_frequency * 2.0 + _idle_phase * 2.0))
			var wander := Vector2(
				_noise.get_noise_1d(_idle_time * idle_noise_speed),
				_noise.get_noise_1d(_idle_time * idle_noise_speed + 137.0))
			idle_target = (fig8 + wander * idle_noise_amount) * idle_sway_amplitude
		else:
			_idle_time = 0.0
		_was_idle = is_idle

		## sourced from pure mouse look, never from the camera node, or headbob and kicks feed back into the sway.
		if _head != null:
			var look_now := Vector2(_head.rotation.x, _player.rotation.y)
			if _look_primed:
				var pitch_vel := wrapf(look_now.x - _last_look.x, -PI, PI) / maxf(delta, 0.0001)
				var yaw_vel := wrapf(look_now.y - _last_look.y, -PI, PI) / maxf(delta, 0.0001)
				look_pos_target = Vector2(
					clampf(yaw_vel * look_sway_position, -look_sway_max, look_sway_max),
					clampf(-pitch_vel * look_sway_position, -look_sway_max, look_sway_max))
				var max_rot := deg_to_rad(look_sway_max_rot_deg)
				var gain := deg_to_rad(look_sway_rotation_deg)
				rot_target.x = clampf(-pitch_vel * gain, -max_rot, max_rot)
				rot_target.y = clampf(-yaw_vel * gain, -max_rot, max_rot)
			_last_look = look_now
			_look_primed = true

		var lateral := _player.velocity.dot(_player.global_transform.basis.x)
		var run_max := 9.0
		if _player.movement != null:
			run_max = _player.movement.run_max_speed
		rot_target.z = -clampf(lateral / run_max, -1.0, 1.0) * deg_to_rad(strafe_tilt_max_deg)

		if _player.has_method("is_running") and _player.is_running():
			run_pos_target = run_pose_offset
			run_rot_target = Vector3(deg_to_rad(run_pose_tilt_deg.x),
				deg_to_rad(run_pose_tilt_deg.y), deg_to_rad(run_pose_tilt_deg.z))

		if not grounded:
			air_pos_target = air_pose_offset

		var cam := get_viewport().get_camera_3d()
		if weapon_bob and cam != null and cam.has_method("get_bob_phase") and hspeed > 0.1 and grounded:
			var angle: float = cam.get_bob_phase() * TAU
			var sf := clampf(hspeed / bob_max_speed, 0.0, 1.0)
			bob_target = Vector2(sin(angle) * bob_amplitude.x * sf, sin(angle * 2.0) * bob_amplitude.y * sf)

		if cam != null:
			var from := cam.global_position
			var to := from - cam.global_transform.basis.z * wall_probe_dist
			var query := PhysicsRayQueryParameters3D.create(from, to, WALL_MASK)
			query.exclude = [_player.get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				var intrude := clampf(wall_probe_dist - from.distance_to(hit.position), 0.0, wall_max_pullback)
				wall_target = Vector3(0.0, -intrude * wall_pullback_down, intrude)

	_idle_x = SpringUtil.apply(_idle_x.x, _idle_x.y, idle_target.x, idle_sway_stiffness, idle_sway_damping, delta)
	_idle_y = SpringUtil.apply(_idle_y.x, _idle_y.y, idle_target.y, idle_sway_stiffness, idle_sway_damping, delta)
	_look_x = SpringUtil.apply(_look_x.x, _look_x.y, look_pos_target.x, look_sway_stiffness, look_sway_damping, delta)
	_look_y = SpringUtil.apply(_look_y.x, _look_y.y, look_pos_target.y, look_sway_stiffness, look_sway_damping, delta)
	_bob_x = SpringUtil.apply(_bob_x.x, _bob_x.y, bob_target.x, bob_stiffness, bob_damping, delta)
	_bob_y = SpringUtil.apply(_bob_y.x, _bob_y.y, bob_target.y, bob_stiffness, bob_damping, delta)
	_rot_pitch = SpringUtil.apply(_rot_pitch.x, _rot_pitch.y, rot_target.x, look_sway_stiffness, look_sway_damping, delta)
	_rot_yaw = SpringUtil.apply(_rot_yaw.x, _rot_yaw.y, rot_target.y, look_sway_stiffness, look_sway_damping, delta)
	_rot_roll = SpringUtil.apply(_rot_roll.x, _rot_roll.y, rot_target.z, strafe_tilt_stiffness, strafe_tilt_damping, delta)

	var rp := _spring3(_run_pos, _run_pos_vel, run_pos_target, run_pose_stiffness, run_pose_damping, delta)
	_run_pos = rp[0]
	_run_pos_vel = rp[1]
	var rr := _spring3(_run_rot, _run_rot_vel, run_rot_target, run_pose_stiffness, run_pose_damping, delta)
	_run_rot = rr[0]
	_run_rot_vel = rr[1]
	var ap := _spring3(_air_pos, _air_pos_vel, air_pos_target, air_pose_stiffness, air_pose_damping, delta)
	_air_pos = ap[0]
	_air_pos_vel = ap[1]
	var rlp := _spring3(_reload_pos, _reload_pos_vel, reload_pos_target, reload_pose_stiffness, reload_pose_damping, delta)
	_reload_pos = rlp[0]
	_reload_pos_vel = rlp[1]
	var rlr := _spring3(_reload_rot, _reload_rot_vel, reload_rot_target, reload_pose_stiffness, reload_pose_damping, delta)
	_reload_rot = rlr[0]
	_reload_rot_vel = rlr[1]
	var kp := _spring3(_recoil_pos, _recoil_pos_vel, Vector3.ZERO, recoil_stiffness, recoil_damping, delta)
	_recoil_pos = kp[0]
	_recoil_pos_vel = kp[1]
	var kr := _spring3(_recoil_rot, _recoil_rot_vel, Vector3.ZERO, recoil_stiffness, recoil_damping, delta)
	_recoil_rot = kr[0]
	_recoil_rot_vel = kr[1]
	var wp := _spring3(_wall_pos, _wall_pos_vel, wall_target, wall_stiffness, wall_damping, delta)
	_wall_pos = wp[0]
	_wall_pos_vel = wp[1]

	var steady := 1.0 - _ads * ads_steadiness
	var travel := lerpf(1.0, ads_recoil_travel, _ads)
	var sway := Vector3(_idle_x.x + _look_x.x + _bob_x.x, _idle_y.x + _look_y.x + _bob_y.x, 0.0)
	position = (sway + _run_pos + _air_pos + _wall_pos) * steady + _recoil_pos * travel + _reload_pos
	rotation = (Vector3(_rot_pitch.x, _rot_yaw.x, _rot_roll.x) + _run_rot) * steady + _recoil_rot + _reload_rot

	if _gun != null:
		var from := hip_transform()
		var to := aim_transform()
		_gun.position = from.origin.lerp(to.origin, _ads)
		_gun.quaternion = from.basis.get_rotation_quaternion().slerp(
			to.basis.get_rotation_quaternion(), _ads)


func hip_transform() -> Transform3D:
	var pose := hip_node()
	if pose != null:
		return pose.transform
	return Transform3D(Basis(Vector3.RIGHT, _hip_pitch), _hip_position)


func aim_transform() -> Transform3D:
	var pose := aim_node()
	if pose != null:
		return pose.transform
	return Transform3D(Basis(Vector3.RIGHT, deg_to_rad(sights_pitch_deg)), sights_position)


func hip_node() -> Node3D:
	return _marker(hip_pose, "HipPose")


func aim_node() -> Node3D:
	return _marker(aim_pose, "AimPose")


func _marker(assigned: Node3D, fallback: String) -> Node3D:
	if assigned != null and is_instance_valid(assigned):
		return assigned
	var rack := weapon() as WeaponRack
	if rack != null:
		var gun := rack.shown()
		if gun != null:
			var own := gun.get_node_or_null(NodePath(fallback)) as Node3D
			if own != null:
				return own
	return get_node_or_null(NodePath(fallback)) as Node3D


func _spring3(value: Vector3, velocity: Vector3, target: Vector3, stiffness: float, damping: float, delta: float) -> Array:
	var x := SpringUtil.apply(value.x, velocity.x, target.x, stiffness, damping, delta)
	var y := SpringUtil.apply(value.y, velocity.y, target.y, stiffness, damping, delta)
	var z := SpringUtil.apply(value.z, velocity.z, target.z, stiffness, damping, delta)
	return [Vector3(x.x, y.x, z.x), Vector3(x.y, y.y, z.y)]
