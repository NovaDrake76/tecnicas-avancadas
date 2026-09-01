@tool
class_name HillRing
extends Node3D

## hills that begin where the flat range ends, so the world has an edge you cannot see over.
## the middle stays perfectly flat on purpose, the gridded floor is the ruler the ballistics demo reads.

@export_group("Shape")
## the floor is a 200 m square, so the falloff follows a square too or the corners poke through.
@export var square_falloff := true
## everything inside this stays flat. it must match the floor's half extent.
@export var inner := 100.0
## the hills reach full height by here.
@export var outer := 190.0
@export var extent := 440.0
@export var resolution := 150
@export var height := 26.0
## above 1 pushes more ground low, which reads as separate hills rather than one smooth wall.
@export var contrast := 1.7

@export_group("Noise")
@export var noise_seed := 20260901
@export var noise_frequency := 0.008
@export var noise_octaves := 4
@export var detail_frequency := 0.035
@export var detail_amount := 1.8

@export_group("Look")
@export var grass_shader: Shader = preload("res://Shaders/terrain_grass.gdshader")

@export_group("Build")
## flip this in the editor to rebuild after changing anything above.
@export var rebuild := false:
	set(value):
		rebuild = false
		if is_inside_tree():
			build()

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ready_noise := false


func _ready() -> void:
	build()


func _configure_noise() -> void:
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = noise_frequency
	_noise.fractal_octaves = noise_octaves
	_detail.seed = noise_seed + 977
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = detail_frequency
	_ready_noise = true


## 0 on the flat range, 1 out where the hills are full height.
func falloff(x: float, z: float) -> float:
	var d := maxf(absf(x), absf(z)) if square_falloff else Vector2(x, z).length()
	return smoothstep(inner, outer, d)


## the ground height at a world point. the foliage scatter calls this so plants sit on the ground.
func height_at(x: float, z: float) -> float:
	if not _ready_noise:
		_configure_noise()
	var ramp := falloff(x, z)
	if ramp <= 0.0:
		return 0.0
	var base: float = pow(_noise.get_noise_2d(x, z) * 0.5 + 0.5, contrast)
	var fine := _detail.get_noise_2d(x, z) * detail_amount
	return (base * height + fine) * ramp


func build() -> void:
	_configure_noise()
	for child in get_children():
		child.queue_free()

	var step := extent / float(resolution)
	var half := extent * 0.5

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()

	for iz in resolution:
		for ix in resolution:
			var x0 := -half + float(ix) * step
			var z0 := -half + float(iz) * step
			var x1 := x0 + step
			var z1 := z0 + step

			var a := Vector3(x0, height_at(x0, z0), z0)
			var b := Vector3(x1, height_at(x1, z0), z0)
			var c := Vector3(x1, height_at(x1, z1), z1)
			var d := Vector3(x0, height_at(x0, z1), z1)

			_add_tri(surface, a, b, c)
			_add_tri(surface, a, c, d)
			faces.append_array([a, b, c, a, c, d])

	surface.generate_normals()

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "HillMesh"
	mesh_node.mesh = surface.commit()
	mesh_node.material_override = _make_material()
	_attach(mesh_node)

	var body := StaticBody3D.new()
	body.name = "HillBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	_attach(body)


## the geometry is GENERATED, never stored. setting owner here is what told godot to serialise
## every vertex and every instance transform into level_01.tscn, and took it to 38 MB.
func _attach(node: Node) -> void:
	add_child(node)


func _add_tri(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		surface.add_vertex(v)


func _make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = grass_shader
	return mat


## the height of the MESH surface, which is not the same as height_at on a curved slope.
## the mesh is flat triangles between grid corners, so a prop placed with the smooth function
## floats above the ground wherever the surface bulges, and sinks where it dips.
func surface_height_at(x: float, z: float) -> float:
	var step := extent / float(resolution)
	var half := extent * 0.5
	var fx := (x + half) / step
	var fz := (z + half) / step
	var ix := clampi(int(floor(fx)), 0, resolution - 1)
	var iz := clampi(int(floor(fz)), 0, resolution - 1)
	var u := fx - float(ix)
	var v := fz - float(iz)

	var x0 := -half + float(ix) * step
	var z0 := -half + float(iz) * step
	var x1 := x0 + step
	var z1 := z0 + step

	var ha := height_at(x0, z0)
	var hb := height_at(x1, z0)
	var hc := height_at(x1, z1)
	var hd := height_at(x0, z1)

	## the quad is split a-b-c and a-c-d, so which triangle a point lands in decides the plane.
	if u >= v:
		return ha + (hb - ha) * u + (hc - hb) * v
	return ha + (hc - hd) * u + (hd - ha) * v
