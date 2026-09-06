class_name KiwiBody
extends Node

@export_group("Down")
## a downed bird TIPS OVER rather than playing the settle clip, which leaves it standing with its eyes shut.
@export var lie_down := true
@export var lie_roll_deg := 84.0
@export var lie_time := 0.35
## how hard the ground slows a thrown body: friction, not a timer, so a hard throw travels further.
@export var throw_friction := 14.0
## the two crosses over the eyes.
@export var mark_eyes := true
@export var eye_mark_size := 0.075
## OFF by default: a downed kiwi stays lying where it fell, which is what makes where you drop one a decision.
@export var vanish_on_down := false
## long enough for the slowest, lowest call to finish before the node carrying it is freed.
@export var despawn_delay := 1.6

@export_group("Down burst")
@export var burst_light := Color(0.55, 0.4, 0.2)
@export var burst_dark := Color(0.22, 0.15, 0.09)
@export var burst_count := 34
@export var burst_speed := 3.8

var _kiwi: Kiwi
var _model: Node3D
var _found := false
var _dragged := false
var _thrown := false
var _tumble := 0.0
var _handle: Area3D
var _grab: Interactable


func _ready() -> void:
	_kiwi = get_parent() as Kiwi
	_model = _kiwi.get_node_or_null("Model") as Node3D


func collapse(at: Vector3) -> void:
	var world := get_tree().current_scene
	BurstFx.spawn(world, at, burst_light, burst_count, burst_speed)
	BurstFx.spawn(world, at, burst_dark, int(burst_count * 0.6), burst_speed * 0.8)
	if not vanish_on_down:
		_lie_down()
		_mark_eyes()
		_become_body()
		return
	if _model != null:
		_model.visible = false
	Sfx.play(&"kiwi_poof", at)
	_kiwi.set_physics_process(false)
	## the node outlives the burst by a moment; the particles are parented to the world, not to us.
	get_tree().create_timer(despawn_delay).timeout.connect(_kiwi.queue_free)


func toss(launch: Vector3, spin: float) -> void:
	if not _kiwi.is_down():
		return
	_thrown = true
	_tumble = spin
	_kiwi.velocity = launch
	_kiwi.set_physics_process(true)


func step_thrown(delta: float) -> bool:
	if not _thrown:
		return false
	_kiwi.velocity.y -= _kiwi.gravity * delta
	if _model != null:
		_model.rotation.x += _tumble * delta
	if _kiwi.is_on_floor():
		_kiwi.velocity.x = move_toward(_kiwi.velocity.x, 0.0, throw_friction * delta)
		_kiwi.velocity.z = move_toward(_kiwi.velocity.z, 0.0, throw_friction * delta)
		_tumble = move_toward(_tumble, 0.0, throw_friction * delta)
	_kiwi.move_and_slide()
	if not _kiwi.is_on_floor() or Vector2(_kiwi.velocity.x, _kiwi.velocity.z).length() > 0.4:
		return true
	_thrown = false
	_kiwi.velocity = Vector3.ZERO
	if _model != null:
		_model.rotation.x = 0.0
		_model.rotation.z = deg_to_rad(lie_roll_deg)
		_model.position.y = lie_lift(deg_to_rad(lie_roll_deg))
	Sfx.play(&"body_drop", _kiwi.global_position)
	return true


func is_thrown() -> bool:
	return _thrown


func set_dragged(value: bool) -> void:
	_dragged = value
	if _grab != null:
		_grab.set_enabled(not value)
	if _model != null:
		_model.rotation.z = 0.0 if value else deg_to_rad(lie_roll_deg)
		_model.position.y = 0.0 if value else lie_lift(deg_to_rad(lie_roll_deg))


func is_dragged() -> bool:
	return _dragged


func mark_found() -> void:
	_found = true


func is_found() -> bool:
	return _found


func _become_body() -> void:
	_kiwi.add_to_group("body")
	_handle = Area3D.new()
	_handle.collision_layer = 128
	_handle.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.75, 0.5, 0.75)
	shape.shape = box
	shape.position = Vector3(0.0, 0.25, 0.0)
	_handle.add_child(shape)
	_kiwi.add_child(_handle)
	_grab = Interactable.new()
	_grab.prompt = "Pick the body up"
	_kiwi.add_child(_grab)
	_grab.interacted.connect(_on_grab_pressed)


func _on_grab_pressed(_by: Node) -> void:
	for node in get_tree().get_nodes_in_group("body_drag"):
		var drag := node as BodyDrag
		if drag != null:
			drag.grab(_kiwi)
			return


func _lie_down() -> void:
	if not lie_down or _model == null:
		return
	var roll := deg_to_rad(lie_roll_deg)
	var lift := lie_lift(roll)
	var over := create_tween()
	over.set_trans(Tween.TRANS_CUBIC)
	over.set_ease(Tween.EASE_OUT)
	over.tween_property(_model, "rotation:z", roll, lie_time)
	over.parallel().tween_property(_model, "position:y", lift, lie_time)


func lie_lift(roll: float) -> float:
	if _model == null:
		return 0.0
	var bounds := AABB()
	var first := true
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var box := (_model.global_transform.affine_inverse() * mesh.global_transform) * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		return _model.position.y
	var turn := Basis(Vector3.BACK, roll)
	var lowest := INF
	for i in 8:
		lowest = minf(lowest, (turn * bounds.get_endpoint(i)).y)
	return maxf(-lowest, 0.0)


func _mark_eyes() -> void:
	if not mark_eyes:
		return
	var skeleton: Skeleton3D = null
	for node in _kiwi.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	if skeleton == null:
		return
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(i).to_lower()
		if not (bone.begins_with("eye.l") or bone.begins_with("eye.r")):
			continue
		var mount := BoneAttachment3D.new()
		mount.bone_idx = i
		skeleton.add_child(mount)
		mount.add_child(_cross())


func _cross() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.05, 0.04, 0.04)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for angle in [45.0, -45.0]:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(eye_mark_size, eye_mark_size * 0.22, eye_mark_size * 0.22)
		bar.mesh = box
		bar.material_override = mat
		bar.rotation.z = deg_to_rad(angle)
		root.add_child(bar)
	return root
