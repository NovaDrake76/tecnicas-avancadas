class_name KiwiSuit
extends RefCounted


const OLIVE := Color(0.42, 0.43, 0.27)
const OLIVE_DARK := Color(0.33, 0.34, 0.21)
const CHARCOAL := Color(0.2, 0.2, 0.21)
const STEEL := Color(0.3, 0.31, 0.32)
const PALE := Color(0.86, 0.86, 0.8)
const AMBER := Color(0.92, 0.6, 0.17)
const AMBER_LEADER := Color(1.0, 0.85, 0.5)
const VISOR := Color(0.95, 0.66, 0.28, 0.42)
const CAPE := [Color(0.27, 0.3, 0.18), Color(0.31, 0.26, 0.16), Color(0.2, 0.25, 0.15), Color(0.24, 0.28, 0.2)]

## the helmet's egg, relative to the point between the eyes and around the skull: measured.
const HEAD_AT := Vector3(0.0, 0.013, 0.046)
const HEAD_R := Vector3(0.078, 0.058, 0.105)
## the visor sits this far off the shell, a bubble the eyes look out of.
const VISOR_OUT := 0.02

var plates: Array[MeshInstance3D] = []
var trims: Array[MeshInstance3D] = []
var chevron: MeshInstance3D
var plate_mat: StandardMaterial3D
var strap_mat: StandardMaterial3D
var dark_mat: StandardMaterial3D
var steel_mat: StandardMaterial3D
var lamp_mat: StandardMaterial3D
var visor_mat: StandardMaterial3D
var pale_mat: StandardMaterial3D

var _head_c := Vector3.ZERO


func build(kind: int, head: Node3D, torso: Node3D, leg_l: Node3D, leg_r: Node3D, mid: Vector3) -> void:
	_materials()
	_head_c = mid + HEAD_AT
	_helmet(head, kind)
	_carrier(torso, kind)
	if leg_l != null:
		_greave(leg_l, -1.0)
	if leg_r != null:
		_greave(leg_r, 1.0)
	if kind == KiwiArmour.Kind.SNIPER:
		_cape(torso)
		_scope(head)
	for mi in plates:
		mi.layers = 2
	for mi in trims:
		mi.layers = 2
	if chevron != null:
		chevron.layers = 2


func _materials() -> void:
	plate_mat = KitMesh.matte(OLIVE, 0.9, 0.05)
	plate_mat.emission_enabled = true
	plate_mat.emission = Color.WHITE
	plate_mat.emission_energy_multiplier = 0.0
	dark_mat = KitMesh.matte(OLIVE_DARK, 0.9, 0.05)
	strap_mat = KitMesh.matte(CHARCOAL, 0.85, 0.05)
	steel_mat = KitMesh.matte(STEEL, 0.5, 0.6)
	pale_mat = KitMesh.glow(PALE, 0.25)
	lamp_mat = KitMesh.glow(AMBER, 1.2)
	visor_mat = KitMesh.glow(VISOR, 0.35)
	visor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visor_mat.albedo_color = VISOR


func flash(level: float) -> void:
	plate_mat.emission_energy_multiplier = level * 3.0


func set_leader(leader: bool) -> void:
	lamp_mat.albedo_color = AMBER_LEADER if leader else AMBER
	lamp_mat.emission = AMBER_LEADER if leader else AMBER
	lamp_mat.emission_energy_multiplier = 2.4 if leader else 1.2
	if chevron != null:
		chevron.visible = leader


# ---------------------------------------------------------------- the helmet

func _on_head(azimuth: float, elevation: float, out := 0.0) -> Vector3:
	return KiwiBody.head_point(azimuth, elevation, out)


func _head_normal(azimuth: float, elevation: float) -> Vector3:
	return KiwiBody.head_normal(azimuth, elevation)


func _head_patch(parent: Node3D, az0: float, az1: float, el0: float, el1: float, out: float, thick: float,
		mat: Material, nu := 16, nv := 6) -> MeshInstance3D:
	var mesh := KiwiBody.head_patch(az0, az1, el0, el1, nu, nv, out, thick)
	return KitMesh.put(mesh, mat, parent)


