class_name Avatar
extends Node3D


const KIT := Color(0.16, 0.19, 0.16)
const PLATE := Color(0.10, 0.12, 0.11)
const SKIN := Color(0.62, 0.48, 0.38)
const BAND := Color(0.35, 0.85, 0.45)

const STRIDE := 1.1
const SWING_DEG := 28.0
const BODY := false

var _body: Node3D
var _legs: Array[Node3D] = []
var _last := Vector3.INF
var _walked := 0.0
var _tag: Label3D


func _ready() -> void:
	add_to_group("avatar")
	_build()


func set_tag(text: String) -> void:
	if _tag != null:
		_tag.text = text


func _build() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	if BODY:
		_build_body()

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


func _build_body() -> void:
	_box(_body, Vector3(0.52, 0.62, 0.30), Vector3(0.0, 1.16, 0.0), KIT)
	_box(_body, Vector3(0.56, 0.36, 0.34), Vector3(0.0, 1.22, 0.0), PLATE)
	_box(_body, Vector3(0.24, 0.26, 0.24), Vector3(0.0, 1.60, 0.0), SKIN)
	_box(_body, Vector3(0.28, 0.09, 0.30), Vector3(0.0, 1.74, -0.02), KIT)
	_box(_body, Vector3(0.58, 0.06, 0.32), Vector3(0.0, 1.44, 0.0), BAND)
	_box(_body, Vector3(0.14, 0.46, 0.16), Vector3(-0.31, 1.20, -0.10), KIT)
	_box(_body, Vector3(0.14, 0.46, 0.16), Vector3(0.31, 1.20, -0.10), KIT)

	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.14 * side, 0.86, 0.0)
		_body.add_child(hip)
		_box(hip, Vector3(0.19, 0.86, 0.22), Vector3(0.0, -0.43, 0.0), PLATE)
		_legs.append(hip)


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


func _process(delta: float) -> void:
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
