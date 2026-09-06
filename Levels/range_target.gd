class_name RangeTarget
extends StaticBody3D


signal hit(count: int)

@export var distance_label := ""
@export var width := 0.5
@export var height := 0.9
@export var down_time := 1.4
@export var colour := Color(0.82, 0.72, 0.5)

var hits := 0
var _down := false
var _board: MeshInstance3D
var _head: MeshInstance3D
var _chest: MeshInstance3D
var _label: Label3D
var _tween: Tween


func _ready() -> void:
	add_to_group("range_target")
	collision_layer = 8
	collision_mask = 0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, 0.03)
	_board = MeshInstance3D.new()
	_board.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.95
	_board.material_override = mat
	_board.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(_board)
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.15, 0.12, 0.1)
	_head = MeshInstance3D.new()
	var head := _head
	var disc := CylinderMesh.new()
	disc.top_radius = width * 0.16
	disc.bottom_radius = width * 0.16
	disc.height = 0.005
	head.mesh = disc
	head.rotation_degrees.x = 90.0
	head.position = Vector3(0.0, height * 0.30, 0.02)
	head.material_override = ink
	_board.add_child(head)
	_chest = MeshInstance3D.new()
	var chest := _chest
	var bar := BoxMesh.new()
	bar.size = Vector3(width * 0.52, height * 0.38, 0.005)
	chest.mesh = bar
	chest.position = Vector3(0.0, -height * 0.02, 0.02)
	chest.material_override = ink
	_board.add_child(chest)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.06)
	shape.shape = box
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(shape)

	_label = Label3D.new()
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.position = Vector3(0.0, height + 0.34, 0.06)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.outline_size = 8
	add_child(_label)
	_refresh_label()


func aim_point(part: String) -> Vector3:
	match part:
		"head":
			return _head.global_position
		"chest":
			return _chest.global_position
	return _board.global_position


func take_bb_hit(_damage := 1.0, at := Vector3.INF, _energy := -1.0) -> void:
	hits += 1
	hit.emit(hits)
	Sfx.play(&"target_hit", at if at.is_finite() else global_position)
	_refresh_label()
	if _down:
		return
	_down = true
	Sfx.play(&"target_fall", global_position)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_board, "rotation_degrees:x", -85.0, 0.12).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(down_time)
	_tween.tween_callback(func() -> void: Sfx.play(&"target_rise", global_position))
	_tween.tween_property(_board, "rotation_degrees:x", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(func() -> void: _down = false)


func _refresh_label() -> void:
	_label.text = "%s\n%d hits" % [distance_label, hits] if hits > 0 else distance_label
