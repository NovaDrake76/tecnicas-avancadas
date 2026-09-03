class_name KiwiArmour
extends Node3D

## what an armoured kiwi wears, and the weak point it frames. plate you can SEE: a visor band across
## the brow with the eyes in the slot under it, a chest plate and a back plate with the laser green
## trim, so the player is told at a glance both that this bird will shrug off a plinked bb and where
## the one shot that will not be shrugged off has to land. built from primitives in _ready like the
## range target and the horn, PSX flat like everything else.
##
## the head pieces follow the head BONE. the rig's axes are the rigger's business, so nothing here
## assumes one: at the first frame the head's pose is compared with the body's facing and that one
## comparison fixes a calibration for good, the same trick the vision cone uses. it draws and reports
## hits; every decision about damage is the kiwi's.

const METAL := Color(0.14, 0.15, 0.16)
const METAL_LIGHT := Color(0.24, 0.25, 0.27)
const TRIM := LaserEyes.GLOW
const LEADER_TRIM := Color(0.75, 1.0, 0.55)

## the weak point box: the eyes are 77 mm apart, so this covers both with a little to spare.
@export var weak_size := Vector3(0.15, 0.09, 0.09)
## how far forward of the eye midpoint the weak point sits, so it is the first thing a bb from the
## front meets rather than the body capsule behind it.
@export var weak_forward := 0.015

var _kiwi: CharacterBody3D
var _eyes: LaserEyes
var _skeleton: Skeleton3D
var _bone := -1
var _calib := Basis.IDENTITY
var _bound := false
var _head_rig: Node3D
var _weak: WeakPoint
var _plates: Array[MeshInstance3D] = []
var _trims: Array[MeshInstance3D] = []
var _plate_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _chevron: MeshInstance3D
var _flash := 0.0
var _shed := false
var _leader := false


func bind(kiwi: CharacterBody3D, eyes: LaserEyes) -> void:
	_kiwi = kiwi
	_eyes = eyes
	_skeleton = kiwi.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton != null:
		for i in _skeleton.get_bone_count():
			if "head" in _skeleton.get_bone_name(i).to_lower():
				_bone = i
				break
	_build_body_plates()
	_head_rig = Node3D.new()
	_head_rig.top_level = true
	add_child(_head_rig)
	_weak = WeakPoint.new()
	_weak.setup(kiwi, weak_size)
	_head_rig.add_child(_weak)
	_build_visor()


func _build_materials() -> void:
	if _plate_mat != null:
		return
	_plate_mat = StandardMaterial3D.new()
	_plate_mat.albedo_color = METAL
	_plate_mat.roughness = 0.55
	_plate_mat.metallic = 0.6
	_plate_mat.emission_enabled = true
	_plate_mat.emission = Color.WHITE
	_plate_mat.emission_energy_multiplier = 0.0
	_trim_mat = StandardMaterial3D.new()
	_trim_mat.albedo_color = TRIM
	_trim_mat.emission_enabled = true
	_trim_mat.emission = TRIM
	_trim_mat.emission_energy_multiplier = 1.2
	_trim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _plate(parent: Node3D, size: Vector3, at: Vector3, trim_y: float) -> MeshInstance3D:
	_build_materials()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = _plate_mat
	mi.position = at
	parent.add_child(mi)
	_plates.append(mi)
	var band := MeshInstance3D.new()
	var strip := BoxMesh.new()
	strip.size = Vector3(size.x * 0.92, 0.012, size.z + 0.004)
	band.mesh = strip
	band.material_override = _trim_mat
	band.position = Vector3(0.0, trim_y, 0.0)
	mi.add_child(band)
	_trims.append(band)
	return mi


## the chest and back plates ride the body, so they are plain children of the kiwi.
func _build_body_plates() -> void:
	_plate(self, Vector3(0.24, 0.17, 0.05), Vector3(0.0, 0.3, -0.16), 0.02)
	var back := _plate(self, Vector3(0.22, 0.15, 0.05), Vector3(0.0, 0.32, 0.15), 0.0)
	_chevron = MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.09, 0.05, 0.01)
	_chevron.mesh = prism
	_chevron.material_override = _trim_mat
	_chevron.position = Vector3(0.0, 0.03, 0.031)
	_chevron.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	_chevron.visible = false
	back.add_child(_chevron)


## the visor band sits over the eyes on the head rig, framing the slot the weak point fills.
func _build_visor() -> void:
	_build_materials()
	var band := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.17, 0.03, 0.06)
	band.mesh = box
	band.material_override = _plate_mat
	band.name = "Visor"
	_head_rig.add_child(band)
	_plates.append(band)
	var strip := MeshInstance3D.new()
	var thin := BoxMesh.new()
	thin.size = Vector3(0.17, 0.006, 0.062)
	strip.mesh = thin
	strip.material_override = _trim_mat
	strip.position = Vector3(0.0, -0.012, 0.0)
	band.add_child(strip)
	_trims.append(strip)
	for side in [-1.0, 1.0]:
		var cheek := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.03, 0.09, 0.06)
		cheek.mesh = cb
		cheek.material_override = _plate_mat
		cheek.position = Vector3(side * 0.085, -0.045, 0.0)
		band.add_child(cheek)
		_plates.append(cheek)


