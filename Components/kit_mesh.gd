class_name KitMesh
extends RefCounted


static func lathe(profile: PackedVector2Array, segments: int, lift := Callable(),
		lift_weight := PackedFloat32Array(), sharp := PackedInt32Array(), pinch := Callable()) -> ArrayMesh:
	var n := profile.size()
	var seg_normal: Array[Vector2] = []
	for i in n - 1:
		var d := profile[i + 1] - profile[i]
		seg_normal.append(Vector2(-d.y, d.x).normalized())
	var point_normal: Array[Vector2] = []
	for i in n:
		if i == 0:
			point_normal.append(seg_normal[0])
		elif i == n - 1:
			point_normal.append(seg_normal[n - 2])
		else:
			point_normal.append((seg_normal[i - 1] + seg_normal[i]).normalized())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for s in n - 1:
		var ends := [s, s + 1]
		for e in 2:
			var i: int = ends[e]
			var n2: Vector2 = seg_normal[s] if sharp.has(i) else point_normal[i]
			var w: float = lift_weight[i] if i < lift_weight.size() else 1.0
			for k in segments + 1:
				var theta := TAU * float(k) / float(segments)
				var r := profile[i].x
				var y := profile[i].y
				if lift.is_valid():
					y += float(lift.call(theta)) * w
				if pinch.is_valid():
					r *= 1.0 + (float(pinch.call(theta)) - 1.0) * w
				var nrm := Vector3(n2.x * sin(theta), n2.y, -n2.x * cos(theta))
				if r < 0.0005:
					nrm = Vector3.UP if n2.y >= 0.0 else Vector3.DOWN
				st.set_normal(nrm.normalized())
				st.set_uv(Vector2(float(k) / float(segments), float(i) / float(n - 1)))
				st.add_vertex(Vector3(r * sin(theta), y, -r * cos(theta)))
		for k in segments:
			var a := base + k
			var b := base + segments + 1 + k
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
		base += 2 * (segments + 1)
	return st.commit()


