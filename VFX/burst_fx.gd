class_name BurstFx
extends Node3D

## an omnidirectional puff of tumbling billboard bits, for a target coming apart.
## mesh and per colour materials are cached statics so a burst allocates no render resources.

static var _quad: QuadMesh
static var _pms := {}


static func _pm(color: Color, speed: float) -> ParticleProcessMaterial:
	var key := "%s|%.1f" % [color.to_html(false), speed]
	if not _pms.has(key):
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.12
		pm.direction = Vector3(0, 1, 0)
		## a full hemisphere of spread is what makes it a puff rather than a spray.
		pm.spread = 180.0
		pm.initial_velocity_min = speed * 0.4
		pm.initial_velocity_max = speed
		pm.gravity = Vector3(0, -5.0, 0)
		pm.damping_min = 1.5
		pm.damping_max = 3.5
		pm.scale_min = 0.6
		pm.scale_max = 1.3
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -220.0
		pm.angular_velocity_max = 220.0

		## the fade is a colour ramp on the process material, not a tween on a shared material.
		var grad := Gradient.new()
		grad.set_color(0, Color(color.r, color.g, color.b, 1.0))
		grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
		var ramp := GradientTexture1D.new()
		ramp.gradient = grad
		pm.color_ramp = ramp

		_pms[key] = pm
	return _pms[key]


static func warm() -> void:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(0.05, 0.05)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color.WHITE
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_receive_shadows = true
		_quad.material = m


static func spawn(world: Node, at: Vector3, color: Color, count := 16,
		speed := 3.0, lifetime := 0.9) -> void:
	if world == null:
		return
	if _quad == null:
		warm()

	var parts := GPUParticles3D.new()
	parts.amount = maxi(1, count)
	parts.lifetime = lifetime
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.emitting = true
	parts.process_material = _pm(color, speed)
	parts.draw_pass_1 = _quad
	world.add_child(parts)
	parts.global_position = at

	parts.get_tree().create_timer(lifetime + 0.3).timeout.connect(parts.queue_free)
