class_name BodyDrag
extends Node


signal grabbed(body: Node3D)
signal dropped(body: Node3D)

## where it sits in the view, in CAMERA space: left, a little down, and far enough forward to clear the near plane.
@export var carry_offset := Vector3(-0.74, -0.74, -1.26)
const CARRY_BASIS := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
## a nudge on top, for taste only.
@export var carry_tilt := Vector3(0.0, 0.0, 0.0)
## a body picked up snaps to the hand over this rather than teleporting, which reads as picking a thing up instead of a...
@export var raise_time := 0.18
@export_group("Throw")
## letting go THROWS the bird rather than setting it down at the player's feet.
@export var throw_speed := 6.5
@export var throw_lift := 3.0
@export var throw_spin := 6.0

var _player: CharacterBody3D
var _body: Node3D
var _just_dropped := false
var _raise := 0.0
var _from := Transform3D.IDENTITY


func _ready() -> void:
	add_to_group("body_drag")
	_player = get_parent() as CharacterBody3D


func _pass() -> ViewmodelPass:
	return get_tree().get_first_node_in_group("viewmodel_pass") as ViewmodelPass


func carry_mask() -> int:
	var p := _pass()
	return p.mask() if p != null else 0


func is_carrying() -> bool:
	return _body != null and is_instance_valid(_body)


func carried() -> Node3D:
	return _body if is_carrying() else null


func speed_mult() -> float:
	return 1.0


func grab(body: Node3D) -> bool:
	if _player == null or _just_dropped or is_carrying():
		return false
	if body == null or not is_instance_valid(body):
		return false
	if body.has_method("is_down") and not body.is_down():
		return false
	_body = body
	_raise = 0.0
	_from = _body.global_transform
	if _body.has_method("net_carried"):
		_body.net_carried.rpc(multiplayer.get_unique_id())
	elif _body.has_method("set_dragged"):
		_body.set_dragged(true)
	var p := _pass()
	if p != null:
		p.take_over(_body)
	Sfx.play_2d(&"body_grab")
	grabbed.emit(_body)
	return true


func drop() -> void:
	if not is_carrying():
		return
	var was := _body
	var p := _pass()
	if p != null:
		p.hand_back(was)
	if was.has_method("net_carried"):
		was.net_carried.rpc(0)
	elif was.has_method("set_dragged"):
		was.set_dragged(false)
	_body = null
	_just_dropped = true
	_throw(was)
	dropped.emit(was)


func _unhandled_input(event: InputEvent) -> void:
	if not is_carrying():
		return
	if event.is_action_pressed("interact"):
		drop()
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	_just_dropped = false


func _process(delta: float) -> void:
	if _body != null and not is_instance_valid(_body):
		_body = null
		var gone := _pass()
		if gone != null:
			gone.forget_freed()
		return
	if _body == null or _player == null:
		return
	var cam := _player.get_viewport().get_camera_3d()
	if cam == null:
		return
	var want := cam.global_transform * Transform3D(
		Basis.from_euler(Vector3(
			deg_to_rad(carry_tilt.x),
			deg_to_rad(carry_tilt.y),
			deg_to_rad(carry_tilt.z))) * CARRY_BASIS,
		carry_offset)
	if _raise < 1.0:
		_raise = minf(_raise + delta / maxf(raise_time, 0.001), 1.0)
		_body.global_transform = _from.interpolate_with(want, _raise)
	else:
		_body.global_transform = want


func _throw(body: Node3D) -> void:
	if _player == null or body == null or not is_instance_valid(body):
		return
	var cam := _player.get_viewport().get_camera_3d()
	var aim := -_player.global_transform.basis.z
	if cam != null:
		aim = -cam.global_transform.basis.z
	var toss := aim * throw_speed + Vector3.UP * throw_lift
	toss += Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	if body.has_method("toss"):
		body.toss.rpc(toss, throw_spin)
	else:
		body.global_position += aim * 0.6
