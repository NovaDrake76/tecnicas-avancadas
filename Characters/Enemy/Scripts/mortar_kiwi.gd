class_name MortarKiwi
extends Kiwi


@export_group("Mortar")
@export var min_range := 8.0
@export var max_range := 60.0
@export var flight_time := 2.6
@export var cooldown := 6.0
## how long after being alarmed before the first shell.
@export var first_shot_delay := 1.5
@export var blast_radius := 3.5
@export var blast_damage := 38.0
## what is left of the damage when cover stands between the blast and you.
@export var cover_factor := 0.35
## the tube's report.
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


func _on_alarmed(from: Vector3) -> void:
	_begin_bombard(from)


func _step_hunt(_delta: float) -> void:
	pass


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
	voice.alarm()
	Alarm.raise_search(toward)
	awareness_changed.emit(self, 1.0)


func _step_bombard(delta: float) -> void:
	if Alarm.stage == Alarm.Stage.CALM:
		_end_bombard()
		return
	var player := Player.nearest(get_tree(), global_position)
	## exposure_to and not sees_point: only exposure_to applies the crouch range scale, so a crouched player creeps closer before it bolts.
	if player != null and global_position.distance_to(player.global_position) <= flee_range \
			and vision.exposure_to(player) > 0.0:
		_begin_flee(player.global_position)
		return
	velocity.x = move_toward(velocity.x, 0.0, walk_speed * 6.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, walk_speed * 6.0 * delta)
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
	_net_shell.rpc(from, at)


@rpc("authority", "call_local", "reliable")
func _net_shell(from: Vector3, at: Vector3) -> void:
	MortarShell.launch(get_tree().current_scene, from, at, flight_time, blast_radius,
		blast_damage if multiplayer.is_server() else 0.0, cover_factor, self)
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


func _end_flee() -> void:
	if Alarm.is_hot() and _has_aim:
		_home = global_position
		_begin_bombard(_aim_at)
		return
	super()


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


func _build_tube() -> void:
	_tube = build_mortar(self, find_child("Skeleton3D", true, false) as Skeleton3D)