func _helmet(head: Node3D, kind: int) -> void:
	var crown := _head_patch(head, -PI, PI, 0.25, 1.5, 0.009, 0.007, plate_mat, 28, 7)
	crown.name = "Crown"
	plates.append(crown)
	var skirt := _head_patch(head, 1.0, TAU - 1.0, -0.36, 0.25, 0.009, 0.007, plate_mat, 24, 4)
	skirt.name = "Skirt"
	plates.append(skirt)
	var ridge := _head_patch(head, -0.07, 0.07, 0.5, 1.5, 0.017, 0.006, dark_mat, 2, 6)
	ridge.name = "RidgeFront"
	plates.append(ridge)
	var spine := _head_patch(head, PI - 0.07, PI + 0.07, -0.32, 1.5, 0.017, 0.006, dark_mat, 2, 8)
	spine.name = "RidgeBack"
	plates.append(spine)
	for side in [-1.0, 1.0]:
		var az0: float = minf(side * 0.25, side * 1.05)
		var az1: float = maxf(side * 0.25, side * 1.05)
		var pane := _head_patch(head, az0, az1, -0.68, 0.3, VISOR_OUT, 0.0, visor_mat, 8, 6)
		pane.name = "VisorL" if side < 0.0 else "VisorR"
		trims.append(pane)
	var centre := _head_patch(head, -0.25, 0.25, -0.26, 0.3, VISOR_OUT, 0.0, visor_mat, 4, 4)
	centre.name = "VisorC"
	trims.append(centre)
	var frame_mat := dark_mat
	var brow := _head_patch(head, -1.08, 1.08, 0.25, 0.32, VISOR_OUT * 0.55 + 0.007, 0.006, frame_mat, 16, 1)
	brow.name = "VisorFrame"
	plates.append(brow)
	for side in [-1.0, 1.0]:
		var cup_at := _on_head(side * 1.7, -0.12, 0.02)
		var n := _head_normal(side * 1.7, -0.12)
		var cup := KitMesh.lathe(PackedVector2Array([Vector2(0.0, 0.016), Vector2(0.02, 0.016), Vector2(0.024, 0.008),
			Vector2(0.024, 0.0), Vector2(0.0, 0.0)]), 16, Callable(), PackedFloat32Array(), PackedInt32Array([1, 2, 3]))
		var ear := KitMesh.put(cup, plate_mat, head, cup_at, "Ear")
		ear.basis = KitMesh.basis_along(n)
		plates.append(ear)
		var dot := KitMesh.lathe(PackedVector2Array([Vector2(0.0, 0.019), Vector2(0.009, 0.019), Vector2(0.009, 0.015), Vector2(0.0, 0.015)]),
			10, Callable(), PackedFloat32Array(), PackedInt32Array([1, 2]))
		var light := KitMesh.put(dot, lamp_mat, head, cup_at, "EarLight")
		light.basis = KitMesh.basis_along(n)
		trims.append(light)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var lb := BoxMesh.new()
	lb.size = Vector3(0.034, 0.011, 0.006)
	lamp.mesh = lb
	lamp.material_override = lamp_mat
	lamp.position = _on_head(0.0, 0.42, 0.008)
	lamp.basis = Basis.looking_at(-_head_normal(0.0, 0.42), Vector3.UP)
	head.add_child(lamp)
	trims.append(lamp)
	var mast := _on_head(-2.4, 0.3, 0.004)
	var whip := KitMesh.rod(head, mast, mast + Vector3(-0.012, 0.075, 0.02), 0.0025, strap_mat)
	whip.name = "Mast"
	plates.append(whip)
	if kind == KiwiArmour.Kind.SNIPER:
		return


func _scope(head: Node3D) -> void:
	var at := _on_head(0.62, 0.38, 0.034)
	var scope := Node3D.new()
	scope.name = "Scope"
	scope.position = at + Vector3(0.0, 0.0, -0.02)
	head.add_child(scope)
	var tube := PackedVector2Array([Vector2(0.0, 0.04), Vector2(0.012, 0.04), Vector2(0.012, -0.028),
		Vector2(0.015, -0.028), Vector2(0.015, -0.04), Vector2(0.0, -0.04)])
	var body := KitMesh.lathe(tube, 14, Callable(), PackedFloat32Array(), PackedInt32Array([1, 2, 3, 4]))
	var barrel := KitMesh.put(body, steel_mat, scope, Vector3.ZERO, "ScopeTube")
	barrel.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	plates.append(barrel)
	var lens := KitMesh.lathe(PackedVector2Array([Vector2(0.0, 0.043), Vector2(0.009, 0.043), Vector2(0.009, 0.039), Vector2(0.0, 0.039)]),
		14, Callable(), PackedFloat32Array(), PackedInt32Array([1, 2]))
	var glass := KitMesh.put(lens, lamp_mat, scope, Vector3.ZERO, "ScopeLens")
	glass.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	trims.append(glass)
	var post := KitMesh.rod(head, at, at - _head_normal(0.62, 0.38) * 0.03, 0.005, steel_mat)
	post.name = "ScopePost"
	plates.append(post)


