class_name KiwiBody
extends Node


## the body as an egg, measured off the mesh: what any kit strapped to it is cut against.
const BODY_C := Vector3(0.0, 0.27, 0.0)
const BODY_R := Vector3(0.177, 0.195, 0.222)
## the egg sits nose-up by this much, about the bird's own x axis.
const BODY_TILT_DEG := 13.0
## how much the belly pulls in below the middle: the chest is the fat end.
const BODY_SQUEEZE := 0.5
## the rump is shorter than the chest.
const BODY_BACK := 0.86
## the chest stands nearly vertical up to the neck where an egg would curve in.
const BODY_CHEST := 0.5


static func body_tilt() -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(BODY_TILT_DEG))


const MAP_AZ := 64
const MAP_EL := 32
const HEAD_R_FALLBACK := Vector3(0.078, 0.058, 0.105)
static var _maps := {}
static var _map := {}
static var _head_c := Vector3(0.0, 0.522, -0.2)


static func fit(kiwi: Node3D, skeleton: Skeleton3D, head_c: Vector3) -> void:
	_head_c = head_c
	var mi: MeshInstance3D = null
	if skeleton != null:
		for ch in skeleton.get_children():
			if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
				mi = ch
				break
	if mi == null:
		_map = {}
		return
	var key := "%s|%s" % [mi.mesh.resource_path if mi.mesh.resource_path != "" else str(mi.mesh.get_instance_id()), head_c]
	if _maps.has(key):
		_map = _maps[key]
		return
	var into := kiwi.global_transform.affine_inverse() * mi.global_transform
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var body := _radial(verts, into, BODY_C, body_tilt(), func(q: Vector3) -> bool:
		return q.y >= 0.17 and q.y < 0.47 and q.z > -0.29)
	var head := _radial(verts, into, head_c, Basis.IDENTITY, func(q: Vector3) -> bool:
		return q.y > 0.46 and q.z > -0.3 and q.z < 0.02)
	## the CORE of the bird, not its feathers: an opening (a min filter then a max filter, two bins
	## wide) drops every spike thinner than four bins -- the tufts, the crest, the beak root -- and a
	## mean smooths what is left, so kit hugs the body and a feather may overlap it, never the reverse.
	_map = {"body": _core(_filled(body)), "head": _core(_filled(head)), "body_raw": body, "head_raw": head}
	_maps[key] = _map


static func _core(filled: PackedFloat32Array) -> PackedFloat32Array:
	var eroded := _filter(filled, 2, false)
	var opened := _filter(eroded, 2, true)
	var smooth := PackedFloat32Array()
	smooth.resize(MAP_AZ * MAP_EL)
	for j in MAP_EL:
		for i in MAP_AZ:
			var sum := 0.0
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					sum += opened[clampi(j + dj, 0, MAP_EL - 1) * MAP_AZ + posmod(i + di, MAP_AZ)]
			smooth[j * MAP_AZ + i] = sum / 9.0
	return smooth


