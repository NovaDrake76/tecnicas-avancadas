extends Node

## pooled bullet hole decals on static surfaces, autoloaded as BulletHoles.
## a ring buffer, the oldest hole is reused once the pool is full so they never accumulate.

const POOL := 96
const HOLE_SIZE := 0.09
const DEPTH := 0.25

var _decals: Array[Decal] = []
var _next := 0
var _tex: Texture2D


func _ready() -> void:
	_tex = _make_texture()
	for _i in POOL:
		var d := Decal.new()
		d.texture_albedo = _tex
		d.size = Vector3(HOLE_SIZE, DEPTH, HOLE_SIZE)
		d.visible = false
		add_child(d)
		_decals.append(d)
	## build the vfx caches at load, material creation is when godot compiles their pipelines.
	ImpactFx.warm()
	TracerFx.warm()
	MuzzleFlashFx.warm()


## stamp a hole at point, projected into the surface whose outward normal is given.
func mark(point: Vector3, normal: Vector3) -> void:
	if _decals.is_empty():
		return
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var d := _decals[_next]
	_next = (_next + 1) % POOL

	## orient so local +Y is the surface normal, a decal projects along -Y into the wall.
	var t := n.cross(Vector3.RIGHT)
	if t.length() < 0.05:
		t = n.cross(Vector3.FORWARD)
	t = t.normalized()
	var b := t.cross(n).normalized()
	d.global_transform = Transform3D(Basis(t, n, b), point)
	d.rotate_object_local(Vector3.UP, randf() * TAU)
	d.visible = true


func clear() -> void:
	for d in _decals:
		d.visible = false
	_next = 0


func active_holes() -> int:
	var count := 0
	for d in _decals:
		if d.visible:
			count += 1
	return count


## a procedural hole, dark punched core with a lighter chipped rim and soft alpha falloff.
func _make_texture() -> Texture2D:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s * 0.5, s * 0.5)
	for y in s:
		for x in s:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(c) / (s * 0.5)
			var col := Color(0.04, 0.04, 0.05)
			var a := 0.0
			if dist < 0.5:
				a = 0.95
			elif dist < 0.9:
				a = 1.0 - (dist - 0.5) / 0.4
				col = Color(0.16, 0.15, 0.14)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