static func patch(fn: Callable, u0: float, u1: float, v0: float, v1: float, nu: int, nv: int,
		inside: Vector3, thickness := 0.0, color := Callable(), inner := Callable()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	var nrms: Array[Vector3] = []
	var eu := (u1 - u0) * 0.002
	var ev := (v1 - v0) * 0.002
	for j in nv + 1:
		var v := lerpf(v0, v1, float(j) / float(nv))
		for i in nu + 1:
			var u := lerpf(u0, u1, float(i) / float(nu))
			var p: Vector3 = fn.call(u, v)
			var du: Vector3 = fn.call(u + eu, v) - fn.call(u - eu, v)
			var dv: Vector3 = fn.call(u, v + ev) - fn.call(u, v - ev)
			var nrm := du.cross(dv).normalized()
			if nrm.dot(p - inside) < 0.0:
				nrm = -nrm
			pts.append(p)
			nrms.append(nrm)
	var cols := (nu + 1)
	var layers := 2 if thickness > 0.0 else 1
	for layer in layers:
		for j in nv + 1:
			for i in nu + 1:
				var idx := j * cols + i
				var nrm := nrms[idx] if layer == 0 else -nrms[idx]
				var p := pts[idx] if layer == 0 else pts[idx] - nrms[idx] * thickness
				if layer == 1 and inner.is_valid():
					p = inner.call(lerpf(u0, u1, float(i) / float(nu)), lerpf(v0, v1, float(j) / float(nv)))
				st.set_normal(nrm)
				st.set_uv(Vector2(float(i) / float(nu), float(j) / float(nv)))
				if color.is_valid():
					st.set_color(color.call(lerpf(u0, u1, float(i) / float(nu)), lerpf(v0, v1, float(j) / float(nv))))
				st.add_vertex(p)
	var per_layer := (nu + 1) * (nv + 1)
	for layer in layers:
		var off := layer * per_layer
		for j in nv:
			for i in nu:
				var a := off + j * cols + i
				var b := a + cols
				if layer == 0:
					_quad(st, a, b, a + 1, b + 1)
				else:
					_quad(st, a, a + 1, b, b + 1)
	if thickness > 0.0:
		var ring: Array[int] = []
		for i in nu + 1:
			ring.append(i)
		for j in range(1, nv + 1):
			ring.append(j * cols + nu)
		for i in range(nu - 1, -1, -1):
			ring.append(nv * cols + i)
		for j in range(nv - 1, 0, -1):
			ring.append(j * cols)
		var start := 2 * per_layer
		var count := ring.size()
		for r in count:
			var idx := ring[r]
			var next := ring[(r + 1) % count]
			var edge_dir := (pts[next] - pts[idx]).normalized()
			var out := edge_dir.cross(nrms[idx]).normalized()
			if out.dot(pts[idx] - inside) < 0.0:
				out = -out
			for layer in 2:
				st.set_normal(out)
				st.set_uv(Vector2(float(r) / float(count), float(layer)))
				if color.is_valid():
					st.set_color(color.call(u0, v0))
				var q := pts[idx] if layer == 0 else pts[idx] - nrms[idx] * thickness
				if layer == 1 and inner.is_valid():
					var ii := idx % cols
					@warning_ignore("integer_division")
					var jj := idx / cols
					q = inner.call(lerpf(u0, u1, float(ii) / float(nu)), lerpf(v0, v1, float(jj) / float(nv)))
				st.add_vertex(q)
		for r in count:
			var a := start + 2 * r
			var b := start + 2 * ((r + 1) % count)
			_quad(st, a, a + 1, b, b + 1)
	return st.commit()


static func _quad(st: SurfaceTool, a: int, b: int, c: int, d: int) -> void:
	st.add_index(a)
	st.add_index(b)
	st.add_index(c)
	st.add_index(c)
	st.add_index(b)
	st.add_index(d)


static func on_ellipsoid(centre: Vector3, radii: Vector3, azimuth: float, elevation: float,
		basis := Basis.IDENTITY, squeeze := 0.0, back := 1.0, chest := 0.0) -> Vector3:
	var c := cos(elevation)
	var rz := radii.z * (1.0 - squeeze * maxf(0.0, -sin(elevation))) * lerpf(1.0, back, (1.0 - cos(azimuth)) * 0.5)
	rz *= 1.0 + chest * maxf(0.0, sin(elevation)) * maxf(0.0, cos(azimuth))
	var rx := radii.x * (1.0 - squeeze * 0.5 * maxf(0.0, -sin(elevation)))
	var local := Vector3(rx * sin(azimuth) * c, radii.y * sin(elevation), -rz * cos(azimuth) * c)
	return centre + basis * local


static func ellipsoid_patch(centre: Vector3, radii: Vector3, az0: float, az1: float, el0: float, el1: float,
		nu: int, nv: int, thickness := 0.0, basis := Basis.IDENTITY, color := Callable(),
		hem := Callable(), squeeze := 0.0, back := 1.0, chest := 0.0) -> ArrayMesh:
	var fn := func(u: float, v: float) -> Vector3:
		var e := v
		if hem.is_valid():
			e = lerpf(float(hem.call(u)), el1, (v - el0) / maxf(el1 - el0, 0.0001))
		return on_ellipsoid(centre, radii, u, e, basis, squeeze, back, chest)
	return patch(fn, az0, az1, el0, el1, nu, nv, centre, thickness, color)


static func matte(color: Color, roughness := 0.9, metallic := 0.0, vertex_colors := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = vertex_colors
	return m


static func glow(color: Color, energy := 1.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func put(mesh: Mesh, material: Material, parent: Node, at := Vector3.ZERO, name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = at
	## render layer 2: kit, which the lights a creature carries under its own kit must not light.
	mi.layers = 2
	if name != "":
		mi.name = name
	parent.add_child(mi)
	return mi


static func basis_along(y_axis: Vector3) -> Basis:
	var y := y_axis.normalized()
	var helper := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(helper).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func rod(parent: Node, from: Vector3, to: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = from.distance_to(to)
	cm.radial_segments = 8
	var mi := put(cm, material, parent, (from + to) * 0.5)
	mi.basis = basis_along(to - from)
	return mi


static func flat(points: PackedVector2Array, triangles: PackedInt32Array, scale := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in points:
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(0.5 + q.x * 0.5, 0.5 - q.y * 0.5))
		st.add_vertex(Vector3(q.x * scale, q.y * scale, 0.0))
	for i in triangles:
		st.add_index(i)
	return st.commit()


static func hash01(a: float, b: float) -> float:
	var h := sin(a * 12.9898 + b * 78.233) * 43758.5453
	return h - floor(h)