static func _filter(map: PackedFloat32Array, radius: int, take_max: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(MAP_AZ * MAP_EL)
	for j in MAP_EL:
		for i in MAP_AZ:
			var best := 0.0 if take_max else INF
			for dj in range(-radius, radius + 1):
				for di in range(-radius, radius + 1):
					var v := map[clampi(j + dj, 0, MAP_EL - 1) * MAP_AZ + posmod(i + di, MAP_AZ)]
					best = maxf(best, v) if take_max else minf(best, v)
			out[j * MAP_AZ + i] = best
	return out


static func _bin(az: float, el: float) -> int:
	var i := int(floor(fposmod(az, TAU) / TAU * MAP_AZ)) % MAP_AZ
	var j := clampi(int(floor((el + PI * 0.5) / PI * MAP_EL)), 0, MAP_EL - 1)
	return j * MAP_AZ + i


static func _radial(verts: PackedVector3Array, into: Transform3D, centre: Vector3, basis: Basis, keep: Callable) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	r.resize(MAP_AZ * MAP_EL)
	r.fill(0.0)
	var inv := basis.inverse()
	for v in verts:
		var q: Vector3 = into * v
		if not keep.call(q):
			continue
		var local: Vector3 = inv * (q - centre)
		var d := local.length()
		if d < 0.001:
			continue
		var az := atan2(local.x, -local.z)
		var el := asin(clampf(local.y / d, -1.0, 1.0))
		var k := _bin(az, el)
		r[k] = maxf(r[k], d)
	## a vertex covers its neighbours too, so the face between two vertices is never a hole in the map.
	var grown := r.duplicate()
	for j in MAP_EL:
		for i in MAP_AZ:
			var best := 0.0
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					best = maxf(best, r[clampi(j + dj, 0, MAP_EL - 1) * MAP_AZ + posmod(i + di, MAP_AZ)])
			grown[j * MAP_AZ + i] = best
	return grown


static func _filled(measured: PackedFloat32Array) -> PackedFloat32Array:
	var grown := measured.duplicate()
	for _pass in 40:
		var again := false
		var filled := grown.duplicate()
		for j in MAP_EL:
			for i in MAP_AZ:
				if grown[j * MAP_AZ + i] > 0.0:
					continue
				var best := 0.0
				for dj in [-1, 0, 1]:
					for di in [-1, 0, 1]:
						best = maxf(best, grown[clampi(j + dj, 0, MAP_EL - 1) * MAP_AZ + posmod(i + di, MAP_AZ)])
				if best > 0.0:
					filled[j * MAP_AZ + i] = best
					again = true
		grown = filled
		if not again:
			break
	return grown


static func _sample(map: PackedFloat32Array, az: float, el: float) -> float:
	var fa := fposmod(az, TAU) / TAU * MAP_AZ - 0.5
	var fe := clampf((el + PI * 0.5) / PI * MAP_EL - 0.5, 0.0, MAP_EL - 1.001)
	var i0 := int(floor(fa))
	var ta := fa - float(i0)
	var j0 := int(floor(fe))
	var te := fe - float(j0)
	var ia := posmod(i0, MAP_AZ)
	var ib := posmod(i0 + 1, MAP_AZ)
	var jb := mini(j0 + 1, MAP_EL - 1)
	var top := lerpf(map[j0 * MAP_AZ + ia], map[j0 * MAP_AZ + ib], ta)
	var bottom := lerpf(map[jb * MAP_AZ + ia], map[jb * MAP_AZ + ib], ta)
	return lerpf(top, bottom, te)


static func _dir(azimuth: float, elevation: float) -> Vector3:
	var c := cos(elevation)
	return Vector3(sin(azimuth) * c, sin(elevation), -cos(azimuth) * c)


static func body_point(azimuth: float, elevation: float, out := 0.0) -> Vector3:
	if _map.has("body"):
		var r: float = _sample(_map["body"], azimuth, elevation) + out
		return BODY_C + body_tilt() * (_dir(azimuth, elevation) * r)
	return KitMesh.on_ellipsoid(BODY_C, BODY_R + Vector3.ONE * out, azimuth, elevation, body_tilt(), BODY_SQUEEZE, BODY_BACK, BODY_CHEST)


static func body_normal(azimuth: float, elevation: float) -> Vector3:
	return (body_point(azimuth, elevation, 0.05) - body_point(azimuth, elevation, 0.0)).normalized()


static func head_point(azimuth: float, elevation: float, out := 0.0) -> Vector3:
	if _map.has("head"):
		var r: float = _sample(_map["head"], azimuth, elevation) + out
		return _head_c + _dir(azimuth, elevation) * r
	return KitMesh.on_ellipsoid(_head_c, HEAD_R_FALLBACK + Vector3.ONE * out, azimuth, elevation)


static func head_normal(azimuth: float, elevation: float) -> Vector3:
	return (head_point(azimuth, elevation, 0.05) - head_point(azimuth, elevation, 0.0)).normalized()


static func body_patch(az0: float, az1: float, el0: float, el1: float, nu: int, nv: int, out: float,
		thickness := 0.0, color := Callable(), hem := Callable()) -> ArrayMesh:
	var fn := func(u: float, v: float) -> Vector3:
		var e := v
		if hem.is_valid():
			e = lerpf(float(hem.call(u)), el1, (v - el0) / maxf(el1 - el0, 0.0001))
		return body_point(u, e, out)
	var inner := func(u: float, v: float) -> Vector3:
		var e := v
		if hem.is_valid():
			e = lerpf(float(hem.call(u)), el1, (v - el0) / maxf(el1 - el0, 0.0001))
		return body_point(u, e, out - thickness)
	return KitMesh.patch(fn, az0, az1, el0, el1, nu, nv, BODY_C, thickness, color, inner)


static func head_patch(az0: float, az1: float, el0: float, el1: float, nu: int, nv: int, out: float,
		thickness := 0.0) -> ArrayMesh:
	var fn := func(u: float, v: float) -> Vector3:
		return head_point(u, v, out)
	var inner := func(u: float, v: float) -> Vector3:
		return head_point(u, v, out - thickness)
	return KitMesh.patch(fn, az0, az1, el0, el1, nu, nv, _head_c, thickness, Callable(), inner)


static func deepest(kiwi: Node3D, skeleton: Skeleton3D) -> Dictionary:
	var worst := {"depth": -1.0, "piece": "nothing"}
	if skeleton == null or _map.is_empty():
		return worst
	var into_kiwi := kiwi.global_transform.affine_inverse()
	var inv_tilt := body_tilt().inverse()
	for rig in skeleton.get_children():
		if not (rig is BoneRig):
			continue
		for node in rig.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null or mi.name == "Cape":
				continue
			## measured in the REST pose: the head may be mid-sweep on an idle clip, and the map is of the bird at rest.
			var bone_rig := rig as BoneRig
			var rest: Transform3D = skeleton.global_transform * skeleton.get_bone_global_rest(bone_rig.bone_idx)
			var into: Transform3D = into_kiwi * rest * (bone_rig.global_transform.affine_inverse() * mi.global_transform)
			for surface in mi.mesh.get_surface_count():
				var verts: PackedVector3Array = mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for v in verts:
					var q: Vector3 = into * v
					var depth := -1.0
					if (q - _head_c).length() < 0.15 and q.z > -0.3:
						var local := q - _head_c
						var d := local.length()
						var az := atan2(local.x, -local.z)
						var el := asin(clampf(local.y / maxf(d, 0.001), -1.0, 1.0))
						if _map["head_raw"][_bin(az, el)] > 0.0:
							depth = _sample(_map["head"], az, el) - d
					if depth < 0.0 and q.y >= 0.17 and q.y < 0.47:
						var local := inv_tilt * (q - BODY_C)
						var d := local.length()
						var az := atan2(local.x, -local.z)
						var el := asin(clampf(local.y / maxf(d, 0.001), -1.0, 1.0))
						if _map["body_raw"][_bin(az, el)] > 0.0:
							depth = maxf(depth, _sample(_map["body"], az, el) - d)
					if depth > float(worst["depth"]):
						worst = {"depth": depth, "piece": "%s/%s" % [rig.name, mi.name], "at": q,
							"head": (q - _head_c).length() < 0.15 and q.z > -0.3, "mesh": mi.mesh.resource_name if mi.mesh.resource_name != "" else mi.mesh.get_class()}
	return worst

@export_group("Down")
## a downed bird TIPS OVER rather than playing the settle clip, which leaves it standing with its eyes shut.
@export var lie_down := true
@export var lie_roll_deg := 84.0
@export var lie_time := 0.35
## how hard the ground slows a thrown body: friction, not a timer, so a hard throw travels further.
@export var throw_friction := 14.0
## the two crosses over the eyes.
@export var mark_eyes := true
@export var eye_mark_size := 0.075
## OFF by default: a downed kiwi stays lying where it fell, which is what makes where you drop one a decision.
@export var vanish_on_down := false
## long enough for the slowest, lowest call to finish before the node carrying it is freed.
@export var despawn_delay := 1.6

@export_group("Down burst")
@export var burst_light := Color(0.55, 0.4, 0.2)
@export var burst_dark := Color(0.22, 0.15, 0.09)
@export var burst_count := 34
@export var burst_speed := 3.8

var _kiwi: Kiwi
var _model: Node3D
var _found := false
var _dragged := false
var _thrown := false
var _tumble := 0.0
var _handle: Area3D
var _grab: Interactable


func _ready() -> void:
	_kiwi = get_parent() as Kiwi
	_model = _kiwi.get_node_or_null("Model") as Node3D


func collapse(at: Vector3) -> void:
	var world := get_tree().current_scene
	BurstFx.spawn(world, at, burst_light, burst_count, burst_speed)
	BurstFx.spawn(world, at, burst_dark, int(burst_count * 0.6), burst_speed * 0.8)
	if not vanish_on_down:
		_lie_down()
		_mark_eyes()
		_become_body()
		return
	if _model != null:
		_model.visible = false
	Sfx.play(&"kiwi_poof", at)
	_kiwi.set_physics_process(false)
	## the node outlives the burst by a moment; the particles are parented to the world, not to us.
	get_tree().create_timer(despawn_delay).timeout.connect(_kiwi.queue_free)


func toss(launch: Vector3, spin: float) -> void:
	if not _kiwi.is_down():
		return
	_thrown = true
	_tumble = spin
	_kiwi.velocity = launch
	_kiwi.set_physics_process(true)


func step_thrown(delta: float) -> bool:
	if not _thrown:
		return false
	_kiwi.velocity.y -= _kiwi.gravity * delta
	if _model != null:
		_model.rotation.x += _tumble * delta
	if _kiwi.is_on_floor():
		_kiwi.velocity.x = move_toward(_kiwi.velocity.x, 0.0, throw_friction * delta)
		_kiwi.velocity.z = move_toward(_kiwi.velocity.z, 0.0, throw_friction * delta)
		_tumble = move_toward(_tumble, 0.0, throw_friction * delta)
	_kiwi.move_and_slide()
	if not _kiwi.is_on_floor() or Vector2(_kiwi.velocity.x, _kiwi.velocity.z).length() > 0.4:
		return true
	_thrown = false
	_kiwi.velocity = Vector3.ZERO
	if _model != null:
		_model.rotation.x = 0.0
		_model.rotation.z = deg_to_rad(lie_roll_deg)
		_model.position.y = lie_lift(deg_to_rad(lie_roll_deg))
	Sfx.play(&"body_drop", _kiwi.global_position)
	return true


func is_thrown() -> bool:
	return _thrown


func set_dragged(value: bool) -> void:
	_dragged = value
	if _grab != null:
		_grab.set_enabled(not value)
	if _model != null:
		_model.rotation.z = 0.0 if value else deg_to_rad(lie_roll_deg)
		_model.position.y = 0.0 if value else lie_lift(deg_to_rad(lie_roll_deg))


func is_dragged() -> bool:
	return _dragged


func mark_found() -> void:
	_found = true


func is_found() -> bool:
	return _found


func _become_body() -> void:
	_kiwi.add_to_group("body")
	_handle = Area3D.new()
	_handle.collision_layer = 128
	_handle.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.75, 0.5, 0.75)
	shape.shape = box
	shape.position = Vector3(0.0, 0.25, 0.0)
	_handle.add_child(shape)
	_kiwi.add_child(_handle)
	_grab = Interactable.new()
	_grab.prompt = "Pick the body up"
	_kiwi.add_child(_grab)
	_grab.interacted.connect(_on_grab_pressed)


