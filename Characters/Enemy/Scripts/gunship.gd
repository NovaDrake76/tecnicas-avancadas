class_name Gunship
extends CharacterBody3D


enum Phase { ARRIVE, SCOUT, LEAVE, GONE }

const TRACER := Color(1.0, 0.62, 0.25)
const TRIM := LaserEyes.GLOW

@export_group("Flight")
@export var orbit_radius := 26.0
@export var height := 22.0
@export var orbit_speed := 0.35
@export var fly_speed := 26.0
## how long it stays once it has arrived, if the alarm never drops
@export var loiter := 55.0

@export_group("Searchlight")
## seconds in the light before you are marked
@export var mark_time := 1.5
## how fast the light wanders when it has nothing, in metres per second at the ground
@export var sweep_radius := 9.0
@export var sweep_speed := 0.5

@export_group("Gun")
## seconds continuously marked before the door gun opens up
@export var gun_delay := 4.0
@export var gun_dps := 26.0
## the impact line starts this far short of you and walks in at walk_speed
@export var lead_in := 6.0
@export var walk_speed := 9.0
@export var hit_radius := 1.1
@export var burst_time := 2.2
@export var burst_gap := 2.5

var phase := Phase.ARRIVE
var light: Searchlight

var _centre := Vector3.ZERO
var _angle := 0.0
var _time := 0.0
var _loiter := 0.0
var _player: Node3D
var _mark := 0.0
var _marked := false
var _gun := 0.0
var _firing := false
var _burst_left := 0.0
var _gap_left := 0.0
var _strike := Vector3.ZERO
var _strike_dir := Vector3.FORWARD
var _hits := 0.0
var _forced_light := Vector3.INF
var _lock := 0.0
var _rotor: Node3D
var _tail_rotor: Node3D
var _beacon_mat: StandardMaterial3D
var _tracer: MeshInstance3D
var _gun_muzzle: Node3D
var _rotor_sfx: AudioStreamPlayer3D
var _rotor_far: AudioStreamPlayer3D
var _gun_sfx: AudioStreamPlayer3D
var _leave_dir := Vector3.FORWARD


func _ready() -> void:
	add_to_group("reinforcement")
	add_to_group("gunship")
	collision_layer = 8
	collision_mask = 0
	_build()
	light = Searchlight.new()
	light.position = Vector3(0.0, -0.6, -1.4)
	add_child(light)
	_rotor_sfx = Sfx.attach(&"heli_rotor_near", self)
	_rotor_sfx.play()
	_rotor_far = Sfx.attach(&"heli_rotor_far", self)
	_rotor_far.play()
	_rotor_mix()
	_gun_sfx = Sfx.attach(&"heli_gun", self)
	Alarm.stage_changed.connect(_on_stage)


func dispatch(from: Vector3, toward: Vector3) -> void:
	global_position = from
	_centre = toward
	var flat := toward - from
	flat.y = 0.0
	if flat.length_squared() > 0.01:
		rotation.y = atan2(-flat.x, -flat.z)
	_angle = atan2(from.z - toward.z, from.x - toward.x)
	phase = Phase.ARRIVE


func _physics_process(delta: float) -> void:
	_rotor_mix()
	_time += delta
	if _rotor != null:
		_rotor.rotation.y += delta * 25.0
		_tail_rotor.rotation.x += delta * 40.0
	if _beacon_mat != null:
		_beacon_mat.emission_energy_multiplier = 4.0 if fmod(_time, 1.0) < 0.12 else 0.0
	if _player == null or not is_instance_valid(_player):
		_player = Player.nearest(get_tree(), global_position)

	match phase:
		Phase.ARRIVE:
			_step_arrive(delta)
		Phase.SCOUT:
			_step_scout(delta)
		Phase.LEAVE:
			global_position += _leave_dir * fly_speed * delta + Vector3.UP * 4.0 * delta
			if _time > 1000.0 or global_position.distance_to(_centre) > 260.0:
				phase = Phase.GONE
				queue_free()
		Phase.GONE:
			pass


func _step_arrive(delta: float) -> void:
	var ring := _ring_point(_angle)
	var to := ring - global_position
	if to.length() < fly_speed * delta * 1.5:
		global_position = ring
		phase = Phase.SCOUT
		_loiter = 0.0
		light.set_lit(true)
		return
	global_position += to.normalized() * fly_speed * delta
	_face(to)


func _ring_point(angle: float) -> Vector3:
	return _centre + Vector3(cos(angle) * orbit_radius, height, sin(angle) * orbit_radius)


func _step_scout(delta: float) -> void:
	_loiter += delta
	if Alarm.has_last_known:
		_centre = _centre.lerp(Alarm.last_known, clampf(delta * 0.8, 0.0, 1.0))
	_angle += orbit_speed * delta
	var want := _ring_point(_angle)
	var to := want - global_position
	global_position = want
	var tangent := Vector3(-sin(_angle), 0.0, cos(_angle))
	_face(tangent if to.length_squared() < 0.0001 else tangent)

	_step_light(delta)
	_step_gun(delta)

	if _loiter >= loiter and not _marked:
		_leave()


