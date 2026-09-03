class_name AlarmHorn
extends StaticBody3D

## the compound's klaxon on a post. a runner that reaches it pulls the lever and the whole garrison
## goes to ALARM; the player can cut it first, and then the runners have to find a friend instead.
## built from primitives in _ready like the range target, so there is no model to import and it
## reads at a distance, which matters because the player has to be able to find it before the
## runner does. it decides nothing about the alarm itself: it tells Alarm, and Alarm tells it when
## the compound has calmed down so the siren stops and it can be pulled again.

signal raised(by: Node)
signal cut

const METAL := Color(0.16, 0.17, 0.18)
const BAND := Color(0.72, 0.12, 0.1)
const LIT := Color(1.0, 0.28, 0.16)
const RATE := 22050

@export var post_height := 2.3
@export var prompt := "Cut the horn"
@export var can_be_cut := true
## quieter than it was: the first cut was loud enough to be heard over the whole level at full
## volume, and a siren that is everywhere tells you nothing about where.
@export var siren_db := -7.0

static var _siren_stream: AudioStreamWAV

var _raised := false
var _disabled := false
var _time := 0.0
var _head: MeshInstance3D
var _beacon: MeshInstance3D
var _beacon_mat: StandardMaterial3D
var _band_mat: StandardMaterial3D
var _light: OmniLight3D
var _siren: AudioStreamPlayer3D
var _interact: Interactable


func _ready() -> void:
	add_to_group("alarm_horn")
	collision_layer = 1
	collision_mask = 0
	_build()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.16
	cyl.height = post_height
	shape.shape = cyl
	shape.position = Vector3(0.0, post_height * 0.5, 0.0)
	add_child(shape)

	_interact = Interactable.new()
	_interact.prompt = prompt
	_interact.set_enabled(can_be_cut)
	add_child(_interact)
	_interact.interacted.connect(func(_by: Node) -> void: cut_horn())

	_siren = AudioStreamPlayer3D.new()
	_siren.unit_size = 14.0
	_siren.max_distance = 140.0
	_siren.volume_db = siren_db
	_siren.position = Vector3(0.0, post_height, 0.0)
	add_child(_siren)

	Alarm.stage_changed.connect(_on_stage)


func _build() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = METAL
	metal.roughness = 0.6
	metal.metallic = 0.5
	_band_mat = StandardMaterial3D.new()
	_band_mat.albedo_color = BAND
	_band_mat.roughness = 0.7
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = LIT
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = LIT
	_beacon_mat.emission_energy_multiplier = 0.0

	var post := MeshInstance3D.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.05
	pole.bottom_radius = 0.07
	pole.height = post_height
	pole.radial_segments = 10
	post.mesh = pole
	post.material_override = metal
	post.position = Vector3(0.0, post_height * 0.5, 0.0)
	add_child(post)

	var foot := MeshInstance3D.new()
	var plate := CylinderMesh.new()
	plate.top_radius = 0.22
	plate.bottom_radius = 0.26
	plate.height = 0.06
	plate.radial_segments = 12
	foot.mesh = plate
	foot.material_override = metal
	foot.position = Vector3(0.0, 0.03, 0.0)
	add_child(foot)

	## the red band is what says "alarm" from across the yard, lit or not
	var band := MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = 0.075
	ring.bottom_radius = 0.075
	ring.height = 0.3
	ring.radial_segments = 10
	band.mesh = ring
	band.material_override = _band_mat
	band.position = Vector3(0.0, post_height - 0.55, 0.0)
	add_child(band)

	## the klaxon: a cone leaning forward and down off the top of the post
	_head = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.24
	cone.bottom_radius = 0.07
	cone.height = 0.42
	cone.radial_segments = 12
	_head.mesh = cone
	_head.material_override = metal
	_head.position = Vector3(0.0, post_height - 0.15, -0.22)
	_head.rotation_degrees = Vector3(-70.0, 0.0, 0.0)
	add_child(_head)

	## the small box the lever lives in, at hand height. this is what "cut" is about.
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.24, 0.1)
	box.mesh = bm
	box.material_override = metal
	box.position = Vector3(0.0, 1.25, 0.1)
	add_child(box)

	_beacon = MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.09
	bulb.height = 0.18
	bulb.radial_segments = 10
	bulb.rings = 5
	_beacon.mesh = bulb
	_beacon.material_override = _beacon_mat
	_beacon.position = Vector3(0.0, post_height + 0.08, 0.0)
	add_child(_beacon)

	_light = OmniLight3D.new()
	_light.light_color = LIT
	_light.omni_range = 9.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, post_height + 0.1, 0.0)
	_light.visible = false
	add_child(_light)


func _process(delta: float) -> void:
	if not _raised:
		return
	_time += delta
	## a turning beacon: the pulse is what the eye reads as "alarm" from a distance
	var pulse := 0.5 + 0.5 * sin(_time * 9.0)
	_beacon_mat.emission_energy_multiplier = 1.5 + 4.5 * pulse
	_light.light_energy = 1.0 + 5.0 * pulse
	_beacon.rotation.y += delta * 6.0


## a runner reached it. the compound goes to ALARM, the siren starts and the beacon lights.
func raise(by: Node) -> void:
	if _disabled:
		return
	Alarm.raise_alarm(global_position)
	if _raised:
		return
	_raised = true
	_time = 0.0
	_light.visible = true
	_siren.stream = siren()
	_siren.play()
	raised.emit(by)


## the player cut it. runners skip it from now on and have to find a friend instead, which is the
## pre-emptive stealth play: something to do about the horn BEFORE being seen.
func cut_horn() -> void:
	if _disabled:
		return
	_disabled = true
	_quiet()
	_interact.set_enabled(false)
	_head.rotation_degrees = Vector3(-120.0, 0.0, 0.0)
	_band_mat.albedo_color = BAND.darkened(0.5)
	cut.emit()


## for tools and probes that need the horn back.
func restore() -> void:
	_disabled = false
	_interact.set_enabled(can_be_cut)
	_head.rotation_degrees = Vector3(-70.0, 0.0, 0.0)
	_band_mat.albedo_color = BAND


func is_usable() -> bool:
	return not _disabled


func is_raised() -> bool:
	return _raised


func is_cut() -> bool:
	return _disabled


func _on_stage(stage: int) -> void:
	if stage != Alarm.Stage.ALARM:
		_quiet()


func _quiet() -> void:
	_raised = false
	_siren.stop()
	_light.visible = false
	_light.light_energy = 0.0
	_beacon_mat.emission_energy_multiplier = 0.0


## a two tone siren that loops without a seam: the sweep is symmetric over the loop and its mean
## frequency fits a whole number of cycles in it, so the phase lands back where it started.
static func siren() -> AudioStreamWAV:
	if _siren_stream != null:
		return _siren_stream
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f := 620.0 + 140.0 * sin(TAU * t)
		phase += TAU * f / float(RATE)
		var v := sin(phase) + 0.5 * sin(2.0 * phase) + 0.25 * sin(3.0 * phase)
		out[i] = tanh(v * 0.7)
	_siren_stream = Tone.wav(out, true, RATE)
	return _siren_stream