func _on_grab_pressed(_by: Node) -> void:
	for node in get_tree().get_nodes_in_group("body_drag"):
		var drag := node as BodyDrag
		if drag != null:
			drag.grab(_kiwi)
			return


func _lie_down() -> void:
	if not lie_down or _model == null:
		return
	var roll := deg_to_rad(lie_roll_deg)
	var lift := lie_lift(roll)
	var over := create_tween()
	over.set_trans(Tween.TRANS_CUBIC)
	over.set_ease(Tween.EASE_OUT)
	over.tween_property(_model, "rotation:z", roll, lie_time)
	over.parallel().tween_property(_model, "position:y", lift, lie_time)


func lie_lift(roll: float) -> float:
	if _model == null:
		return 0.0
	var bounds := AABB()
	var first := true
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var box := (_model.global_transform.affine_inverse() * mesh.global_transform) * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		return _model.position.y
	var turn := Basis(Vector3.BACK, roll)
	var lowest := INF
	for i in 8:
		lowest = minf(lowest, (turn * bounds.get_endpoint(i)).y)
	return maxf(-lowest, 0.0)


func _mark_eyes() -> void:
	if not mark_eyes:
		return
	var skeleton: Skeleton3D = null
	for node in _kiwi.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	if skeleton == null:
		return
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(i).to_lower()
		if not (bone.begins_with("eye.l") or bone.begins_with("eye.r")):
			continue
		var mount := BoneAttachment3D.new()
		mount.bone_idx = i
		skeleton.add_child(mount)
		mount.add_child(_cross())


func _cross() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.05, 0.04, 0.04)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for angle in [45.0, -45.0]:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(eye_mark_size, eye_mark_size * 0.22, eye_mark_size * 0.22)
		bar.mesh = box
		bar.material_override = mat
		bar.rotation.z = deg_to_rad(angle)
		root.add_child(bar)
	return root
