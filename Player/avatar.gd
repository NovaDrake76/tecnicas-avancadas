class_name Avatar
extends Node3D

## what your teammate looks like from the outside.
##
## the player has never had a body: it is a capsule, a camera and a weapon hanging off it, which is
## all a first person game needs and none of what a second player needs. this is the body, and it is
## built from primitives for the same reason the alarm horn and the gunship are -- the pack's human
## mesh is a T-pose with the arms straight out, and a static T-pose sliding across a field is worse
## than no character at all.
##
## it is deliberately plain: a dark figure with a plate carrier and a cap. two ghost operatives on a
## night job are not meant to be read as individuals, they are meant to be read as NOT KIWIS at a
## glance and at distance, which is the one thing a co-op stealth game needs from a silhouette.

const KIT := Color(0.16, 0.19, 0.16)
const PLATE := Color(0.10, 0.12, 0.11)
const SKIN := Color(0.62, 0.48, 0.38)
## the same green the laser kiwi's trim uses, so friend and enemy are told apart by SHAPE and the
## colour is only the accent. a second player is a person, and every kiwi is a bird.
const BAND := Color(0.35, 0.85, 0.45)

## the legs swing with the ground covered rather than with a timer, the same rule the footsteps use,
## so a walking figure and its own footsteps keep step at any speed.
const STRIDE := 1.1
const SWING_DEG := 28.0

var _body: Node3D
var _legs: Array[Node3D] = []
var _last := Vector3.INF
var _walked := 0.0
var _tag: Label3D


func _ready() -> void:
	add_to_group("avatar")
	_build()


## the name over the head. it is not decoration: in a stealth game where both players wear the same
## black kit, the tag is how you know the shape by the container is your friend before you shoot it.
func set_tag(text: String) -> void:
	if _tag != null:
		_tag.text = text


func _build() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	## the proportions are a person's, and they are the whole of whether this reads as one: shoulders
	## about a quarter of the height across, legs a little under half of it, head a seventh. the
	## first pass was narrow enough to read as a post with a hat on.
	_box(_body, Vector3(0.52, 0.62, 0.30), Vector3(0.0, 1.16, 0.0), KIT)
	_box(_body, Vector3(0.56, 0.36, 0.34), Vector3(0.0, 1.22, 0.0), PLATE)
	_box(_body, Vector3(0.24, 0.26, 0.24), Vector3(0.0, 1.60, 0.0), SKIN)
	## the cap, which is most of what says "person" on a low figure at fifty metres.
	_box(_body, Vector3(0.28, 0.09, 0.30), Vector3(0.0, 1.74, -0.02), KIT)
	## a band on the shoulders so a teammate reads at a glance in the dark.
	_box(_body, Vector3(0.58, 0.06, 0.32), Vector3(0.0, 1.44, 0.0), BAND)
	## arms, held forward and in, which is what a person carrying a weapon looks like from behind.
	_box(_body, Vector3(0.14, 0.46, 0.16), Vector3(-0.31, 1.20, -0.10), KIT)
	_box(_body, Vector3(0.14, 0.46, 0.16), Vector3(0.31, 1.20, -0.10), KIT)

	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.14 * side, 0.86, 0.0)
		_body.add_child(hip)
		_box(hip, Vector3(0.19, 0.86, 0.22), Vector3(0.0, -0.43, 0.0), PLATE)
		_legs.append(hip)

	_tag = Label3D.new()
	_tag.text = ""
	_tag.position = Vector3(0.0, 1.98, 0.0)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = false
	_tag.pixel_size = 0.004
	_tag.modulate = BAND
	_tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	_tag.outline_size = 10
	add_child(_tag)


## face down in the grass. an operative who is out is not gone: their teammate has to be able to
## find them, and a figure lying where they fell is the only thing that says where that was.
func lie(down: bool) -> void:
	if _body == null:
		return
	_body.rotation.x = deg_to_rad(-88.0) if down else 0.0
	_body.position.y = 0.15 if down else 0.0
	if _tag != null:
		_tag.modulate = Color(1.0, 0.45, 0.35) if down else BAND
		_tag.position.y = 1.1 if down else 2.05


func _box(parent: Node3D, size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.9
	mesh.material_override = mat
	parent.add_child(mesh)
	return mesh


## the walk. it reads the parent's own movement rather than being told about it, because the parent
## is a remote operative whose position arrives over the wire and whose velocity does not: how far it
## MOVED since the last frame is the only honest thing to swing the legs by, and it is exactly what
## the footsteps already measure.
func _process(delta: float) -> void:
	## the crouch comes free: the head's height is already on the wire because the aim needs it, and
	## how low the head is IS how crouched the operative is. squashing the body to it costs nothing
	## and means a teammate sneaking looks like a teammate sneaking.
	var head := get_parent().get_node_or_null("Head") as Node3D
	if head != null and _body != null:
		_body.scale.y = clampf(head.position.y / 1.65, 0.62, 1.0)
	var here := global_position
	if _last == Vector3.INF:
		_last = here
		return
	var moved := Vector2(here.x - _last.x, here.z - _last.z).length()
	_last = here
	var speed := moved / maxf(delta, 0.0001)
	if speed < 0.4:
		_walked = move_toward(_walked, 0.0, delta * 4.0)
	else:
		_walked += moved
	var swing := sin(_walked / STRIDE * TAU) * deg_to_rad(SWING_DEG) * clampf(speed / 6.0, 0.0, 1.0)
	for i in _legs.size():
		_legs[i].rotation.x = swing if i == 0 else -swing
