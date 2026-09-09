class_name MenuReel
extends Node3D


signal cut(index: int)

const KIWI := "res://Models/kiwi.glb"
const PROPS := "res://Models/Props/"
const NATURE := "res://Models/Nature/"
const GRASS := preload("res://Shaders/terrain_grass.gdshader")
const FLAG := preload("res://Shaders/flag.gdshader")
const SCENES := ["march", "rally", "battle"]
const SPACING := 400.0
const TILE := 4.0
const STOREY := 3.0
const CLIP_WALK := "walk"
const CLIP_RUN := "run"
const CLIP_IDLE := ["IdleA", "IdleB", "IdleC", "IdleD"]
const MARCHERS := 30
const SPECTATORS := 26
const CROWD := 48
const SHOOTERS := 7
const RUNNERS := 6
const EMPIRE_RED := Color(0.62, 0.13, 0.10)
const ASPHALT := Color(0.16, 0.16, 0.17)
const CONCRETE := Color(0.46, 0.45, 0.42)
const EARTH := Color(0.26, 0.23, 0.18)
const ROOF := Color(0.13, 0.12, 0.12)

## seconds each scene plays before the cut to the next.
@export var period := 9.0
@export var march_speed := 1.05
## the road: a bird that walks off its far end comes back on at the near one.
@export var march_length := 60.0
@export var run_speed := 3.4
@export var tracer_speed := 70.0

var _cams: Array[Camera3D] = []
var _rests: Array[Transform3D] = []
var _marchers: Array[Node3D] = []
var _runners: Array[Dictionary] = []
var _shooters: Array[Dictionary] = []
var _enemy: Array[Dictionary] = []
var _tracers: Array[Dictionary] = []
var _fires: Array[Dictionary] = []
var _bursts: Array[Dictionary] = []
var _burst_clock := 3.0
var _index := 0
var _t := 0.0
var _cuts := 0
var _kiwi_scene: PackedScene
var _scenes := {}
var _roundel: ImageTexture
var _birds := 0


func _ready() -> void:
	_kiwi_scene = load(KIWI) as PackedScene
	_roundel = _make_roundel()
	_build_march(Vector3(0.0, 0.0, 0.0))
	_build_rally(Vector3(SPACING, 0.0, 0.0))
	_build_battle(Vector3(SPACING * 2.0, 0.0, 0.0))
	_cams[0].make_current()


func _process(delta: float) -> void:
	_t += delta
	if _t >= period:
		_t = 0.0
		_index = (_index + 1) % _cams.size()
		_cams[_index].make_current()
		_cuts += 1
		cut.emit(_index)
	_step_march(delta)
	_step_battle(delta)
	_move_camera()


func _move_camera() -> void:
	var cam := _cams[_index]
	var rest := _rests[_index]
	match _index:
		0:
			cam.transform = rest.translated(Vector3(0.0, 0.0, 0.14) * _t)
		1:
			cam.transform = rest.translated(Vector3(0.0, -0.015, -0.2) * _t)
		2:
			var shake := Vector2(sin(_t * 11.3) * 0.006 + sin(_t * 4.1) * 0.004, cos(_t * 9.7) * 0.005)
			cam.transform = rest
			cam.rotate_object_local(Vector3.RIGHT, shake.y)
			cam.rotate_y(shake.x)
			cam.position += Vector3(0.0, 0.0, 0.05) * _t


## ---------------------------------------------------------------- pieces
func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path] as PackedScene


func _glb(path: String) -> Node3D:
	var scene := _scene(PROPS + path)
	return scene.instantiate() as Node3D if scene != null else Node3D.new()


func _nature(path: String) -> Node3D:
	var scene := _scene(NATURE + path)
	return scene.instantiate() as Node3D if scene != null else Node3D.new()


func _place(parent: Node, node: Node3D, at: Vector3, yaw := 0.0) -> Node3D:
	node.position = at
	node.rotation.y = deg_to_rad(yaw)
	parent.add_child(node)
	return node


