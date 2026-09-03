class_name MortarShell
extends Node3D

## one round from the mortar kiwi: a shell on a parabola and, from the moment it leaves the tube, a
## RING ON THE GROUND where it will land, filling up as it falls. that ring is the whole design: you
## are told where and when, and standing on it is the one thing that gets you hurt. it lands on
## nothing the mortar can see, which is the point of a mortar; cover between the blast and you cuts
## the damage, so a wall still means something, and a roof means everything. the shell is silent in
## the air: the ring is the warning, and a whistle on top of it only made the same point louder.

signal burst(at: Vector3)

const RING := Color(1.0, 0.45, 0.2)
const FIRE := Color(1.0, 0.6, 0.2)
const SMOKE := Color(0.35, 0.3, 0.26)

var _from := Vector3.ZERO
var _target := Vector3.ZERO
var _flight := 2.6
var _radius := 3.5
var _damage := 38.0
var _cover_factor := 0.35
var _shooter: Node3D
var _t := 0.0
var _apex := 8.0
var _shell: MeshInstance3D
var _ring: MeshInstance3D
var _fill: MeshInstance3D
var _done := false


static func launch(world: Node, from: Vector3, target: Vector3, flight_time: float, radius: float,
		damage: float, cover_factor: float, shooter: Node3D) -> MortarShell:
	var shell := MortarShell.new()
	shell._from = from
	shell._target = target
	shell._flight = maxf(flight_time, 0.3)
	shell._radius = radius
	shell._damage = damage
	shell._cover_factor = cover_factor
	shell._shooter = shooter
	shell.add_to_group("mortar_shell")
	world.add_child(shell)
	shell.global_position = from
	return shell


func _ready() -> void:
	var flat := Vector2(_target.x - _from.x, _target.z - _from.z).length()
	_apex = maxf(6.0, flat * 0.35)

	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.2, 0.2, 0.22)
	body.roughness = 0.5
	body.metallic = 0.5
	_shell = MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = 0.09
	m.height = 0.42
	m.radial_segments = 8
	m.rings = 3
	_shell.mesh = m
	_shell.material_override = body
	add_child(_shell)

	## the telegraph: a faint ring the size of the blast, and a disc inside it that grows to the ring
	## exactly as the shell arrives, so the fill IS the clock.
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.albedo_color = Color(RING, 0.55)
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.disable_receive_shadows = true
	ring_mat.no_depth_test = false
	_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	## TorusMesh.rings is the count AROUND the big circle and ring_segments around the tube, the
	## opposite of what the names suggest.
	ring.inner_radius = _radius - 0.08
	ring.outer_radius = _radius
	ring.rings = 40
	ring.ring_segments = 6
	_ring.mesh = ring
	_ring.material_override = ring_mat
	_ring.top_level = true
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	var fill_mat := ring_mat.duplicate() as StandardMaterial3D
	fill_mat.albedo_color = Color(RING, 0.16)
	_fill = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 28
	disc.rings = 1
	_fill.mesh = disc
	_fill.material_override = fill_mat
	_fill.top_level = true
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill)
	var ground := _ground_at(_target)
	_ring.global_position = ground + Vector3.UP * 0.06
	_fill.global_position = ground + Vector3.UP * 0.05
	_fill.scale = Vector3(0.01, 1.0, 0.01)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var u := clampf(_t / _flight, 0.0, 1.0)
	var pos := _from.lerp(_target, u) + Vector3.UP * (_apex * 4.0 * u * (1.0 - u))
	var ahead := _from.lerp(_target, minf(u + 0.02, 1.0)) + Vector3.UP * (_apex * 4.0 * minf(u + 0.02, 1.0) * (1.0 - minf(u + 0.02, 1.0)))
	global_position = pos
	if ahead.distance_squared_to(pos) > 0.0001:
		_shell.look_at(ahead, Vector3.UP)
		_shell.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var r := maxf(_radius * u, 0.05)
	_fill.scale = Vector3(r, 1.0, r)
	if u >= 1.0:
		_explode()


func _explode() -> void:
	_done = true
	var at := _ground_at(_target)
	var world := get_tree().current_scene
	BurstFx.spawn(world, at + Vector3.UP * 0.3, FIRE, 26, 6.0, 0.5)
	BurstFx.spawn(world, at + Vector3.UP * 0.5, SMOKE, 40, 4.0, 1.4)
	BurstFx.spawn(world, at + Vector3.UP * 0.2, Color(0.5, 0.42, 0.3), 30, 7.0, 0.9)
	ImpactFx.flash(world, at + Vector3.UP * 0.6, FIRE, 6.0, 0.16)
	var light := LaserEyes.make_light(FIRE, 14.0)
	light.light_energy = 9.0
	world.add_child(light)
	light.global_position = at + Vector3.UP * 1.0
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	tw.tween_callback(light.queue_free)

	var thump := AudioStreamPlayer3D.new()
	thump.stream = thump_sound()
	thump.unit_size = 26.0
	thump.max_distance = 220.0
	world.add_child(thump)
	thump.global_position = at
	thump.finished.connect(thump.queue_free)
	thump.play()

	_hurt(at)
	burst.emit(at)
	queue_free()


## damage falls off to the ring's edge, and cover between the blast and you cuts it hard. the ray is
## from knee height at the blast, so a crate you are crouched behind counts and a kerb does not.
func _hurt(at: Vector3) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.has_method("take_laser_hit"):
		return
	var flat := Vector2(player.global_position.x - at.x, player.global_position.z - at.z).length()
	if flat > _radius or absf(player.global_position.y - at.y) > 3.0:
		return
	var dmg := _damage * pow(1.0 - flat / _radius, 0.7)
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, VisionCone.sight_point(player), 1)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		dmg *= _cover_factor
	if dmg > 0.5:
		player.take_laser_hit(dmg, at)


func _ground_at(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 40.0, point - Vector3.UP * 60.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else point


func target() -> Vector3:
	return _target


func time_left() -> float:
	return maxf(0.0, _flight - _t)


static var _thump: AudioStreamWAV


## the blast: a low thud with a crack on the front and noise decaying behind it.
static func thump_sound() -> AudioStreamWAV:
	if _thump != null:
		return _thump
	var rate := Tone.RATE
	var n := int(rate * 0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(rate)
		var u := float(i) / float(n)
		var env := exp(-u * 6.0)
		var low := sin(TAU * 48.0 * t) * exp(-u * 3.0) * 0.9
		var noise := (randf() * 2.0 - 1.0) * env * 0.8
		var crack := (randf() * 2.0 - 1.0) * exp(-t * 90.0)
		out[i] = tanh((low + noise + crack) * 1.4)
	_thump = Tone.wav(out)
	return _thump
