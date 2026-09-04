class_name MortarKiwi
extends Kiwi

## indirect fire. the mortar kiwi holds its post and drops shells on the last place the compound knew
## you were, whether or not IT can see you, and that makes cover TEMPORARY: the failure mode of cover
## combat is both sides sitting still and trading, and this is what argues against sitting still.
## every shell is telegraphed by a ring on the ground that fills as it falls, so the answer is always
## on screen: be somewhere else when it lands. it is one bb to put down and it has no armour; it is
## dangerous because of where it sits, not because of what it takes to kill.

@export_group("Mortar")
@export var min_range := 8.0
@export var max_range := 60.0
@export var flight_time := 2.6
@export var cooldown := 6.0
## how long after being alarmed before the first shell. the tube has to be swung round.
@export var first_shot_delay := 1.5
@export var blast_radius := 3.5
@export var blast_damage := 38.0
## what is left of the damage when cover stands between the blast and you.
@export var cover_factor := 0.35
## the tube's report. a clip at this path is used when it exists; until then the synthesised cough
## below stands in, so a missing file leaves the mortar quiet rather than breaking the scene.
## a mortar is no use at arm's length. a player it can SEE inside this sends it running, and it
## goes back to the tube once it has put some ground between you. the shells have a minimum range
## for the same reason, so closing in is the counter and this is what makes closing in a chase.
@export var flee_range := 10.0

var _cool := 0.0
var _aim_at := Vector3.ZERO
var _has_aim := false
var _tube: Node3D
var _shots := 0


func _ready() -> void:
	super()
	add_to_group("mortar")
	_build_tube()


func _physics_process(delta: float) -> void:
	if _state == State.HUNT:
		_step_bombard(delta)
	super(delta)


## every alarm a plain kiwi answers by running, this one answers by bombarding.
func _on_alarmed(from: Vector3) -> void:
	_begin_bombard(from)


func told(at: Vector3) -> void:
	if _state == State.HUNT:
		_aim_at = at
		_has_aim = true
		return
	super(at)


func _begin_bombard(toward: Vector3) -> void:
	_aim_at = toward
	_has_aim = true
	_cool = first_shot_delay
	_state = State.HUNT
	if not idle_clips.is_empty():
		_play(idle_clips[0], 0.2)
	speak(alert_pitch, alert_db)
	Alarm.raise_search(toward)
	awareness_changed.emit(self, 1.0)


func _step_bombard(delta: float) -> void:
	if Alarm.stage == Alarm.Stage.CALM:
		_end_bombard()
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	## the same sense the alarm uses, so a crouched player creeps closer before it bolts: exposure_to
	## applies the crouch range scale and sees_point does not.
	if player != null and global_position.distance_to(player.global_position) <= flee_range \
			and vision.exposure_to(player) > 0.0:
		_begin_flee(player.global_position)
		return
	velocity.x = move_toward(velocity.x, 0.0, walk_speed * 6.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, walk_speed * 6.0 * delta)
	## the compound's knowledge is the fire plan, and that is what indirect fire IS: a bird seeing
	## you, a runner's shout, the gunship's mark. it is only worth aiming at because VisionCone keeps
	## it fresh while ANY bird can see you, alerted or not; before that it froze at the spot where
	## the mortar first caught you and every shell after that landed there.
	## the fire plan is the compound's belief INCLUDING how old it is. a fresh contact is shelled
	## accurately and a cold one is area fire you can walk out of, which is what stops a mortar
	## from being a turret that always knows the answer.
	if Alarm.has_last_known:
		_aim_at = Alarm.search_point(get_instance_id())
		_has_aim = true
	if not _has_aim:
		return
	_turn_to(_aim_at, turn_speed, delta)
	_cool -= delta
	if _cool > 0.0:
		return
	var flat := Vector2(_aim_at.x - global_position.x, _aim_at.z - global_position.z).length()
	if flat < min_range or flat > max_range:
		_cool = 0.5
		return
	_fire(_aim_at)
	_cool = cooldown


func _fire(at: Vector3) -> void:
	_shots += 1
	var from := _tube.global_position + Vector3.UP * 0.3 if _tube != null else global_position + Vector3.UP * 0.6
	MortarShell.launch(get_tree().current_scene, from, at, flight_time, blast_radius, blast_damage, cover_factor, self)
	Sfx.play(&"mortar_fire", from)
	BurstFx.spawn(get_tree().current_scene, from, Color(0.6, 0.55, 0.5), 10, 2.5, 0.5)


func _end_bombard() -> void:
	_has_aim = false
	vision.rearm()
	awareness_changed.emit(self, 0.0)
	_begin_idle()


func stand_down() -> void:
	if _state == State.DOWN:
		return
	if _state == State.HUNT:
		_end_bombard()
	super()


## having run, it goes back to the tube if the compound is still hot, else back to loafing.
func _end_flee() -> void:
	if Alarm.is_hot() and _has_aim:
		_home = global_position
		_begin_bombard(_aim_at)
		return
	super()


## the tube goes with the bird. it is a child of the body, not of the model, so the vanish that hides
## the model would have left a mortar standing on nothing.
func _go_down() -> void:
	if _state == State.DOWN:
		return
	awareness_changed.emit(self, 0.0)
	if _tube != null:
		BurstFx.spawn(get_tree().current_scene, _tube.global_position, Color(0.3, 0.3, 0.32), 14, 3.5, 0.6)
		_tube.visible = false
	super()


func tube_visible() -> bool:
	return _tube != null and _tube.visible


func is_bombarding() -> bool:
	return _state == State.HUNT


func shots_fired() -> int:
	return _shots


## the mortar itself: a base plate and a tube on the bird's back, angled up and forward.
func _build_tube() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.16, 0.17, 0.18)
	metal.roughness = 0.55
	metal.metallic = 0.5
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.85, 0.45, 0.15)
	trim.emission_enabled = true
	trim.emission = Color(0.85, 0.45, 0.15)
	trim.emission_energy_multiplier = 0.6
	_tube = Node3D.new()
	_tube.position = Vector3(0.0, 0.42, 0.06)
	add_child(_tube)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.26, 0.04, 0.22)
	plate.mesh = pm
	plate.material_override = metal
	_tube.add_child(plate)
	var barrel := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.055
	bm.bottom_radius = 0.07
	bm.height = 0.5
	bm.radial_segments = 10
	barrel.mesh = bm
	barrel.material_override = metal
	barrel.position = Vector3(0.0, 0.22, -0.08)
	barrel.rotation_degrees = Vector3(-32.0, 0.0, 0.0)
	_tube.add_child(barrel)
	var band := MeshInstance3D.new()
	var bb := CylinderMesh.new()
	bb.top_radius = 0.062
	bb.bottom_radius = 0.062
	bb.height = 0.03
	bb.radial_segments = 10
	band.mesh = bb
	band.material_override = trim
	band.position = Vector3(0.0, 0.14, 0.0)
	barrel.add_child(band)
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.03, 0.3, 0.03)
		leg.mesh = lm
		leg.material_override = metal
		leg.position = Vector3(side * 0.1, 0.16, 0.08)
		leg.rotation_degrees = Vector3(20.0, 0.0, side * -18.0)
		_tube.add_child(leg)