# ---------------------------------------------------------------- the carrier

func _body_patch(parent: Node3D, az0: float, az1: float, el0: float, el1: float, out: float, thick: float,
		mat: Material, nu := 16, nv := 8) -> MeshInstance3D:
	var mesh := KiwiBody.body_patch(az0, az1, el0, el1, nu, nv, out, thick)
	return KitMesh.put(mesh, mat, parent)


func _facing(azimuth: float, elevation: float, out: float) -> Transform3D:
	var at := KiwiBody.body_point(azimuth, elevation, out)
	return Transform3D(Basis.looking_at(-KiwiBody.body_normal(azimuth, elevation), Vector3.UP), at)


func _box(parent: Node3D, size: Vector3, at: Transform3D, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := KitMesh.put(bm, mat, parent)
	mi.transform = at
	return mi


func _carrier(torso: Node3D, kind: int) -> void:
	var chest := _body_patch(torso, -0.8, 0.8, 0.28, 0.48, 0.017, 0.014, plate_mat)
	chest.name = "Chest"
	plates.append(chest)
	var hem_band := _body_patch(torso, -0.8, 0.8, 0.22, 0.28, 0.018, 0.006, strap_mat, 12, 1)
	hem_band.name = "ChestBand"
	plates.append(hem_band)
	for side in [-1.0, 1.0]:
		var strip := _box(torso, Vector3(0.009, 0.034, 0.005), _facing(side * 0.46, 0.55, 0.032), lamp_mat)
		strip.name = "ChestLight"
		trims.append(strip)
	var wing := KitMesh.flat(PackedVector2Array([
		Vector2(0.0, 0.62), Vector2(0.14, 0.18), Vector2(-0.14, 0.18),
		Vector2(0.0, 0.3), Vector2(1.0, 0.62), Vector2(0.85, 0.2), Vector2(0.5, -0.05),
		Vector2(-1.0, 0.62), Vector2(-0.85, 0.2), Vector2(-0.5, -0.05),
		Vector2(0.0, 0.16), Vector2(0.16, -0.45), Vector2(-0.16, -0.45)]),
		PackedInt32Array([0, 1, 2, 3, 4, 5, 3, 5, 6, 3, 8, 7, 3, 9, 8, 10, 11, 12]), 0.032)
	var badge := KitMesh.put(wing, pale_mat, torso, Vector3.ZERO, "Badge")
	badge.transform = _facing(-0.36, 0.5, 0.035)
	trims.append(badge)
	var belt := _body_patch(torso, -PI, PI, 0.05, 0.2, 0.012, 0.006, strap_mat, 28, 2)
	belt.name = "Belt"
	plates.append(belt)
	for az in [-0.46, 0.0, 0.46]:
		var pouch := _box(torso, Vector3(0.05, 0.048, 0.032), _facing(float(az), 0.12, 0.031), plate_mat)
		pouch.name = "Pouch"
		plates.append(pouch)
		var flap := _box(torso, Vector3(0.052, 0.016, 0.036), _facing(float(az), 0.2, 0.033), strap_mat)
		flap.name = "PouchFlap"
		plates.append(flap)
	for side in [-1.0, 1.0]:
		var strap := KiwiBody.body_patch(side * 0.62 - 0.05, side * 0.62 + 0.05, 0.56, PI - 0.76, 3, 10, 0.012, 0.006)
		plates.append(KitMesh.put(strap, strap_mat, torso, Vector3.ZERO, "Strap"))
	for side in [-1.0, 1.0]:
		var a0: float = minf(side * 1.2, side * 1.82)
		var a1: float = maxf(side * 1.2, side * 1.82)
		var top := _body_patch(torso, a0, a1, 0.62, 0.95, 0.024, 0.01, plate_mat, 8, 4)
		top.name = "PauldronTop"
		plates.append(top)
		var middle := _body_patch(torso, a0 + 0.04, a1 - 0.04, 0.45, 0.7, 0.019, 0.01, plate_mat, 8, 3)
		middle.name = "PauldronMid"
		plates.append(middle)
		var low := _body_patch(torso, a0 + 0.08, a1 - 0.08, 0.28, 0.52, 0.014, 0.01, plate_mat, 8, 3)
		low.name = "PauldronLow"
		plates.append(low)
		var mark := MeshInstance3D.new()
		mark.name = "PauldronMark"
		var pm := PrismMesh.new()
		pm.size = Vector3(0.028, 0.02, 0.004)
		mark.mesh = pm
		mark.material_override = lamp_mat
		mark.transform = _facing(side * 1.5, 0.82, 0.034)
		mark.rotate_object_local(Vector3.FORWARD, PI)
		torso.add_child(mark)
		trims.append(mark)
	var back := _body_patch(torso, PI - 0.7, PI + 0.7, 0.25, 0.76, 0.016, 0.012, plate_mat)
	back.name = "Back"
	plates.append(back)
	if kind == KiwiArmour.Kind.SNIPER:
		return
	var pack := _box(torso, Vector3(0.15, 0.2, 0.075), _facing(PI, 0.5, 0.058), strap_mat)
	pack.name = "Pack"
	plates.append(pack)
	var bar := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.07, 0.012, 0.004)
	bar.mesh = bb
	bar.material_override = lamp_mat
	bar.position = Vector3(0.0, 0.065, 0.039)
	pack.add_child(bar)
	trims.append(bar)
	var radio := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(0.036, 0.065, 0.024)
	radio.mesh = rb
	radio.material_override = dark_mat
	radio.position = Vector3(0.09, 0.02, 0.012)
	pack.add_child(radio)
	plates.append(radio)
	var whip := KitMesh.rod(pack, Vector3(0.09, 0.055, 0.012), Vector3(0.09, 0.21, 0.012), 0.0025, strap_mat)
	plates.append(whip)
	chevron = MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.07, 0.04, 0.006)
	chevron.mesh = prism
	chevron.material_override = lamp_mat
	chevron.position = Vector3(0.0, -0.03, 0.041)
	chevron.visible = false
	pack.add_child(chevron)


