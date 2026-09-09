class_name BriefingMap
extends Control


const DATA := "res://UI/briefing/map.json"
const R_OCEAN := 0.996
const R_LAND := 1.0
## a stained region sits a hair above the land it covers, or the two fight for the same depth and streak.
const R_REGION := 1.0015
const R_GRID := 1.002
const R_INK := 1.004
const R_MARK := 1.008
const MAX_EDGE_DEG := 2.5
const MAX_DEPTH := 5
const GRID_STEP := 15.0
const GRID_SAMPLE := 2.0
const CAMERA_OUT := 4.0
const MARK_RING := 26.0
const LINE_STEPS := 24

@export var space := Color(0.015, 0.025, 0.03)
@export var ocean := Color(0.04, 0.09, 0.105)
@export var horizon := Color(0.55, 0.85, 0.72, 0.35)
@export var grid := Color(0.55, 0.85, 0.72, 0.09)
@export var land := Color(0.10, 0.165, 0.15)
@export var coast := Color(0.55, 0.85, 0.72, 0.5)
@export var stain_colour := Color(0.60, 0.16, 0.11)
@export var stain_fresh := Color(1.0, 0.45, 0.28)
@export var marker := Color(0.98, 0.74, 0.32)
## how long a region takes to go from its first flash to the settled colour.
@export var stain_time := 1.4
@export var mark_period := 1.6
## how long a line takes to grow from one place to the other.
@export var line_time := 1.0
@export var label_font: Font
@export var label_size := 18
## where the globe is looked at from when nothing has asked yet: over the Coral Sea.
@export var home := Vector2(-14.0, 136.0)

## lat and lon of the place under the middle of the screen; the camera hangs over it.
var view_centre := Vector2(-14.0, 136.0)
## 1 is the whole disc filling the height; 7 is New Zealand filling it.
var zoom := 1.0

var _viewport: SubViewport
var _cam: Camera3D
var _overlay: Control
var _region_mesh := {}
var _region_ink := {}
var _region_mat := {}
var _names := {}
var _stains := {}
var _marks: Array[Dictionary] = []
var _paths: Array[Dictionary] = []
var _loaded := false
var _build_ms := 0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	view_centre = home
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(PRESET_FULL_RECT)
	add_child(holder)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	holder.add_child(_viewport)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 10.0
	_viewport.add_child(_cam)
	_overlay = Control.new()
	_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	var t0 := Time.get_ticks_msec()
	_load()
	_build_ms = Time.get_ticks_msec() - t0
	_update_camera()
	resized.connect(queue_redraw)


func _load() -> void:
	var file := FileAccess.open(DATA, FileAccess.READ)
	if file == null:
		push_error("briefing map: cannot open %s" % DATA)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not (data is Dictionary):
		push_error("briefing map: %s is not a dictionary" % DATA)
		return
	var d := data as Dictionary
	_viewport.add_child(_sphere(R_OCEAN, ocean))
	var land_tris := PackedVector3Array()
	var land_lines := PackedVector3Array()
	for ring in d["land"]:
		var pts := _ring(ring)
		land_tris.append_array(_tris(pts, R_LAND, false))
		land_lines.append_array(_lines(pts, R_INK))
	_viewport.add_child(_mesh_node(land_tris, Mesh.PRIMITIVE_TRIANGLES, land))
	_viewport.add_child(_mesh_node(land_lines, Mesh.PRIMITIVE_LINES, coast))
	_viewport.add_child(_mesh_node(_grid_lines(), Mesh.PRIMITIVE_LINES, grid))
	_names = d["names"]
	for id in d["regions"]:
		var tris := PackedVector3Array()
		var lines := PackedVector3Array()
		for ring in d["regions"][id]:
			var pts := _ring(ring)
			tris.append_array(_tris(pts, R_REGION, true))
			lines.append_array(_lines(pts, R_INK + 0.001))
		var fill := _mesh_node(tris, Mesh.PRIMITIVE_TRIANGLES, stain_colour)
		fill.visible = false
		var ink := _mesh_node(lines, Mesh.PRIMITIVE_LINES, stain_fresh)
		ink.visible = false
		_viewport.add_child(fill)
		_viewport.add_child(ink)
		_region_mesh[id] = fill
		_region_ink[id] = ink
		_region_mat[id] = [fill.material_override, ink.material_override]
	_loaded = true