func _step_light(delta: float) -> void:
	_lock = maxf(0.0, _lock - delta)
	var target := Vector3.INF
	if _forced_light != Vector3.INF:
		target = _forced_light
	elif (_marked or _lock > 0.0) and _player != null:
		target = _player.global_position
	else:
		var t := _time * sweep_speed
		target = _centre + Vector3(sin(t * 1.3) * sweep_radius, 0.0, cos(t * 0.9) * sweep_radius)
		target.y = _centre.y
	light.aim_at(target)

	var seen := false
	if _player != null and is_instance_valid(_player) and _player.has_method("is_alive") and _player.is_alive():
		seen = light.sees(VisionCone.sight_point(_player))
	if seen:
		_mark = minf(_mark + delta, mark_time + 0.01)
	else:
		_mark = maxf(0.0, _mark - delta * 2.0)
	var was := _marked
	if _mark >= mark_time:
		_marked = true
	elif _mark < mark_time * 0.5:
		_marked = false
	if _marked:
		Alarm.mark(_player.global_position)
	elif was:
		_stop_gun()


func _step_gun(delta: float) -> void:
	if not _marked:
		_gun = 0.0
		return
	_gun += delta
	if _gun < gun_delay:
		return
	if _firing:
		_burst_left -= delta
		_strike += _strike_dir * walk_speed * delta
		var ground := _ground_under(_strike)
		if fmod(_burst_left, 0.06) < delta:
			ImpactFx.spawn(get_tree().current_scene, ground, Vector3.UP, Color(0.75, 0.7, 0.6))
		LaserEyes.stretch(_tracer, _gun_muzzle.global_position, ground, 0.035)
		_tracer.visible = fmod(_time, 0.08) < 0.05
		var flat := _player.global_position - ground
		flat.y = 0.0
		if flat.length() <= hit_radius:
			_player.take_laser_hit(gun_dps * delta, global_position)
			_hits += gun_dps * delta
		if _burst_left <= 0.0:
			_firing = false
			_tracer.visible = false
			_gap_left = burst_gap
		return
	_gap_left -= delta
	if _gap_left <= 0.0:
		_open_fire()


func _open_fire() -> void:
	_firing = true
	_burst_left = burst_time
	var from_ship := _player.global_position - global_position
	from_ship.y = 0.0
	_strike_dir = from_ship.normalized() if from_ship.length_squared() > 0.01 else Vector3.FORWARD
	_strike = _player.global_position - _strike_dir * lead_in
	_gun_sfx.pitch_scale = randf_range(0.96, 1.04)
	_gun_sfx.play()


func _stop_gun() -> void:
	_firing = false
	_gun = 0.0
	_gap_left = 0.0
	if _tracer != null:
		_tracer.visible = false
	if _gun_sfx != null:
		_gun_sfx.stop()


