class_name LaserEyes
extends Node3D

## everything the laser looks and sounds like, and nothing it decides. the kiwi says "glow this much",
## "beam on, beam at, beam off", and the bolts borrow the same meshes and materials; this node reads
## the eye bones every frame and draws. keeping the drawing off the physics tick is what makes a beam
## smooth at any frame rate, and keeping every decision out of here is what keeps an effect from ever
## damaging anything.

const CORE := Color(0.88, 1.0, 0.86)
const GLOW := Color(0.25, 1.0, 0.3)
const EYE := Color(0.35, 1.0, 0.4)

## how bright the eyes sit when nothing is happening. that faint green is how you tell a laser kiwi
## from a plain one at a distance, since they share a model.
@export var idle_glow := 0.35
@export var beam_core_radius := 0.028
@export var beam_glow_radius := 0.085
@export var bolt_core_radius := 0.016
@export var bolt_glow_radius := 0.05
@export var light_range := 2.4

static var _cyl: CylinderMesh
static var _sphere: SphereMesh
static var _core_mat: StandardMaterial3D
static var _glow_mat: StandardMaterial3D
static var _eye_mat: StandardMaterial3D

var _skeleton: Skeleton3D
var _eye_l := -1
var _eye_r := -1
var _glow := 0.0
var _eye_meshes: Array[MeshInstance3D] = []
var _eye_light: OmniLight3D
var _beam_parts: Array[MeshInstance3D] = []
var _beam_on := false
var _beam_to := Vector3.ZERO
var _beam_light: OmniLight3D
var _sparks: GPUParticles3D
var _charge_parts: GPUParticles3D
var _voice: AudioStreamPlayer3D
var _hum: AudioStreamPlayer3D
var _time := 0.0


func _ready() -> void:
	_warm()
	for _i in 2:
		var eye := MeshInstance3D.new()
		eye.mesh = _sphere
		eye.material_override = _eye_mat
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(eye)
		_eye_meshes.append(eye)
	_eye_light = make_light(EYE, light_range)
	add_child(_eye_light)

	for i in 4:
		var part := MeshInstance3D.new()
		part.mesh = _cyl
		part.material_override = _core_mat if i % 2 == 0 else _glow_mat
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.visible = false
		add_child(part)
		_beam_parts.append(part)
	_beam_light = make_light(GLOW, 3.5)
	_beam_light.visible = false
	add_child(_beam_light)

	_sparks = _make_sparks()
	add_child(_sparks)
	_charge_parts = _make_charge()
	add_child(_charge_parts)

	_voice = _speaker(10.0)
	add_child(_voice)
	_hum = _speaker(12.0)
	add_child(_hum)
	set_glow(0.0)


## the rig has real eye bones, so the beams leave the eyes wherever the head clip has put them.
func bind(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	if _skeleton == null:
		return
	for i in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(i).to_lower()
		if bone_name.begins_with("eye.l"):
			_eye_l = i
		elif bone_name.begins_with("eye.r"):
			_eye_r = i
	if _eye_l < 0 or _eye_r < 0:
		for i in _skeleton.get_bone_count():
			if "head" in _skeleton.get_bone_name(i).to_lower():
				_eye_l = i
				_eye_r = i
				break


func eye_position(right: bool) -> Vector3:
	var bone := _eye_r if right else _eye_l
	if _skeleton != null and bone >= 0:
		return (_skeleton.global_transform * _skeleton.get_bone_global_pose(bone)).origin
	## no rig: a pair of points where a kiwi's eyes are, either side of its beak
	var owner_node := get_parent() as Node3D
	var base := owner_node.global_transform if owner_node != null else global_transform
	return base * Vector3(0.04 if right else -0.04, 0.45, -0.25)


func between_eyes() -> Vector3:
	return (eye_position(false) + eye_position(true)) * 0.5


## 0 is the resting ember, 1 is a charge about to fire.
func set_glow(level: float) -> void:
	_glow = clampf(level, 0.0, 1.0)


## the crack of one bolt leaving. the bolt itself is a LaserBolt, the kiwi launches it.
func zap() -> void:
	_voice.stream = LaserSfx.zap()
	_voice.pitch_scale = randf_range(0.92, 1.1)
	_voice.play()


## where a bolt or the beam lands: sparks off the world, and a flash of the same green on whatever it
## hit. a hit on the player throws no sparks: they would burst in the camera as pale squares, and
## the player already has the rim, the kick and the sound to say they were hit.
func impact(at: Vector3, on_player: bool) -> void:
	var world := get_tree().current_scene
	if not on_player:
		BurstFx.spawn(world, at, GLOW, 14, 2.4, 0.4)
		BurstFx.spawn(world, at, CORE, 5, 1.6, 0.3)
	var flash := make_light(GLOW, 2.5 if on_player else 2.0)
	world.add_child(flash)
	flash.global_position = at
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.12)
	tw.tween_callback(flash.queue_free)


func charge_start(duration: float) -> void:
	_charge_parts.emitting = true
	_hum.stream = LaserSfx.charge(duration)
	_hum.pitch_scale = 1.0
	_hum.play()


## a charge that is cut short fizzles, so the ear knows the beam is not coming.
func charge_stop(fizzle: bool) -> void:
	_charge_parts.emitting = false
	_hum.stop()
	if fizzle:
		_voice.stream = LaserSfx.zap()
		_voice.pitch_scale = 0.5
		_voice.play()


func beam_start() -> void:
	_beam_on = true
	_beam_light.visible = true
	_sparks.emitting = true
	_hum.stream = LaserSfx.beam()
	_hum.pitch_scale = 1.0
	_hum.play()