## the kiwi glb faces +z at yaw 0, the opposite of godot's forward; every yaw here is written against that.
static func yaw_toward(dir: Vector3) -> float:
	return rad_to_deg(atan2(dir.x, dir.z))


func _bird(parent: Node, at: Vector3, yaw: float, clip: String, offset := 0.0) -> Node3D:
	var kiwi := _kiwi_scene.instantiate() as Node3D
	Kiwi.enable_vertex_colors(kiwi)
	_place(parent, kiwi, at, yaw)
	_birds += 1
	var anim := kiwi.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim != null:
		for clip_name in anim.get_animation_list():
			if String(clip_name).ends_with("|" + clip):
				anim.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
				anim.play(clip_name)
				anim.seek(offset, true)
				break
	return kiwi


func _flat_mat(colour: Color, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	return m


func _box(parent: Node, at: Vector3, size: Vector3, colour: Color, yaw := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _flat_mat(colour)
	_place(parent, mesh, at, yaw)
	return mesh


func _ground(parent: Node, origin: Vector3, size: float, colour: Color) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mesh.mesh = plane
	mesh.material_override = _flat_mat(colour)
	_place(parent, mesh, origin + Vector3(0.0, -0.03, 0.0))


func _grass(parent: Node, origin: Vector3, size := 300.0) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mesh.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = GRASS
	mesh.material_override = mat
	_place(parent, mesh, origin)


func _floor(parent: Node, origin: Vector3, cols: int, rows: int, tile := "Kit/floor_ceiling_hr_3") -> void:
	for i in cols:
		for j in rows:
			var x := origin.x + (float(i) - float(cols - 1) * 0.5) * TILE
			var z := origin.z + (float(j) - float(rows - 1) * 0.5) * TILE
			_place(parent, _glb(tile + ".glb"), Vector3(x, -0.4, z))


## a ring of forest round a point, the level kit's own scatter, with nothing in the middle of it.
func _forest(parent: Node, at: Vector3, ring := 0.4, seed_no := 3, trees := 220, ferns := 90, grass := 240, rocks := 20) -> void:
	var f := Foliage.new()
	f.scatter_seed = seed_no
	f.ring_scale = ring
	f.tree_count = trees
	f.fern_count = ferns
	f.range_grass_count = 0
	f.grass_count = grass
	f.rock_count = rocks
	f.debris_count = rocks
	f.tree_collision = false
	f.rock_collision = false
	_place(parent, f, at)


func _tree(parent: Node, at: Vector3, kind := "tree_pine_a", scale_by := 1.0, yaw := 0.0) -> void:
	var t := _nature(kind + ".glb")
	t.scale = Vector3.ONE * scale_by
	_place(parent, t, at, yaw)


## a building of the kit's walls: front on +z, `wide` modules across, `deep` along, `storeys` high,
## a roof slab on top; the ground floor may hold a doorway and the front a banner.
func _block(parent: Node, at: Vector3, wide: int, deep: int, storeys: int, yaw := 0.0, door := -1, banner := false) -> Node3D:
	var root := Node3D.new()
	_place(parent, root, at, yaw)
	var w := float(wide) * TILE
	var d := float(deep) * TILE
	for s in storeys:
		var y := float(s) * STOREY
		for i in wide:
			var x := (float(i) - float(wide - 1) * 0.5) * TILE
			var piece := "Walls/wall_hr_1.glb" if (i + s) % 3 != 1 else "Walls/wall_hr_2.glb"
			if s == 0 and i == door:
				piece = "Kit/doorway_hr_2_wide.glb"
			_place(root, _glb(piece), Vector3(x, y, d * 0.5))
			_place(root, _glb("Walls/wall_hr_1.glb"), Vector3(x, y, -d * 0.5))
		for j in deep:
			var z := (float(j) - float(deep - 1) * 0.5) * TILE
			_place(root, _glb("Walls/wall_hr_1.glb"), Vector3(-w * 0.5, y, z), 90.0)
			_place(root, _glb("Walls/wall_hr_2.glb" if j % 2 == 0 else "Walls/wall_hr_1.glb"), Vector3(w * 0.5, y, z), 90.0)
	_box(root, Vector3(0.0, float(storeys) * STOREY + 0.15, 0.0), Vector3(w + 0.5, 0.3, d + 0.5), ROOF)
	if banner:
		_banner(root, Vector3(0.0, float(storeys) * STOREY - 1.7, d * 0.5 + 0.22), 0.0, Vector2(2.6, 1.6))
	return root


func _camera(at: Vector3, look: Vector3, fov: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = "Camera%d" % (_cams.size() + 1)
	cam.fov = fov
	cam.far = 600.0
	cam.position = at
	add_child(cam)
	cam.look_at(look)
	_cams.append(cam)
	_rests.append(cam.transform)
	return cam


func _make_roundel() -> ImageTexture:
	var w := 192
	var h := 120
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(EMPIRE_RED)
	var c := Vector2(w * 0.5, h * 0.5)
	for y in h:
		for x in w:
			var dist := Vector2(x, y).distance_to(c)
			if dist < 22.0:
				img.set_pixel(x, y, Color(0.06, 0.05, 0.05))
			elif dist < 36.0:
				img.set_pixel(x, y, Color(0.93, 0.9, 0.84))
	for y in range(h - 8, h):
		for x in w:
			img.set_pixel(x, y, Color(0.06, 0.05, 0.05))
	return ImageTexture.create_from_image(img)


func _banner(parent: Node, at: Vector3, yaw: float, size: Vector2) -> void:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _roundel
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	_place(parent, mesh, at, yaw)


## the cloth hangs toward +x of the flag; `yaw` turns the whole flag, so a flag by a wall hangs away from it.
func _flag(parent: Node, at: Vector3, height := 4.2, yaw := 0.0) -> void:
	var root := Node3D.new()
	_place(parent, root, at, yaw)
	at = Vector3.ZERO
	parent = root
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.04
	cyl.height = height
	pole.mesh = cyl
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.56, 0.58)
	steel.metallic = 0.6
	pole.material_override = steel
	_place(parent, pole, at + Vector3(0.0, height * 0.5, 0.0))
	var cloth := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Z
	plane.size = Vector2(1.7, 1.05)
	plane.subdivide_width = 24
	plane.subdivide_depth = 12
	cloth.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = FLAG
	mat.set_shader_parameter("cloth", _roundel)
	cloth.material_override = mat
	_place(parent, cloth, at + Vector3(0.85, height - 0.6, 0.0))


## ---------------------------------------------------------------- the march
func _build_march(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "March"
	add_child(root)
	_ground(root, origin, 400.0, EARTH)
	var road_len := 150.0
	_box(root, origin, Vector3(8.0, 0.06, road_len), ASPHALT)
	for side in [-1.0, 1.0]:
		_box(root, origin + Vector3(side * 5.75, 0.06, 0.0), Vector3(3.5, 0.16, road_len), CONCRETE)
	var z := -road_len * 0.5 + 2.0
	while z < road_len * 0.5:
		_box(root, origin + Vector3(0.0, 0.035, z), Vector3(0.14, 0.012, 2.2), Color(0.8, 0.78, 0.7))
		z += 6.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for side in [-1.0, 1.0]:
		var cursor := -70.0
		var n := 0
		while cursor < 70.0:
			var wide := 2 + rng.randi_range(0, 2)
			var deep := 2
			var storeys := 2 + rng.randi_range(0, 2)
			var w := float(wide) * TILE
			var x: float = side * (7.6 + float(deep) * TILE * 0.5)
			var door := rng.randi_range(0, wide - 1) if rng.randf() < 0.6 else -1
			_block(root, origin + Vector3(x, 0.0, cursor + w * 0.5), wide, deep, storeys, -side * 90.0, door, n % 3 == 1)
			cursor += w + 2.0
			n += 1
	for k in 9:
		var fz := -64.0 + float(k) * 16.0
		_flag(root, origin + Vector3(-6.9, 0.14, fz), 4.6)
		_flag(root, origin + Vector3(6.9, 0.14, fz + 8.0), 4.6, 180.0)
	for k in 6:
		var pz := -60.0 + float(k) * 24.0
		_place(root, _glb("Barrels/metal_barrel_hr_1.glb"), origin + Vector3(-6.2, 0.14, pz), rng.randf_range(0.0, 90.0))
		_place(root, _glb("Containers/wooden_crate_1.glb"), origin + Vector3(6.3, 0.14, pz + 11.0), rng.randf_range(0.0, 90.0))
	for i in SPECTATORS:
		var side := -1.0 if i % 2 == 0 else 1.0
		var sz := -30.0 + float(i) * 2.4 + rng.randf_range(-0.6, 0.6)
		var sx := side * (4.6 + rng.randf_range(0.0, 1.6))
		_bird(root, origin + Vector3(sx, 0.13, sz), -side * 90.0 + rng.randf_range(-20.0, 20.0), CLIP_IDLE[i % CLIP_IDLE.size()], rng.randf_range(0.0, 2.0))
	for i in MARCHERS:
		var lane := (float(i % 3) - 1.0) * 1.3
		@warning_ignore("integer_division")
		var mz := origin.z - march_length * 0.5 + 1.0 + float(i / 3) * 1.9
		_marchers.append(_bird(root, Vector3(origin.x + lane, 0.0, mz), 0.0, CLIP_WALK, float(i % 3) * 0.25))
	_forest(root, origin + Vector3(0.0, 0.0, 122.0), 0.5, 21, 260, 0, 0, 0)
	_forest(root, origin + Vector3(0.0, 0.0, -122.0), 0.5, 22, 260, 0, 0, 0)
	_camera(origin + Vector3(5.9, 0.62, -12.0), origin + Vector3(-1.2, 0.5, 6.0), 50.0)


func _step_march(delta: float) -> void:
	for bird in _marchers:
		bird.position.z += march_speed * delta
		if bird.position.z > march_length * 0.5:
			bird.position.z -= march_length


## ---------------------------------------------------------------- the rally
func _build_rally(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Rally"
	add_child(root)
	_ground(root, origin, 400.0, EARTH)
	_floor(root, origin, 10, 10, "Kit/floor_ceiling_hr_4")
	_block(root, origin + Vector3(-12.0, 0.0, -24.0), 4, 2, 3, 0.0, 1, true)
	_block(root, origin + Vector3(4.0, 0.0, -24.0), 4, 2, 4, 0.0, -1, true)
	_block(root, origin + Vector3(20.0, 0.0, -24.0), 4, 2, 2, 0.0, 0, false)
	_block(root, origin + Vector3(-28.0, 0.0, -24.0), 4, 2, 2, 0.0, -1, false)
	_block(root, origin + Vector3(-26.0, 0.0, -6.0), 2, 3, 3, 90.0, 1, true)
	_block(root, origin + Vector3(-26.0, 0.0, 12.0), 2, 2, 2, 90.0, -1, false)
	_block(root, origin + Vector3(26.0, 0.0, -4.0), 2, 3, 3, -90.0, 0, true)
	_block(root, origin + Vector3(26.0, 0.0, 12.0), 2, 2, 4, -90.0, -1, false)
	for x in [-6.0, 0.0, 6.0]:
		_banner(root, origin + Vector3(x, 2.4, -12.5), 0.0, Vector2(2.6, 1.6))
	_box(root, origin + Vector3(0.0, 0.5, -12.6), Vector3(16.0, 1.0, 0.4), CONCRETE)
	var podium := _place(root, _glb("Kit/table_large_2.glb"), origin + Vector3(0.0, 0.0, -8.5))
	_place(root, _glb("Kit/table_large_2.glb"), origin + Vector3(-2.2, 0.0, -8.5))
	_place(root, _glb("Kit/table_large_2.glb"), origin + Vector3(2.2, 0.0, -8.5))
	_place(root, _glb("Kit/speaker_mx_1.glb"), origin + Vector3(-5.2, 0.0, -9.0), 20.0)
	_place(root, _glb("Kit/speaker_mx_1.glb"), origin + Vector3(5.2, 0.0, -9.0), -20.0)
	var top := 0.8
	for m in podium.find_children("*", "MeshInstance3D", true, false):
		top = maxf(top, (m as MeshInstance3D).get_aabb().end.y)
	_bird(root, origin + Vector3(0.0, top, -8.5), 0.0, "IdleB")
	for x in [-5.0, -2.5, 2.5, 5.0]:
		_flag(root, origin + Vector3(x, 0.0, -11.5))
	for x in [-14.0, 14.0]:
		_flag(root, origin + Vector3(x, 0.0, 4.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in CROWD:
		@warning_ignore("integer_division")
		var row := i / 8
		var col := i % 8
		var at := origin + Vector3((float(col) - 3.5) * 1.6 + rng.randf_range(-0.4, 0.4), 0.0,
			-4.0 + float(row) * 1.7 + rng.randf_range(-0.3, 0.3))
		_bird(root, at, 180.0 + rng.randf_range(-14.0, 14.0), CLIP_IDLE[i % CLIP_IDLE.size()], rng.randf_range(0.0, 2.0))
	_forest(root, origin + Vector3(0.0, 0.0, -86.0), 0.27, 31, 200, 0, 0, 0)
	_camera(origin + Vector3(1.6, 1.4, 9.5), origin + Vector3(0.0, 1.2, -8.5), 46.0)


## ---------------------------------------------------------------- the battle
func _build_battle(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Battle"
	add_child(root)
	_grass(root, origin)
	_place(root, _glb("Barricades/barricade_b_1.glb"), origin + Vector3(0.0, 0.0, 0.0), 0.0)
	_place(root, _glb("Containers/shipping_container_mx_1.glb"), origin + Vector3(-11.0, 0.0, 6.0), 12.0)
	_place(root, _glb("Containers/supply_crate_1.glb"), origin + Vector3(8.5, 0.0, 4.0), -30.0)
	_place(root, _glb("Containers/wooden_crate_2_a.glb"), origin + Vector3(9.5, 0.0, 1.5), 10.0)
	_place(root, _glb("Barrels/metal_barrel_hr_1.glb"), origin + Vector3(9.6, 0.0, 2.9), 0.0)
	_place(root, _glb("Barricades/barricade_a_1.glb"), origin + Vector3(-9.5, 0.0, 2.5), 25.0)
	_place(root, _glb("Barricades/barricade_a_2.glb"), origin + Vector3(11.0, 0.0, 3.0), -20.0)
	_place(root, _glb("Clutter/cement_bags_mp_1_pallet_1.glb"), origin + Vector3(-4.0, 0.0, 4.5), 40.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in SHOOTERS:
		var x := (float(i) - 3.0) * 2.1 + (0.9 if i > 3 else -0.9)
		var bird := _bird(root, origin + Vector3(x, 0.0, 0.4 + float(i % 3) * 0.5), 180.0, CLIP_IDLE[i % 2], float(i) * 0.4)
		_arm(bird, 0.4 + float(i) * 0.35)
	for i in RUNNERS:
		var a: Vector3
		var b: Vector3
		if i % 2 == 0:
			a = origin + Vector3(rng.randf_range(-12.0, 12.0), 0.0, 20.0)
			b = origin + Vector3(rng.randf_range(-12.0, 12.0), 0.0, -13.0)
		else:
			a = origin + Vector3(22.0, 0.0, rng.randf_range(3.5, 7.0))
			b = origin + Vector3(-22.0, 0.0, rng.randf_range(3.5, 7.0))
		var bird := _bird(root, a, 180.0, CLIP_RUN, rng.randf_range(0.0, 1.0))
		_runners.append({"node": bird, "a": a, "b": b, "t": rng.randf(), "across": i % 2 == 0})
	for i in 14:
		var tx := rng.randf_range(-26.0, 26.0)
		var tz := rng.randf_range(-16.0, -30.0)
		_tree(root, origin + Vector3(tx, 0.0, tz), ["tree_pine_a", "tree_pine_b", "tree_a"][i % 3], rng.randf_range(0.9, 1.5), rng.randf_range(0.0, 360.0))
	_forest(root, origin + Vector3(0.0, 0.0, -58.0), 0.25, 41, 320, 120)
	_forest(root, origin + Vector3(-70.0, 0.0, -40.0), 0.25, 42, 160, 60)
	_forest(root, origin + Vector3(70.0, 0.0, -40.0), 0.25, 43, 160, 60)
	for i in 5:
		var at := origin + Vector3(rng.randf_range(-18.0, 18.0), 0.5, rng.randf_range(-20.0, -32.0))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.55)
		light.light_energy = 0.0
		light.omni_range = 6.0
		_place(root, light, at)
		_enemy.append({"light": light, "at": at, "next": rng.randf_range(0.2, 1.5), "off": 0.0})
	_smoke(root, origin + Vector3(-5.0, 0.2, -18.0), 3.0)
	_smoke(root, origin + Vector3(9.0, 0.2, -24.0), 4.5)
	_fire(root, origin + Vector3(9.0, 0.6, -24.0))
	_fire(root, origin + Vector3(-14.0, 0.5, -26.0))
	for i in 3:
		_bursts.append({"node": _burst(root)})
	_camera(origin + Vector3(3.0, 1.0, 6.0), origin + Vector3(-1.0, 0.55, -9.0), 54.0)


func _arm(bird: Node3D, first: float) -> void:
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0.0, 0.42, 0.45)
	bird.add_child(muzzle)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.55)
	light.light_energy = 0.0
	light.omni_range = 4.0
	muzzle.add_child(light)
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	flash.mesh = quad
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.9, 0.6)
	flash.material_override = fm
	flash.visible = false
	muzzle.add_child(flash)
	_shooters.append({"muzzle": muzzle, "light": light, "flash": flash, "next": first, "off": 0.0})


func _smoke(parent: Node, at: Vector3, spread: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 7.0
	p.preprocess = 6.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.3, 1.0, 0.0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0.5, 0.35, 0.0)
	pm.scale_min = 1.4
	pm.scale_max = 2.6
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = spread * 0.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.22, 0.2, 0.19, 0.45))
	ramp.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	pm.color_ramp = tex
	p.process_material = pm
	p.draw_pass_1 = _puff(1.6)
	_place(parent, p, at)


func _puff(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var puff := GradientTexture2D.new()
	var soft := Gradient.new()
	soft.set_color(0, Color(1.0, 1.0, 1.0, 0.8))
	soft.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	puff.gradient = soft
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	puff.width = 64
	puff.height = 64
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = puff
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	return quad


## a shell landing: a one-shot burst of earth and smoke, kept and moved rather than rebuilt.
func _burst(parent: Node) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 35.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0.0, -6.0, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.32, 0.25, 0.17, 0.9))
	ramp.set_color(1, Color(0.3, 0.28, 0.25, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	pm.color_ramp = tex
	p.process_material = pm
	p.draw_pass_1 = _puff(1.0)
	_place(parent, p, Vector3.ZERO)
	return p


func _fire(parent: Node, at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 3.0
	light.omni_range = 9.0
	_place(parent, light, at)
	_fires.append({"light": light, "phase": randf() * TAU})


func _step_battle(delta: float) -> void:
	for s in _shooters:
		s["next"] = float(s["next"]) - delta
		var light := s["light"] as OmniLight3D
		var flash := s["flash"] as MeshInstance3D
		if float(s["next"]) <= 0.0:
			s["next"] = randf_range(0.25, 1.4)
			s["off"] = 0.07
			light.light_energy = 7.0
			flash.visible = true
			flash.rotation.z = randf() * TAU
			var muzzle := s["muzzle"] as Node3D
			_tracer(muzzle.global_position, muzzle.global_transform.basis.z)
		elif float(s["off"]) > 0.0:
			s["off"] = float(s["off"]) - delta
			light.light_energy = maxf(0.0, light.light_energy - delta * 90.0)
			if float(s["off"]) <= 0.0:
				flash.visible = false
				light.light_energy = 0.0
	for e in _enemy:
		e["next"] = float(e["next"]) - delta
		var light := e["light"] as OmniLight3D
		if float(e["next"]) <= 0.0:
			e["next"] = randf_range(0.3, 1.8)
			e["off"] = 0.08
			light.light_energy = 9.0
			var from := e["at"] as Vector3
			var to := from + Vector3(randf_range(-6.0, 6.0), -0.1, 28.0)
			_tracer(from, (to - from).normalized())
		elif float(e["off"]) > 0.0:
			e["off"] = float(e["off"]) - delta
			light.light_energy = maxf(0.0, light.light_energy - delta * 100.0)
	for i in range(_tracers.size() - 1, -1, -1):
		var t := _tracers[i]
		var node := t["node"] as Node3D
		t["life"] = float(t["life"]) - delta
		node.position += (t["dir"] as Vector3) * tracer_speed * delta
		if float(t["life"]) <= 0.0:
			node.queue_free()
			_tracers.remove_at(i)
	for f in _fires:
		var light := f["light"] as OmniLight3D
		f["phase"] = float(f["phase"]) + delta * 9.0
		light.light_energy = 2.4 + sin(float(f["phase"])) * 0.7 + sin(float(f["phase"]) * 2.7) * 0.4
	for r in _runners:
		var node := r["node"] as Node3D
		var a := r["a"] as Vector3
		var b := r["b"] as Vector3
		var span := a.distance_to(b)
		r["t"] = float(r["t"]) + run_speed * delta / maxf(span, 0.1)
		if float(r["t"]) >= 1.0:
			r["t"] = 0.0
			if bool(r["across"]):
				a.x = _cams[2].global_position.x + randf_range(-14.0, 10.0)
				b.x = _cams[2].global_position.x + randf_range(-14.0, 10.0)
			else:
				a.z = _cams[2].global_position.z + randf_range(-2.5, 1.0)
				b.z = a.z
			r["a"] = a
			r["b"] = b
		node.position = a.lerp(b, float(r["t"]))
		node.rotation.y = deg_to_rad(yaw_toward(b - a))
	_burst_clock -= delta
	if _burst_clock <= 0.0 and not _bursts.is_empty():
		_burst_clock = randf_range(3.0, 6.5)
		var pick := _bursts[randi() % _bursts.size()]
		var p := pick["node"] as GPUParticles3D
		var origin := _cams[2].global_position
		p.global_position = Vector3(origin.x + randf_range(-16.0, 12.0), 0.1, origin.z - randf_range(8.0, 22.0))
		p.restart()
		p.emitting = true


func _tracer(from: Vector3, dir: Vector3) -> void:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.025, 0.025, 0.6)
	node.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.75)
	node.material_override = mat
	add_child(node)
	node.global_position = from
	node.look_at(from + dir)
	_tracers.append({"node": node, "dir": dir.normalized(), "life": 0.45})


## ---------------------------------------------------------------- what a probe asks
func scene_index() -> int:
	return _index


func scene_name() -> String:
	return SCENES[_index]


func cuts() -> int:
	return _cuts


func scene_count() -> int:
	return _cams.size()


func camera() -> Camera3D:
	return _cams[_index]


func marchers() -> Array[Node3D]:
	return _marchers


func runners() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for r in _runners:
		out.append(r["node"] as Node3D)
	return out


func birds() -> int:
	return _birds


func jump(index: int) -> void:
	_index = clampi(index, 0, _cams.size() - 1)
	_t = 0.0
	_cams[_index].make_current()