func _ground_under(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at - Vector3.UP * 60.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else Vector3(at.x, _centre.y, at.z)


func _face(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	var yaw := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, yaw, 0.08)
	rotation.z = lerp_angle(rotation.z, -0.18 if phase == Phase.SCOUT else 0.0, 0.05)


func _leave() -> void:
	if phase == Phase.LEAVE or phase == Phase.GONE:
		return
	_stop_gun()
	_marked = false
	_mark = 0.0
	light.set_lit(false)
	_leave_dir = -global_transform.basis.z
	_leave_dir.y = 0.0
	_leave_dir = _leave_dir.normalized() if _leave_dir.length_squared() > 0.01 else Vector3.FORWARD
	phase = Phase.LEAVE


func _on_stage(stage: int) -> void:
	if stage == Alarm.Stage.CALM:
		_leave()


func take_bb_hit(_damage := 1.0, at := Vector3.INF, _energy := -1.0) -> void:
	var world := get_tree().current_scene
	var where := at if at.is_finite() else global_position
	BurstFx.spawn(world, where, Color.WHITE, 8, 2.0, 0.25)
	Sfx.play(&"heli_ping", where)
	if _player != null and is_instance_valid(_player):
		_mark = mark_time
		_marked = true
		_lock = 2.0
		Alarm.mark(_player.global_position)


func is_down() -> bool:
	return false


func is_marked() -> bool:
	return _marked


func is_firing() -> bool:
	return _firing


func strike_point() -> Vector3:
	return _strike


func damage_dealt() -> float:
	return _hits


func force_light(at: Vector3) -> void:
	_forced_light = at


func release_light() -> void:
	_forced_light = Vector3.INF


func _build() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.17, 0.19, 0.2)
	dark.roughness = 0.6
	dark.metallic = 0.4
	var trim := StandardMaterial3D.new()
	trim.albedo_color = TRIM
	trim.emission_enabled = true
	trim.emission = TRIM
	trim.emission_energy_multiplier = 1.0
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.3, 0.45, 0.5, 0.75)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.2
	var disc := StandardMaterial3D.new()
	disc.albedo_color = Color(0.2, 0.2, 0.2, 0.35)
	disc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(1.0, 0.2, 0.15)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.2, 0.15)

	_box(Vector3(1.6, 1.4, 3.4), Vector3(0.0, 0.0, 0.0), dark)
	_box(Vector3(1.4, 0.7, 1.0), Vector3(0.0, 0.25, -1.9), glass)
	_box(Vector3(1.7, 0.08, 3.5), Vector3(0.0, -0.6, 0.0), trim)
	var boom := _cyl(0.22, 0.14, 4.2, Vector3(0.0, 0.25, 3.8), dark)
	boom.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_box(Vector3(0.1, 1.2, 0.7), Vector3(0.0, 0.9, 5.7), dark)
	_box(Vector3(1.6, 0.08, 0.5), Vector3(0.0, 0.5, 5.4), dark)
	for side in [-1.0, 1.0]:
		var skid := _cyl(0.05, 0.05, 3.0, Vector3(side * 0.8, -1.05, 0.2), dark)
		skid.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		_box(Vector3(0.06, 0.4, 0.06), Vector3(side * 0.8, -0.85, -0.9), dark)
		_box(Vector3(0.06, 0.4, 0.06), Vector3(side * 0.8, -0.85, 1.1), dark)
	_cyl(0.12, 0.12, 0.5, Vector3(0.0, 0.95, 0.0), dark)

	_rotor = Node3D.new()
	_rotor.position = Vector3(0.0, 1.2, 0.0)
	add_child(_rotor)
	var d := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 3.3
	dm.bottom_radius = 3.3
	dm.height = 0.02
	dm.radial_segments = 24
	d.mesh = dm
	d.material_override = disc
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rotor.add_child(d)
	for i in 2:
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(6.4, 0.04, 0.26)
		blade.mesh = bm
		blade.material_override = dark
		blade.rotation_degrees = Vector3(0.0, 90.0 * float(i), 0.0)
		_rotor.add_child(blade)

	_tail_rotor = Node3D.new()
	_tail_rotor.position = Vector3(0.12, 0.9, 5.75)
	add_child(_tail_rotor)
	var td := MeshInstance3D.new()
	var tdm := CylinderMesh.new()
	tdm.top_radius = 0.8
	tdm.bottom_radius = 0.8
	tdm.height = 0.02
	tdm.radial_segments = 16
	td.mesh = tdm
	td.material_override = disc
	td.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	_tail_rotor.add_child(td)
	var tb := MeshInstance3D.new()
	var tbm := BoxMesh.new()
	tbm.size = Vector3(0.03, 1.6, 0.12)
	tb.mesh = tbm
	tb.material_override = dark
	_tail_rotor.add_child(tb)

	var beacon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	beacon.mesh = sm
	beacon.material_override = _beacon_mat
	beacon.position = Vector3(0.0, 0.3, 5.9)
	add_child(beacon)

	_gun_muzzle = Node3D.new()
	var barrel := _cyl(0.05, 0.05, 1.1, Vector3(0.95, -0.25, -0.2), dark)
	barrel.rotation_degrees = Vector3(60.0, 0.0, 0.0)
	_gun_muzzle.position = Vector3(0.95, -0.7, -0.7)
	add_child(_gun_muzzle)

	_tracer = MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 1.0
	tm.bottom_radius = 1.0
	tm.height = 1.0
	tm.radial_segments = 6
	_tracer.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.albedo_color = TRACER
	tmat.emission_enabled = true
	tmat.emission = TRACER
	tmat.emission_energy_multiplier = 2.5
	_tracer.material_override = tmat
	_tracer.top_level = true
	_tracer.visible = false
	_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tracer)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 1.6, 3.6)
	shape.shape = box
	add_child(shape)
	var tail := CollisionShape3D.new()
	var tbox := BoxShape3D.new()
	tbox.size = Vector3(0.5, 0.6, 4.2)
	tail.shape = tbox
	tail.position = Vector3(0.0, 0.25, 3.8)
	add_child(tail)


func _box(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	return mi


func _cyl(top: float, bottom: float, h: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 10
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	return mi


func _rotor_mix() -> void:
	if _rotor_sfx == null or _rotor_far == null:
		return
	var d := global_position.distance_to(Sfx.listener())
	var far_t := clampf((d - 50.0) / 80.0, 0.0, 1.0)
	_rotor_sfx.volume_db = Sfx.level_of(&"heli_rotor_near") - 30.0 * far_t
	_rotor_far.volume_db = Sfx.level_of(&"heli_rotor_far") - 14.0 * (1.0 - far_t)