## a ring in the file is lon, lat pairs; here a point is (lon, lat) in degrees.
func _ring(flat: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	@warning_ignore("integer_division")
	pts.resize(flat.size() / 2)
	for i in pts.size():
		pts[i] = Vector2(float(flat[i * 2]), float(flat[i * 2 + 1]))
	return pts


## a place on the earth as a point on the unit sphere: the pole is +y and east is to the right of
## a camera looking at the origin with +y up.
static func unit(lat: float, lon: float) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return Vector3(cos(la) * cos(lo), sin(la), -cos(la) * sin(lo))


static func _unit_ll(p: Vector2) -> Vector3:
	return unit(p.y, p.x)


static func _deg_len(a: Vector2, b: Vector2) -> float:
	return Vector2((a.x - b.x) * cos(deg_to_rad((a.y + b.y) * 0.5)), a.y - b.y).length()


## a ring triangulated flat in lon/lat, then each triangle split until no edge is longer than a
## few degrees, so no chord sinks under the ocean sphere; the pieces are pushed onto the sphere.
## a region's triangles are all split to the SAME depth: split by need, two neighbours meet at
## different depths and the edge between them opens a hairline crack that the land shows through.
func _tris(ring: PackedVector2Array, radius: float, uniform: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var idx := Geometry2D.triangulate_polygon(ring)
	var floor_depth := 0
	if uniform:
		var longest := 0.0
		@warning_ignore("integer_division")
		for t in idx.size() / 3:
			var a := ring[idx[t * 3]]
			var b := ring[idx[t * 3 + 1]]
			var c := ring[idx[t * 3 + 2]]
			longest = maxf(longest, maxf(maxf(_deg_len(a, b), _deg_len(b, c)), _deg_len(c, a)))
		while longest > MAX_EDGE_DEG and floor_depth < MAX_DEPTH:
			longest *= 0.5
			floor_depth += 1
	@warning_ignore("integer_division")
	for t in idx.size() / 3:
		_split(ring[idx[t * 3]], ring[idx[t * 3 + 1]], ring[idx[t * 3 + 2]], out, 0, radius, floor_depth)
	return out


func _split(a: Vector2, b: Vector2, c: Vector2, out: PackedVector3Array, depth: int, radius: float, floor_depth: int) -> void:
	var longest := maxf(maxf(_deg_len(a, b), _deg_len(b, c)), _deg_len(c, a))
	if depth >= floor_depth and (longest <= MAX_EDGE_DEG or depth >= MAX_DEPTH):
		out.append(_unit_ll(a) * radius)
		out.append(_unit_ll(b) * radius)
		out.append(_unit_ll(c) * radius)
		return
	var ab := (a + b) * 0.5
	var bc := (b + c) * 0.5
	var ca := (c + a) * 0.5
	_split(a, ab, ca, out, depth + 1, radius, floor_depth)
	_split(ab, b, bc, out, depth + 1, radius, floor_depth)
	_split(ca, bc, c, out, depth + 1, radius, floor_depth)
	_split(ab, bc, ca, out, depth + 1, radius, floor_depth)


func _lines(ring: PackedVector2Array, radius: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var steps := maxi(1, int(ceil(_deg_len(a, b) / MAX_EDGE_DEG)))
		for s in steps:
			out.append(_unit_ll(a.lerp(b, float(s) / steps)) * radius)
			out.append(_unit_ll(a.lerp(b, float(s + 1) / steps)) * radius)
	return out


func _grid_lines() -> PackedVector3Array:
	var out := PackedVector3Array()
	var lat := -75.0
	while lat <= 75.0:
		var lon := -180.0
		while lon < 180.0:
			out.append(unit(lat, lon) * R_GRID)
			out.append(unit(lat, lon + GRID_SAMPLE) * R_GRID)
			lon += GRID_SAMPLE
		lat += GRID_STEP
	var lon2 := -180.0
	while lon2 < 180.0:
		var lat2 := -90.0
		while lat2 < 90.0:
			out.append(unit(lat2, lon2) * R_GRID)
			out.append(unit(lat2 + GRID_SAMPLE, lon2) * R_GRID)
			lat2 += GRID_SAMPLE
		lon2 += GRID_STEP
	return out


func _flat(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = colour
	if colour.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _mesh_node(verts: PackedVector3Array, kind: int, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		mesh.add_surface_from_arrays(kind, arrays)
	node.mesh = mesh
	node.material_override = _flat(colour)
	return node


func _sphere(radius: float, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48
	node.mesh = mesh
	node.material_override = _flat(colour)
	return node


func _update_camera() -> void:
	var d := unit(view_centre.x, view_centre.y)
	_cam.size = 2.0 / zoom
	_cam.position = d * CAMERA_OUT
	_cam.look_at(Vector3.ZERO, Vector3.UP if absf(d.y) < 0.999 else Vector3.RIGHT)


func _process(delta: float) -> void:
	if not _loaded:
		return
	_update_camera()
	for id in _stains:
		_stains[id] = float(_stains[id]) + delta
		var age: float = _stains[id]
		var tint := stain_fresh.lerp(stain_colour, clampf(age / stain_time, 0.0, 1.0))
		tint.a = clampf(age / 0.25, 0.0, 1.0)
		var ink := stain_fresh.lerp(marker, 0.5)
		ink.a = tint.a * lerpf(1.0, 0.75, clampf(age / stain_time, 0.0, 1.0))
		(_region_mat[id][0] as StandardMaterial3D).albedo_color = tint
		(_region_mat[id][1] as StandardMaterial3D).albedo_color = ink
	for m in _marks:
		m["age"] = float(m["age"]) + delta
	for l in _paths:
		l["age"] = float(l["age"]) + delta
	_overlay.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), space, true)


func _px_per_unit() -> float:
	return size.y * 0.5 * zoom


func _draw_overlay() -> void:
	if not _loaded:
		return
	var origin := _cam.unproject_position(Vector3.ZERO)
	_overlay.draw_arc(origin, _px_per_unit() * R_OCEAN, 0.0, TAU, 256, horizon, 1.5, true)
	var d := unit(view_centre.x, view_centre.y)
	var font := label_font if label_font != null else ThemeDB.fallback_font
	for l in _paths:
		var grown := clampf(float(l["age"]) / line_time, 0.0, 1.0)
		var pts := l["pts"] as PackedVector3Array
		var shown := int(floor(grown * float(pts.size() - 1)))
		var dash := 0
		for i in shown:
			dash += 1
			if dash % 3 == 0 or (pts[i] as Vector3).dot(d) <= 0.0:
				continue
			_overlay.draw_line(_cam.unproject_position(pts[i] * R_MARK), _cam.unproject_position(pts[i + 1] * R_MARK), Color(marker, 0.7), 1.5, true)
	for m in _marks:
		var p := m["pos"] as Vector3
		if p.dot(d) <= 0.0:
			continue
		var at := _cam.unproject_position(p * R_MARK)
		var age: float = m["age"]
		var fade := clampf(age / 0.3, 0.0, 1.0)
		if bool(m["done"]):
			var dim := Color(marker, 0.55 * fade)
			_overlay.draw_arc(at, 5.0, 0.0, TAU, 24, dim, 1.5, true)
			_overlay.draw_line(at + Vector2(-4.0, -4.0), at + Vector2(4.0, 4.0), dim, 1.5, true)
			_overlay.draw_line(at + Vector2(-4.0, 4.0), at + Vector2(4.0, -4.0), dim, 1.5, true)
			var wide := font.get_string_size(String(m["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size - 3).x
			_overlay.draw_string(font, at + Vector2(-14.0 - wide, label_size * 0.36), String(m["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size - 3, dim)
			continue
		var phase := fmod(age, mark_period) / mark_period
		var ring_ink := marker
		ring_ink.a = (1.0 - phase) * fade
		_overlay.draw_arc(at, 6.0 + phase * MARK_RING, 0.0, TAU, 40, ring_ink, 1.5, true)
		_overlay.draw_circle(at, 4.0, Color(marker, fade))
		_overlay.draw_line(at + Vector2(-14.0, 0.0), at + Vector2(14.0, 0.0), Color(marker, 0.6 * fade), 1.0, true)
		_overlay.draw_line(at + Vector2(0.0, -14.0), at + Vector2(0.0, 14.0), Color(marker, 0.6 * fade), 1.0, true)
		_overlay.draw_string(font, at + Vector2(20.0, label_size * 0.36), String(m["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(marker, fade))


## the empire takes a region: the fill flashes and settles. false if the map has no such region.
func stain(id: String) -> bool:
	if not _region_mesh.has(id):
		return false
	if _stains.has(id):
		return true
	_stains[id] = 0.0
	(_region_mesh[id] as MeshInstance3D).visible = true
	(_region_ink[id] as MeshInstance3D).visible = true
	return true


func has_region(id: String) -> bool:
	return _region_mesh.has(id)


func stained() -> Array[String]:
	var out: Array[String] = []
	for id in _stains:
		out.append(String(id))
	return out


func region_name(id: String) -> String:
	return String(_names.get(id, id))


func mark(lat: float, lon: float, label: String, done := false) -> void:
	_marks.append({"pos": unit(lat, lon), "label": label, "age": 0.0, "done": done})


## a dashed line that grows from one place to the other along the great circle between them.
func line(lat_a: float, lon_a: float, lat_b: float, lon_b: float) -> void:
	var a := unit(lat_a, lon_a)
	var b := unit(lat_b, lon_b)
	var pts := PackedVector3Array()
	for i in LINE_STEPS + 1:
		pts.append(a.slerp(b, float(i) / LINE_STEPS))
	_paths.append({"pts": pts, "age": 0.0})


func lines_drawn() -> int:
	return _paths.size()


func marks() -> int:
	return _marks.size()


func clear_marks() -> void:
	_marks.clear()
	_paths.clear()


## the camera swings over a place and closes in; the globe turns under it, so the place arrives
## upright and unforeshortened, which a flat zoom into a fixed projection could not do.
func look_at_place(lat: float, lon: float, target_zoom: float, seconds: float) -> Tween:
	var target := Vector2(lat, lon)
	if seconds <= 0.0:
		view_centre = target
		zoom = target_zoom
		_update_camera()
		return null
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "view_centre", target, seconds)
	tween.tween_property(self, "zoom", target_zoom, seconds)
	return tween


func reset_view() -> void:
	view_centre = home
	zoom = 1.0
	_stains.clear()
	_marks.clear()
	_paths.clear()
	for id in _region_mesh:
		(_region_mesh[id] as MeshInstance3D).visible = false
		(_region_ink[id] as MeshInstance3D).visible = false
	if _cam != null:
		_update_camera()
	queue_redraw()


func is_loaded() -> bool:
	return _loaded


func build_ms() -> int:
	return _build_ms