## the head rig is placed at the head bone every frame, with the calibration that makes its axes
## the body's at rest. then the weak point and the visor are plain offsets in a frame that means
## "forward is where the bird looks".
func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		_plate_mat.emission_energy_multiplier = _flash * 3.0
	if _kiwi == null or _head_rig == null:
		return
	var head := _head_transform()
	if not _bound:
		if _eyes == null:
			return
		_calib = head.basis.orthonormalized().inverse() * _kiwi.global_transform.basis.orthonormalized()
		_bound = true
		_head_rig.global_transform = Transform3D(head.basis.orthonormalized() * _calib, head.origin)
		var mid := _head_rig.global_transform.affine_inverse() * _eyes.between_eyes()
		_weak.position = mid + Vector3(0.0, 0.0, -weak_forward)
		var visor := _head_rig.get_node("Visor") as Node3D
		visor.position = mid + Vector3(0.0, weak_size.y * 0.5 + 0.012, -0.005)
		return
	_head_rig.global_transform = Transform3D(head.basis.orthonormalized() * _calib, head.origin)


func _head_transform() -> Transform3D:
	if _skeleton != null and _bone >= 0:
		return _skeleton.global_transform * _skeleton.get_bone_global_pose(_bone)
	return _kiwi.global_transform.translated_local(Vector3(0.0, 0.45, -0.2))


## a qualifying hit: the plate flashes white and throws grey sparks.
func dent(at: Vector3) -> void:
	_flash = 1.0
	var world := get_tree().current_scene
	var where := at if at.is_finite() else global_position + Vector3.UP * 0.3
	BurstFx.spawn(world, where, Color(0.8, 0.8, 0.82), 12, 2.6, 0.35)
	BurstFx.spawn(world, where, Color(0.4, 0.4, 0.42), 8, 1.8, 0.4)


## a bb that arrived too slow to matter: a white spark and a ping, nothing else.
func bounce(at: Vector3) -> void:
	_flash = 0.35
	var world := get_tree().current_scene
	var where := at if at.is_finite() else global_position + Vector3.UP * 0.3
	BurstFx.spawn(world, where, Color(1.0, 1.0, 1.0), 8, 2.2, 0.25)
	ImpactFx.flash(world, where, Color(1.0, 1.0, 0.95), 0.8, 0.08)
	var ping := AudioStreamPlayer3D.new()
	ping.stream = ping_sound()
	ping.unit_size = 8.0
	ping.max_distance = 60.0
	ping.pitch_scale = randf_range(0.94, 1.08)
	world.add_child(ping)
	ping.global_position = where
	ping.finished.connect(ping.queue_free)
	ping.play()


## the plates come off before the bird does, which is the clearest possible "that one worked".
func shed() -> void:
	if _shed:
		return
	_shed = true
	var world := get_tree().current_scene
	for p in _plates:
		if p.visible:
			BurstFx.spawn(world, p.global_position, METAL_LIGHT, 10, 3.0, 0.5)
		p.visible = false
	if _weak != null:
		_weak.collision_layer = 0


func is_shed() -> bool:
	return _shed


## the leader's trim is brighter and it wears a chevron on the back plate, so the priority target
## is legible from behind, which is where a stalking player usually is.
func set_leader(leader: bool) -> void:
	_leader = leader
	_build_materials()
	_trim_mat.albedo_color = LEADER_TRIM if leader else TRIM
	_trim_mat.emission = LEADER_TRIM if leader else TRIM
	_trim_mat.emission_energy_multiplier = 2.4 if leader else 1.2
	if _chevron != null:
		_chevron.visible = leader


func is_leader() -> bool:
	return _leader


func weak_point() -> WeakPoint:
	return _weak


func weak_centre() -> Vector3:
	return _weak.global_position if _weak != null else global_position


func hide_all() -> void:
	visible = false
	if _head_rig != null:
		_head_rig.visible = false
	if _weak != null:
		_weak.collision_layer = 0
	set_process(false)


static var _ping: AudioStreamWAV


## a short metallic ping: two close partials that beat against each other, decaying fast.
static func ping_sound() -> AudioStreamWAV:
	if _ping != null:
		return _ping
	var rate := Tone.RATE
	var n := int(rate * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(rate)
		var u := float(i) / float(n)
		var env := exp(-u * 9.0)
		var v := sin(TAU * 3100.0 * t) * 0.6 + sin(TAU * 3380.0 * t) * 0.45 + sin(TAU * 5200.0 * t) * 0.2
		out[i] = tanh(v * env * 1.3)
	_ping = Tone.wav(out)
	return _ping
