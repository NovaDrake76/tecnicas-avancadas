@tool
class_name Foliage
extends Node3D


const NATURE := "res://Models/Nature/%s.glb"

const UPRIGHT := Vector3(PI * 0.5, 0.0, 0.0)


class Band:
	var scenes: Array[String]
	var count: int
	var inner: float
	var outer: float
	var scale_min: float
	var scale_max: float
	var slope_max: float
	var sink: float
	var tint: Color

	func _init(s: Array[String], c: int, i: float, o: float, smin: float, smax: float,
			slope := 1.0, sk := 0.05, tone := Color.WHITE) -> void:
		scenes = s
		count = c
		inner = i
		outer = o
		scale_min = smin
		scale_max = smax
		slope_max = slope
		sink = sk
		tint = tone


@export_group("Layout")
@export var scatter_seed := 1312
## nothing is planted inside this radius, it is the firing lane and it stays clear.
@export var clear_radius := 22.0
## multiplies every band's radii and the clear zone.
@export var ring_scale := 1.0
@export var tree_count := 430
## sparse over the firing range so the grid stays readable, dense past its edge.
@export var range_grass_count := 900
@export var grass_count := 1400
@export var rock_count := 110
@export var fern_count := 220
@export var debris_count := 70

@export_group("Tint")
## the psx grass textures are dry straw.
@export var grass_tint := Color(0.62, 1.35, 0.5)
@export_range(0.0, 0.5) var tint_variation := 0.18

@export_group("Drawing")
## grass is not drawn past this many metres from the camera.
@export var grass_range := 70.0
## ferns, logs and stumps are not drawn past this.
@export var fern_range := 90.0
## grass, ferns and debris cast shadows too when on; off, they stay out of every shadow pass.
@export var small_shadows := false
## grass, ferns and debris are batched in square cells this many metres across, so a cell's range is its grass's range.
@export var small_cell := 24.0
## trees and rocks are batched in cells this big; 0 keeps each species in one batch over the whole map.
@export var large_cell := 0.0

@export_group("Collision")
## trunks block movement.
@export var tree_collision := true
@export var trunk_radius := 0.45
## boulders block movement too, and a stealth map wants things to hide behind.
@export var rock_collision := true
## a ball slightly inside the silhouette, so you can stand against a rock without being shoved.
@export_range(0.3, 1.2) var rock_radius_scale := 0.78

@export_group("Debug")
@export var verbose := false

@export_group("Build")
@export var rebuild := false:
	set(value):
		rebuild = false
		if is_inside_tree():
			build()

static var _scissored_meshes := {}

var _rng := RandomNumberGenerator.new()
var _hills: HillRing


func _ready() -> void:
	build()


func build() -> void:
	for child in get_children():
		child.queue_free()

	_hills = _find_hills()
	_rng.seed = scatter_seed

	var bands: Array[Band] = [
		Band.new(["tree_pine_a", "tree_pine_b", "tree_a", "tree_b", "tree_c"],
			tree_count, 98.0, 210.0, 0.9, 1.8, 0.55, 0.35),
		Band.new(["grass_a", "grass_b", "grass_c", "grass_d"],
			range_grass_count, clear_radius, 98.0, 0.7, 1.2, 1.0, 0.02, grass_tint),
		Band.new(["grass_a", "grass_b", "grass_c", "grass_d"],
			grass_count, 96.0, 210.0, 1.2, 2.5, 1.0, 0.02, grass_tint),
		Band.new(["fern_a", "fern_b"], fern_count, 92.0, 210.0, 1.0, 2.0, 0.9, 0.04),
		Band.new(["stone_a", "stone_b"], rock_count, 90.0, 210.0, 0.7, 2.4, 0.8, 0.2),
		Band.new(["log_a", "stump_a"], debris_count, 100.0, 210.0, 0.9, 1.6, 0.65, 0.12),
	]

	var trunks := PackedVector3Array()
	var trunk_scales := PackedFloat32Array()
	var rocks := PackedVector3Array()
	var rock_radii := PackedFloat32Array()

	for band in bands:
		var is_tree := band.sink >= 0.3 and band.scenes[0].begins_with("tree")
		var is_rock := band.scenes[0].begins_with("stone")
		var per_species := maxi(1, floori(float(band.count) / band.scenes.size()))
		for source in band.scenes:
			var placements := _place(band, per_species)
			var box := _emit(source, placements, band.tint)
			if is_tree and tree_collision:
				for t in placements:
					trunks.append(t.origin)
					trunk_scales.append(t.basis.get_scale().y)
			if is_rock and rock_collision and box.size != Vector3.ZERO:
				var half := maxf(box.size.x, box.size.z) * 0.5 * rock_radius_scale
				for t in placements:
					rocks.append(t.origin)
					rock_radii.append(half * t.basis.get_scale().y)

	if tree_collision and trunks.size() > 0:
		_build_trunk_bodies(trunks, trunk_scales)
	if rock_collision and rocks.size() > 0:
		_build_rock_bodies(rocks, rock_radii)

	if verbose:
		for child in get_children():
			var mmi := child as MultiMeshInstance3D
			if mmi == null:
				continue
			var box := mmi.custom_aabb
			print("  %-24s n=%-6d custom_aabb pos=%s size=%s range=%.0f" % [mmi.name, mmi.multimesh.instance_count,
				str(box.position.round()), str(box.size.round()), mmi.visibility_range_end])


