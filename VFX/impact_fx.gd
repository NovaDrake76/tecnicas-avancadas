class_name ImpactFx
extends Node3D

## procedural impact, a spark burst plus a one frame flash light oriented to the surface.
## every render resource is a cached static so a hit never allocates a mesh or material.

const BB_COLOR := Color(1.0, 0.62, 0.12)

static var _spark_quad: QuadMesh
static var _spark_mat: StandardMaterial3D
static var _spark_pms := {}
static var _flash_mesh: SphereMesh
static var _flash_mats := {}


static func _spark_pm(color: Color) -> ParticleProcessMaterial:
	var key := color.to_html(false)
	if not _spark_pms.has(key):
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		pm.direction = Vector3(0, 0, -1)
		pm.spread = 55.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 5.0
		pm.gravity = Vector3(0, -12.0, 0)
		pm.damping_min = 2.0
		pm.damping_max = 5.0
		pm.scale_min = 0.4
		pm.scale_max = 1.0
		pm.color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, 1.0)
		_spark_pms[key] = pm
	return _spark_pms[key]


static func _flash_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html(false)
	if not _flash_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(color.r, color.g, color.b, 0.92)
		m.disable_receive_shadows = true
		_flash_mats[key] = m
	return _flash_mats[key]


## build the caches at load so the first hit does not compile pipelines mid game.
## keep the colour set closed, a continuous colour would grow the cache forever.
static func warm() -> void:
	if _spark_quad == null:
		_spark_quad = QuadMesh.new()
		_spark_quad.size = Vector2(0.035, 0.035)
		_spark_mat = StandardMaterial3D.new()
		_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		## without this the process material's colour is thrown away and every spark renders white.
		_spark_mat.vertex_color_use_as_albedo = true
		_spark_mat.albedo_color = Color.WHITE
		_spark_mat.disable_receive_shadows = true
		_spark_quad.material = _spark_mat
		_flash_mesh = SphereMesh.new()
		_flash_mesh.radius = 0.09
		_flash_mesh.height = 0.18
	_spark_pm(BB_COLOR)
	_flash_mat(BB_COLOR)


static func spawn(world: Node, at: Vector3, normal: Vector3, color := BB_COLOR) -> void:
	if world == null:
		return
	if _spark_quad == null:
		warm()

	var root := Node3D.new()
	world.add_child(root)
	root.global_position = at

	## point local -Z along the surface normal so sparks spray off it, not into it.
	if normal.length() > 0.01:
		var n := normal.normalized()
		var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.985 else Vector3.FORWARD
		root.look_at(at + n, up)

	var sparks := GPUParticles3D.new()
	sparks.amount = 10
	sparks.lifetime = 0.3
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.emitting = true
	sparks.process_material = _spark_pm(color)
	sparks.draw_pass_1 = _spark_quad
	root.add_child(sparks)

	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 2.5
	light.light_energy = 2.5
	light.shadow_enabled = false
	root.add_child(light)

	## a dead light must not sit in the cluster for the rest of the node's life.
	var tw := root.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.09).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: light.visible = false)

	root.get_tree().create_timer(sparks.lifetime + 0.25).timeout.connect(root.queue_free)


static func flash(world: Node, at: Vector3, color: Color, scale_to := 1.6, duration := 0.12) -> void:
	if world == null:
		return
	if _flash_mesh == null:
		warm()
	var fl := MeshInstance3D.new()
	fl.mesh = _flash_mesh
	fl.material_override = _flash_mat(color)
	world.add_child(fl)
	fl.global_position = at
	fl.scale = Vector3.ONE * 0.4
	var tw := fl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(fl, "scale", Vector3.ONE * scale_to, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(fl, "transparency", 1.0, duration)
	tw.set_parallel(false)
	tw.tween_callback(fl.queue_free)