func beam_aim(to: Vector3, on_player := false) -> void:
	_beam_to = to
	_sparks.emitting = _beam_on and not on_player


func beam_stop() -> void:
	_beam_on = false
	for part in _beam_parts:
		part.visible = false
	_beam_light.visible = false
	_sparks.emitting = false
	_hum.stop()


func is_beaming() -> bool:
	return _beam_on


## the bird is down: no beam, no charge, no ember. a corpse with glowing eyes would keep the threat
## on screen after the threat is gone.
func shut_down() -> void:
	beam_stop()
	charge_stop(false)
	set_glow(0.0)
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_time += delta
	var flicker := 1.0 + (0.08 * sin(_time * 61.0) + 0.05 * sin(_time * 37.0)) * maxf(_glow, 0.15)
	var size_mul := lerpf(1.0, 2.6, _glow) * flicker
	for i in 2:
		var eye := _eye_meshes[i]
		eye.global_position = eye_position(i == 1)
		eye.scale = Vector3.ONE * size_mul
	var mid := between_eyes()
	_eye_light.global_position = mid
	_eye_light.light_energy = lerpf(idle_glow * 1.6, 8.0, _glow) * flicker
	_charge_parts.global_position = mid

	if _beam_on:
		var pulse := 1.0 + 0.18 * sin(_time * 110.0)
		for side in 2:
			var from := eye_position(side == 1)
			stretch(_beam_parts[side * 2], from, _beam_to, beam_core_radius * pulse)
			stretch(_beam_parts[side * 2 + 1], from, _beam_to, beam_glow_radius * pulse)
		var back := (mid - _beam_to).normalized() * 0.15
		_beam_light.global_position = _beam_to + back
		_beam_light.light_energy = 4.0 + 1.5 * sin(_time * 73.0)
		_sparks.global_position = _beam_to


## a unit cylinder stretched between two points: y is the run, x and z the radius. the basis is not
## orthonormal and does not need to be, it only draws.
static func stretch(mi: MeshInstance3D, from: Vector3, to: Vector3, radius: float) -> void:
	var d := to - from
	var length := d.length()
	if length < 0.01:
		mi.visible = false
		return
	mi.visible = true
	var y := d / length
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	mi.global_transform = Transform3D(Basis(x * radius, y * length, z * radius), from + d * 0.5)


## a core and a halo for a bolt, on the shared meshes and materials, so a burst allocates no render
## resources of its own.
static func dart_parts() -> Array[MeshInstance3D]:
	_warm()
	var out: Array[MeshInstance3D] = []
	for i in 2:
		var part := MeshInstance3D.new()
		part.mesh = _cyl
		part.material_override = _core_mat if i == 0 else _glow_mat
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.append(part)
	return out


static func _warm() -> void:
	if _cyl != null:
		return
	_cyl = CylinderMesh.new()
	_cyl.top_radius = 1.0
	_cyl.bottom_radius = 1.0
	_cyl.height = 1.0
	_cyl.radial_segments = 10
	_cyl.rings = 1
	_sphere = SphereMesh.new()
	_sphere.radius = 0.022
	_sphere.height = 0.044
	_sphere.radial_segments = 10
	_sphere.rings = 5

	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = CORE
	_core_mat.emission_enabled = true
	_core_mat.emission = CORE
	_core_mat.emission_energy_multiplier = 3.0
	_core_mat.disable_receive_shadows = true

	## additive on a tube is a glowing tube, which is what a beam's halo is. the trap is an additive
	## QUAD, that one reads as a glowing rectangle.
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.albedo_color = Color(GLOW, 0.45)
	_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_mat.no_depth_test = false
	_glow_mat.disable_receive_shadows = true

	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = EYE
	_eye_mat.emission_enabled = true
	_eye_mat.emission = EYE
	_eye_mat.emission_energy_multiplier = 2.5
	_eye_mat.disable_receive_shadows = true


static func make_light(colour: Color, range_m: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = colour
	l.omni_range = range_m
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.light_specular = 0.2
	return l


func _speaker(unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.unit_size = unit
	p.max_distance = 70.0
	p.volume_db = 0.0
	return p


## sparks thrown off the point where the beam lands, for as long as it lands.
func _make_sparks() -> GPUParticles3D:
	BurstFx.warm()
	var parts := GPUParticles3D.new()
	parts.amount = 48
	parts.lifetime = 0.35
	parts.emitting = false
	parts.explosiveness = 0.0
	parts.draw_pass_1 = BurstFx._quad
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.04
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.8
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.18
	pm.scale_max = 0.45
	pm.color_ramp = _ramp(CORE, GLOW)
	parts.process_material = pm
	return parts


## motes drawn INTO the eyes while the beam charges: emitted on a shell and pulled to the centre.
func _make_charge() -> GPUParticles3D:
	BurstFx.warm()
	var parts := GPUParticles3D.new()
	parts.amount = 70
	parts.lifetime = 0.45
	parts.emitting = false
	parts.explosiveness = 0.0
	parts.local_coords = true
	parts.draw_pass_1 = BurstFx._quad
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 0.42
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	if "radial_velocity_min" in pm:
		pm.radial_velocity_min = -2.2
		pm.radial_velocity_max = -1.4
	pm.scale_min = 0.3
	pm.scale_max = 0.7
	pm.color_ramp = _ramp(GLOW, CORE)
	parts.process_material = pm
	return parts


static func _ramp(a: Color, b: Color) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.set_color(0, Color(a.r, a.g, a.b, 1.0))
	grad.set_color(1, Color(b.r, b.g, b.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	return ramp