static func build_mortar(kiwi: Node3D, skeleton: Skeleton3D) -> Node3D:
	var metal := KitMesh.matte(Color(0.2, 0.21, 0.2), 0.6, 0.4)
	var canvas := KitMesh.matte(Color(0.25, 0.25, 0.18), 1.0, 0.0)
	var bomb_paint := KitMesh.matte(Color(0.3, 0.32, 0.22), 0.8, 0.1)
	var trim := KitMesh.glow(Color(0.85, 0.45, 0.15), 0.6)
	KiwiBody.fit(kiwi, skeleton, KiwiArmour.eye_mid_at_rest(kiwi, skeleton) + KiwiSuit.HEAD_AT)
	var seat := KiwiBody.body_point(PI, 1.15, 0.03)
	var rig := BoneRig.on(kiwi, skeleton, KiwiArmour.TORSO_BONE)
	var root := Node3D.new()
	root.position = seat
	rig.frame.add_child(root)
	var saddle := KiwiBody.body_patch(PI - 0.62, PI + 0.62, 0.9, 1.42, 12, 6, 0.026, 0.014)
	KitMesh.put(saddle, canvas, root, -seat, "Saddle")
	var belt := KiwiBody.body_patch(-PI, PI, 0.3, 0.44, 28, 2, 0.011, 0.004)
	KitMesh.put(belt, canvas, root, -seat, "Belt")
	var upper := KiwiBody.body_patch(PI - 1.35, PI + 1.35, 0.62, 0.74, 20, 2, 0.011, 0.004)
	KitMesh.put(upper, canvas, root, -seat, "BeltUpper")
	var cup := KitMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.066, 0.022),
		Vector2(0.046, 0.022), Vector2(0.046, 0.006), Vector2(0.0, 0.006)]), 16, Callable(),
		PackedFloat32Array(), PackedInt32Array([1, 2, 3, 4]))
	KitMesh.put(cup, metal, root, Vector3(0.0, 0.002, 0.0), "Socket")
	var pivot := Node3D.new()
	pivot.name = "Tube"
	pivot.position = Vector3(0.0, 0.016, 0.0)
	pivot.rotation_degrees = Vector3(-28.0, 0.0, 0.0)
	root.add_child(pivot)
	var barrel := KitMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.032, 0.0), Vector2(0.042, 0.02),
		Vector2(0.042, 0.04), Vector2(0.048, 0.05), Vector2(0.048, 0.4), Vector2(0.056, 0.4), Vector2(0.056, 0.44),
		Vector2(0.04, 0.44), Vector2(0.04, 0.41), Vector2(0.0, 0.41)]), 16, Callable(), PackedFloat32Array(),
		PackedInt32Array([1, 2, 3, 4, 5, 6, 7, 8, 9]))
	KitMesh.put(barrel, metal, pivot, Vector3.ZERO, "Barrel")
	var ring := KitMesh.lathe(PackedVector2Array([Vector2(0.046, 0.33), Vector2(0.052, 0.33), Vector2(0.052, 0.3),
		Vector2(0.046, 0.3)]), 16, Callable(), PackedFloat32Array(), PackedInt32Array([0, 1, 2, 3]))
	KitMesh.put(ring, trim, pivot, Vector3.ZERO, "Band")
	var collar := KitMesh.lathe(PackedVector2Array([Vector2(0.046, 0.215), Vector2(0.06, 0.215), Vector2(0.06, 0.19),
		Vector2(0.046, 0.19)]), 16, Callable(), PackedFloat32Array(), PackedInt32Array([0, 1, 2, 3]))
	KitMesh.put(collar, metal, pivot, Vector3.ZERO, "Collar")
	var axis := pivot.basis * Vector3.UP
	var hinge := pivot.position + axis * 0.2
	var feet: Array[Vector3] = []
	for side in [-1.0, 1.0]:
		var top := hinge + pivot.basis * Vector3(side * 0.058, 0.0, 0.0)
		var foot: Vector3 = KiwiBody.body_point(PI - side * 0.62, 0.92, 0.014) - seat
		feet.append(foot)
		KitMesh.rod(root, top, foot, 0.007, metal)
		var shoe := KitMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.018, 0.0), Vector2(0.018, 0.012),
			Vector2(0.0, 0.012)]), 10, Callable(), PackedFloat32Array(), PackedInt32Array([1, 2]))
		KitMesh.put(shoe, metal, root, foot - Vector3(0.0, 0.002, 0.0), "Shoe")
	var mid_l: Vector3 = (hinge + pivot.basis * Vector3(-0.058, 0.0, 0.0)).lerp(feet[0], 0.45)
	var mid_r: Vector3 = (hinge + pivot.basis * Vector3(0.058, 0.0, 0.0)).lerp(feet[1], 0.45)
	KitMesh.rod(root, mid_l, mid_r, 0.006, metal)
	var screw := KitMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.012, 0.0), Vector2(0.012, 0.03),
		Vector2(0.0, 0.03)]), 10, Callable(), PackedFloat32Array(), PackedInt32Array([1, 2]))
	var knob := KitMesh.put(screw, metal, root, (mid_l + mid_r) * 0.5 - Vector3(0.0, 0.015, 0.0))
	knob.name = "Elevation"
	var sight := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.022, 0.03, 0.05)
	sight.mesh = sb
	sight.material_override = metal
	sight.position = Vector3(-0.078, 0.0, 0.0)
	sight.rotation_degrees = Vector3(-28.0, 0.0, 0.0)
	var sight_pivot := Node3D.new()
	sight_pivot.position = hinge
	root.add_child(sight_pivot)
	sight_pivot.add_child(sight)
	var lens := KitMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.007, 0.0), Vector2(0.007, 0.004),
		Vector2(0.0, 0.004)]), 8, Callable(), PackedFloat32Array(), PackedInt32Array([1, 2]))
	var eye := KitMesh.put(lens, trim, sight, Vector3(0.0, 0.0, -0.027))
	eye.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var bomb := KitMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.014, 0.024), Vector2(0.023, 0.05),
		Vector2(0.023, 0.11), Vector2(0.013, 0.13), Vector2(0.009, 0.13), Vector2(0.009, 0.172), Vector2(0.013, 0.172),
		Vector2(0.013, 0.182), Vector2(0.0, 0.182)]), 12, Callable(), PackedFloat32Array(),
		PackedInt32Array([2, 3, 4, 5, 6, 7, 8]))
	var nose := KitMesh.lathe(PackedVector2Array([Vector2(0.0205, 0.052), Vector2(0.0245, 0.052), Vector2(0.0245, 0.066),
		Vector2(0.0205, 0.066)]), 12, Callable(), PackedFloat32Array(), PackedInt32Array([0, 1, 2, 3]))
	for side in [-1.0, 1.0]:
		var shell := Node3D.new()
		shell.position = KiwiBody.body_point(PI - side * 0.78, 1.0, 0.032) - seat
		shell.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		root.add_child(shell)
		KitMesh.put(bomb, bomb_paint, shell, Vector3.ZERO, "Bomb")
		KitMesh.put(nose, trim, shell, Vector3.ZERO, "Nose")
		for k in 4:
			var fin := MeshInstance3D.new()
			var fb := BoxMesh.new()
			fb.size = Vector3(0.003, 0.034, 0.026)
			fin.mesh = fb
			fin.material_override = bomb_paint
			fin.position = Vector3(0.0, 0.158, 0.0)
			fin.rotation_degrees = Vector3(0.0, 45.0 + 90.0 * float(k), 0.0)
			var fin_pivot := Node3D.new()
			fin_pivot.rotation_degrees = Vector3(0.0, 45.0 + 90.0 * float(k), 0.0)
			shell.add_child(fin_pivot)
			fin.rotation_degrees = Vector3.ZERO
			fin.position = Vector3(0.0, 0.158, 0.019)
			fin_pivot.add_child(fin)
	return root


func kind_name() -> String:
	return "MORTAR"
