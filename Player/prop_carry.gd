class_name PropCarry
extends Node


signal grabbed(prop: Node3D)
signal thrown(prop: Node3D, at: Vector3)

## where it rides, in CAMERA space: the left hand, low, far enough forward to clear the near plane.
@export var hold_offset := Vector3(-0.46, -0.4, -1.0)
@export var hold_tilt := Vector3(-12.0, 22.0, 6.0)
## it swings up to the hand over this rather than teleporting into it.
@export var raise_time := 0.16
@export_group("Throw")
@export var throw_speed := 11.0
@export var throw_lift := 2.4
@export var throw_spin := 7.0
## a throw is worth a grunt of effort; the noise that matters is where it LANDS.
@export var throw_cue := &"throw"

var _player: CharacterBody3D
var _prop: LooseProp
var _raise := 0.0
var _from := Transform3D.IDENTITY
var _just_dropped := false


func _ready() -> void:
	add_to_group("prop_carry")
	_player = get_parent() as CharacterBody3D


static func hands_of(tree: SceneTree, peer: int) -> PropCarry:
	for node in tree.get_nodes_in_group("player"):
		if String((node as Node).name).to_int() == peer:
			return (node as Node).get_node_or_null("PropCarry") as PropCarry
	return null


func is_carrying() -> bool:
	return _prop != null and is_instance_valid(_prop)


func carried() -> LooseProp:
	return _prop if is_carrying() else null


func holder() -> Node3D:
	return _player


## the local operative asks for it; every machine is told, so the same prop rides the same hands
## everywhere and each works the pose out from that player's own head instead of being sent it.
func grab(prop: LooseProp) -> bool:
	if _player == null or _just_dropped or is_carrying():
		return false
	if prop == null or not is_instance_valid(prop) or not prop.can_carry() or prop.is_carried():
		return false
	if _dragging_a_body():
		return false
	prop.net_held.rpc(_peer())
	Sfx.play_2d(&"body_grab")
	return true


func throw() -> void:
	if not is_carrying():
		return
	var prop := _prop
	var aim := _aim()
	var toss := aim * throw_speed + Vector3.UP * throw_lift
	toss += Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * throw_spin
	var from := prop.global_position
	_just_dropped = true
	prop.net_toss.rpc(from, toss * prop.mass, spin)
	if throw_cue != &"":
		Sfx.play_2d(throw_cue)
	thrown.emit(prop, from)


## called by the prop on every machine once the wire has said who is holding it.
func hold(prop: LooseProp) -> void:
	if is_carrying() and _prop != prop:
		release()
	_prop = prop
	_raise = 0.0
	_from = prop.global_transform
	var pass_node := _pass()
	if pass_node != null and _is_local():
		pass_node.take_over(prop)
	grabbed.emit(prop)


func release() -> void:
	if not is_carrying():
		return
	var was := _prop
	var pass_node := _pass()
	if pass_node != null:
		pass_node.hand_back(was)
	_prop = null


func _peer() -> int:
	return String(_player.name).to_int() if _player != null else 1


func _is_local() -> bool:
	return _player != null and _player.has_method("is_local") and _player.is_local()


func _pass() -> ViewmodelPass:
	return get_tree().get_first_node_in_group("viewmodel_pass") as ViewmodelPass


func _dragging_a_body() -> bool:
	var drag := _player.get_node_or_null("BodyDrag") as BodyDrag if _player != null else null
	return drag != null and drag.is_carrying()


## the local operative's eyes are the camera; a remote one's are its head, which is synchronised
## already, so nothing about a carried prop has to cross the wire per frame.
func _eyes() -> Transform3D:
	if _is_local():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			return cam.global_transform
	var head := _player.get_node_or_null("Head") as Node3D if _player != null else null
	return head.global_transform if head != null else _player.global_transform


func _aim() -> Vector3:
	return -_eyes().basis.z


func _unhandled_input(event: InputEvent) -> void:
	if not is_carrying() or not _is_local():
		return
	if event.is_action_pressed("interact"):
		throw()
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	_just_dropped = false


func _process(delta: float) -> void:
	if _prop != null and not is_instance_valid(_prop):
		_prop = null
		var gone := _pass()
		if gone != null:
			gone.forget_freed()
		return
	if _prop == null or _player == null:
		return
	var want := _eyes() * Transform3D(Basis.from_euler(Vector3(
		deg_to_rad(hold_tilt.x), deg_to_rad(hold_tilt.y), deg_to_rad(hold_tilt.z))), hold_offset)
	if _raise < 1.0:
		_raise = minf(_raise + delta / maxf(raise_time, 0.001), 1.0)
		_prop.global_transform = _from.interpolate_with(want, _raise)
	else:
		_prop.global_transform = want
