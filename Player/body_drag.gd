class_name BodyDrag
extends Node

## a downed kiwi stays where it fell, so where it fell is a decision. this is the answer to it: look
## at a body, press interact, and the player picks it up and CARRIES it, held out to the left of the
## view, until it is somewhere nobody looks. press again to let go.
##
## it is carried rather than dragged along the floor because a kiwi weighs almost nothing and hauling
## one should not feel like moving furniture: there is no speed penalty at all. the cost is the two
## seconds at either end and the fact that you are holding a corpse in front of your own face.
##
## there is no hiding PLACE and there does not need to be one. a bird finds a body by casting a ray
## at it, so a crate, a container or the far side of a hill hides one for free, and the level's own
## cover is the vocabulary. anything that blocks a sight line blocks this.

signal grabbed(body: Node3D)
signal dropped(body: Node3D)

## where it sits in the view, in CAMERA space: left, a little down, and far enough forward to clear
## the near plane. it is parked on the camera rather than in the world for the same reason the
## weapon is: what the player is holding should not swim about when they turn.
@export var carry_offset := Vector3(-0.74, -0.74, -1.26)
## how it is turned in the hand, built from NAMED AXES rather than from three euler numbers: what is
## being asked for is "head up, face to the camera, like a totem", and a row of angles says none of
## that and cannot be reasoned about when it comes out wrong. the bird's forward is -Z and its up is
## +Y, so this is its own up left alone and its forward turned back at the player.
const CARRY_BASIS := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
## a nudge on top, for taste only.
@export var carry_tilt := Vector3(0.0, 0.0, 0.0)
## a body picked up snaps to the hand over this rather than teleporting, which reads as picking a
## thing up instead of a thing appearing.
@export var raise_time := 0.18
@export_group("Throw")
## letting go THROWS the bird rather than setting it down at the player's feet. a body that appears
## on the ground under you reads as the game tidying up; one that arcs out of your hands and lands
## reads as you having put it somewhere, which is the whole decision the carry exists for.
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


## the shared pass that draws everything the player is holding, weapon and corpse alike.
func _pass() -> ViewmodelPass:
	return get_tree().get_first_node_in_group("viewmodel_pass") as ViewmodelPass


## the render layer the carried body lives on while it is held, 0 if the pass never came up.
func carry_mask() -> int:
	var p := _pass()
	return p.mask() if p != null else 0


func is_carrying() -> bool:
	return _body != null and is_instance_valid(_body)


func carried() -> Node3D:
	return _body if is_carrying() else null


## a kiwi is a small bird and carrying one costs the player NO speed. it used to cost 45 percent,
## which made every body a haul and quietly discouraged the tidiest thing a player can do; the price
## of moving a body is the time at both ends, not a limp.
func speed_mult() -> float:
	return 1.0


## called by the body's own Interactable. it refuses a second body rather than swapping, so a press
## that lands on the frame a body was dropped cannot pick it straight back up.
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
	## every machine is told who is carrying it, which is what moves the right to say where it is
	## onto the machine doing the carrying.
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


## one tick's grace after a drop. without it the same press that lets go can be read by the body's
## own handle as a press to pick it straight back up.
func _physics_process(_delta: float) -> void:
	_just_dropped = false


func _process(delta: float) -> void:
	## the body can be freed under us by a level change or a probe, and a freed node compares equal
	## to null, so the carry is dropped by the same check that reads it. the pass is told as well, or
	## it keeps rendering a second view for a corpse that no longer exists.
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



## out of the hands and away. the bird flies on its own physics from here: Kiwi.toss takes the
## velocity and its DOWN state carries it until it lands, so nothing here has to simulate anything.
func _throw(body: Node3D) -> void:
	if _player == null or body == null or not is_instance_valid(body):
		return
	var cam := _player.get_viewport().get_camera_3d()
	var aim := -_player.global_transform.basis.z
	if cam != null:
		aim = -cam.global_transform.basis.z
	var toss := aim * throw_speed + Vector3.UP * throw_lift
	## the player's own motion goes into it, so throwing something while running actually throws it
	## further, which is what every hand expects.
	toss += Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	if body.has_method("toss"):
		## thrown on every machine from the same push, so the arc is the same everywhere and the
		## host's copy is the one whose landing counts.
		body.toss.rpc(toss, throw_spin)
	else:
		body.global_position += aim * 0.6
