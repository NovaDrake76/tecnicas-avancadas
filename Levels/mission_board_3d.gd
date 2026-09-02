extends StaticBody3D

## the board on the armory wall: a dark plate with the mission pictures pinned to it, built at runtime
## from Run.LEVELS so a new mission shows up here without touching the scene. nothing is owned, so the
## level file stays small. interacting opens the mission screen.

@export var width := 1.8
@export var height := 1.1
@export var photo_width := 0.46

var _built := false


func _ready() -> void:
	add_to_group("mission_board_3d")
	collision_layer = 1
	if not _built:
		_build()


func _build() -> void:
	_built = true
	var plate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, 0.04)
	plate.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.16, 0.12)
	mat.roughness = 0.95
	plate.material_override = mat
	add_child(plate)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, height, 0.08)
	shape.shape = bs
	add_child(shape)

	var n := Run.level_count()
	var photo_h := photo_width * 9.0 / 16.0
	var gap := (width - n * photo_width) / float(n + 1)
	for i in n:
		var entry: Dictionary = Run.LEVELS[i]
		var path := String(entry.get("image", ""))
		var quad := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(photo_width, photo_h)
		quad.mesh = q
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if path != "" and ResourceLoader.exists(path):
			pm.albedo_texture = load(path)
		else:
			pm.albedo_color = Color(0.3, 0.32, 0.3)
		quad.material_override = pm
		quad.position = Vector3(-width * 0.5 + gap + photo_width * 0.5 + i * (photo_width + gap), 0.08, 0.025)
		add_child(quad)
		## a pin
		var pin := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.012
		s.height = 0.024
		pin.mesh = s
		var pin_mat := StandardMaterial3D.new()
		pin_mat.albedo_color = Color(0.86, 0.3, 0.22)
		pin.material_override = pin_mat
		pin.position = quad.position + Vector3(0.0, photo_h * 0.5 + 0.005, 0.01)
		add_child(pin)