func _find_hills() -> HillRing:
	for node in get_parent().get_children():
		if node is HillRing:
			return node
	return null


func _ground(x: float, z: float) -> float:
	return _hills.surface_height_at(x, z) if _hills != null else 0.0


func _place(band: Band, wanted: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var attempts := wanted * 6
	while out.size() < wanted and attempts > 0:
		attempts -= 1
		var angle := _rng.randf() * TAU
		var t := sqrt(_rng.randf())
		var radius: float = lerpf(band.inner, band.outer, t) * ring_scale
		if radius < clear_radius * ring_scale:
			continue

		var x := cos(angle) * radius
		var z := sin(angle) * radius
		var y := _ground(x, z)

		if band.slope_max < 1.0 and _slope(x, z) > band.slope_max:
			continue

		var grow := _rng.randf_range(band.scale_min, band.scale_max)
		var orient := Basis.from_euler(Vector3(UPRIGHT.x, _rng.randf() * TAU, 0.0)).scaled(Vector3.ONE * grow)
		out.append(Transform3D(orient, Vector3(x, y - band.sink * grow, z)))
	return out


func _slope(x: float, z: float) -> float:
	if _hills == null:
		return 0.0
	var d := 1.5
	var dy_x: float = _ground(x + d, z) - _ground(x - d, z)
	var dy_z: float = _ground(x, z + d) - _ground(x, z - d)
	return Vector2(dy_x, dy_z).length() / (2.0 * d)


static func is_small(source: String) -> bool:
	return source.begins_with("grass") or source.begins_with("fern") \
		or source.begins_with("log") or source.begins_with("stump")


## the graphics quality's share of the grass and fern ranges, set by Settings and read when a level is built.
static var range_scale := 1.0


func _range_of(source: String) -> float:
	if source.begins_with("grass"):
		return grass_range * range_scale
	if is_small(source):
		return fern_range * range_scale
	return 0.0


func _emit(source: String, placements: Array[Transform3D], tint := Color.WHITE) -> AABB:
	if placements.is_empty():
		return AABB()
	var packed := load(NATURE % source) as PackedScene
	if packed == null:
		push_warning("foliage: missing model %s" % source)
		return AABB()

	var probe := packed.instantiate() as Node3D
	var parts := _collect_meshes(probe)
	probe.free()

	var small := is_small(source)
	var cell := small_cell if small else large_cell
	var reach := _range_of(source)
	var cells := _cells(placements, cell)

	var bounds := AABB()
	for index in parts.size():
		var part: Array = parts[index]
		var mesh: Mesh = part[0]
		var local: Transform3D = part[1]
		var tinted := tint != Color.WHITE and mesh.get_surface_count() == 1

		## rolled for every instance in planting order before any batching, so the jitter and every band planted after it land exactly where they always did.
		var colours := PackedColorArray()
		if tinted:
			colours.resize(placements.size())
			for i in placements.size():
				var jitter := _rng.randf_range(-tint_variation, tint_variation)
				colours[i] = Color(tint.r + jitter, tint.g + jitter, tint.b + jitter)
		var drawn_mesh := mesh if tinted else scissored(mesh)
		var override: Material = scissor(_tinting_material(mesh)) if tinted else null

		for key in cells:
			var picked: Array = cells[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = tinted
			mm.mesh = drawn_mesh
			mm.instance_count = picked.size()
			var chunk: Array[Transform3D] = []
			for j in picked.size():
				var at: int = picked[j]
				mm.set_instance_transform(j, placements[at] * local)
				if tinted:
					mm.set_instance_color(j, colours[at])
				chunk.append(placements[at])

			var node := MultiMeshInstance3D.new()
			node.name = "%s_%d_%d_%d" % [source, index, (key as Vector2i).x, (key as Vector2i).y]
			node.multimesh = mm
			## a multimesh assembled in code reports an EMPTY aabb and godot culls every instance; the bounds are handed over explicitly.
			node.custom_aabb = _bounds_of(mesh, local, chunk)
			if override != null:
				node.material_override = override
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if small_shadows or not small \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if reach > 0.0:
				## the range is measured to the cell's centre, so the half diagonal is added or a cell's near edge would vanish at your feet.
				node.visibility_range_end = reach + cell * 0.71
			add_child(node)

		var box := local * mesh.get_aabb()
		bounds = box if index == 0 else bounds.merge(box)

	return bounds


func _cells(placements: Array[Transform3D], cell: float) -> Dictionary:
	var out := {}
	for i in placements.size():
		var key := Vector2i.ZERO
		if cell > 0.0:
			var at := placements[i].origin
			key = Vector2i(floori(at.x / cell), floori(at.z / cell))
		if not out.has(key):
			out[key] = []
		(out[key] as Array).append(i)
	return out


## the same mesh with every alpha-blended surface cut instead, made once per mesh for the session.
static func scissored(mesh: Mesh) -> Mesh:
	var key := mesh.get_instance_id()
	if _scissored_meshes.has(key):
		return _scissored_meshes[key]
	var copy := mesh.duplicate() as Mesh
	var changed := false
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		var cut := scissor(mat)
		if cut != mat:
			copy.surface_set_material(s, cut)
			changed = true
	var out: Mesh = copy if changed else mesh
	_scissored_meshes[key] = out
	return out


static func scissor(mat: Material) -> Material:
	var base := mat as BaseMaterial3D
	if base == null or base.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
		return mat
	var cut := base.duplicate() as BaseMaterial3D
	cut.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	cut.alpha_scissor_threshold = 0.5
	return cut


func _collect_meshes(root: Node3D) -> Array:
	var found: Array = []
	var bounds := AABB()
	var first := true

	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var local := _relative_transform(root, mi)
		found.append([mi.mesh, local])
		var box := local * mi.mesh.get_aabb()
		if first:
			bounds = box
			first = false
		else:
			bounds = bounds.merge(box)

	if found.is_empty():
		return found

	var centre := bounds.get_center()
	var rebase := Transform3D(Basis.IDENTITY, Vector3(-centre.x, -centre.y, -bounds.end.z))
	for part in found:
		part[1] = rebase * part[1]
	return found


func _tinting_material(mesh: Mesh) -> Material:
	var source := mesh.surface_get_material(0) as StandardMaterial3D
	var mat: StandardMaterial3D = source.duplicate() if source != null else StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	return mat


func _bounds_of(mesh: Mesh, local: Transform3D, placements: Array[Transform3D]) -> AABB:
	var box := mesh.get_aabb()
	var bounds := AABB()
	var first := true
	for t in placements:
		var world := (t * local) * box
		if first:
			bounds = world
			first = false
		else:
			bounds = bounds.merge(world)
	return bounds


func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var out := Transform3D.IDENTITY
	var current := node
	while current != null and current != root:
		out = current.transform * out
		current = current.get_parent() as Node3D
	return out


func _build_rock_bodies(points: PackedVector3Array, radii: PackedFloat32Array) -> void:
	var body := StaticBody3D.new()
	body.name = "RockCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	for i in points.size():
		var shape := CollisionShape3D.new()
		var ball := SphereShape3D.new()
		ball.radius = maxf(radii[i], 0.2)
		shape.shape = ball
		## the rocks are sunk into the ground, so the ball sits low or you walk into thin air.
		shape.position = points[i] + Vector3.UP * (ball.radius * 0.5)
		body.add_child(shape)


func _build_trunk_bodies(points: PackedVector3Array, scales: PackedFloat32Array) -> void:
	var body := StaticBody3D.new()
	body.name = "TrunkCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	for i in points.size():
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = trunk_radius * scales[i]
		cyl.height = 6.0 * scales[i]
		shape.shape = cyl
		shape.position = points[i] + Vector3.UP * (cyl.height * 0.5)
		body.add_child(shape)