func _greave(leg: Node3D, side: float) -> void:
	var knee := Vector3(side * 0.068, 0.108, 0.004)
	var ankle := Vector3(side * 0.062, 0.062, 0.017)
	var mid := (knee + ankle) * 0.5
	var shin := KitMesh.lathe(PackedVector2Array([Vector2(0.034, 0.024), Vector2(0.03, 0.026), Vector2(0.03, -0.024),
		Vector2(0.026, -0.024), Vector2(0.026, 0.02), Vector2(0.034, 0.024)]), 14, Callable(), PackedFloat32Array(),
		PackedInt32Array([0, 1, 2, 3, 4]))
	var guard := KitMesh.put(shin, plate_mat, leg, mid, "Greave")
	guard.basis = KitMesh.basis_along(knee - ankle)
	plates.append(guard)
	var cap := KitMesh.lathe(PackedVector2Array([Vector2(0.0, 0.03), Vector2(0.018, 0.026), Vector2(0.03, 0.014),
		Vector2(0.034, 0.0), Vector2(0.0, 0.0)]), 12, Callable(), PackedFloat32Array(), PackedInt32Array([3]))
	var pad := KitMesh.put(cap, strap_mat, leg, knee, "Knee")
	pad.basis = KitMesh.basis_along(knee - ankle)
	plates.append(pad)


func _cape(torso: Node3D) -> void:
	var hem := func(u: float) -> float:
		return 0.2 + 0.18 * KitMesh.hash01(u * 7.3, 1.7)
	var paint := func(u: float, v: float) -> Color:
		var pick := int(floor(KitMesh.hash01(floor(u * 9.0) * 3.1, floor(v * 6.0) * 5.7) * 4.0)) % 4
		return CAPE[pick]
	var mesh := KiwiBody.body_patch(0.7, TAU - 0.7, 0.2, 1.38, 28, 6, 0.03, 0.0, paint, hem)
	var mat := KitMesh.matte(Color.WHITE, 1.0, 0.0, true)
	mat.vertex_color_is_srgb = true
	KitMesh.put(mesh, mat, torso, Vector3.ZERO, "Cape")
