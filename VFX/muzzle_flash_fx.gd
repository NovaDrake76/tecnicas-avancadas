class_name MuzzleFlashFx
extends Node3D

## layered muzzle effect, crossed additive cards plus a brief point light plus a forward spray.
## GAS is the airsoft-correct default, FLASH is the arcade fireball if you want it instead.

enum Style { GAS, FLASH }

const GAS_COLOR := Color(0.86, 0.9, 0.94)
const FLASH_COLOR := Color(1.0, 0.6, 0.2)

static var _card_quad: QuadMesh
static var _card_mats := {}
static var _spark_quad: QuadMesh
static var _spark_pms := {}
static var _textures := {}


## a soft radial blob for gas, a hot core with six spikes for a fireball.
static func _tex(style: int) -> ImageTexture:
	if _textures.has(style):
		return _textures[style]
	const N := 64
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var dx := (float(x) + 0.5) / N * 2.0 - 1.0
			var dy := (float(y) + 0.5) / N * 2.0 - 1.0
			var r := sqrt(dx * dx + dy * dy)
			var a := 0.0
			if style == Style.FLASH:
				var core: float = exp(-pow(r * 3.1, 2.0))
				var ang := atan2(dy, dx)
				var lobe: float = pow(maxf(0.0, cos(ang * 6.0)), 22.0) * exp(-pow(r * 1.35, 2.6))
				a = clampf(core + lobe * 0.85, 0.0, 1.0)
			else:
				a = clampf(exp(-pow(r * 1.9, 2.2)), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_textures[style] = ImageTexture.create_from_image(img)
	return _textures[style]


static func _card_mat(color: Color, intensity: float, style: int) -> StandardMaterial3D:
	var key := "%s|%.2f|%d" % [color.to_html(false), intensity, style]
	if not _card_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(color.r, color.g, color.b, 0.9 * intensity)
		## an untextured additive quad renders as a glowing square, the texture is what gives it a shape.
		m.albedo_texture = _tex(style)
		m.emission_enabled = true
		m.emission = color
		m.emission_texture = _tex(style)
		m.emission_energy_multiplier = 3.0 * intensity
		m.disable_receive_shadows = true
		_card_mats[key] = m
	return _card_mats[key]


static func _spark_pm(color: Color, style: int) -> ParticleProcessMaterial:
	var key := "%s|%d" % [color.to_html(false), style]
	if not _spark_pms.has(key):
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		pm.direction = Vector3(0, 0, -1)
		if style == Style.FLASH:
			pm.spread = 18.0
			pm.initial_velocity_min = 6.0
			pm.initial_velocity_max = 11.0
			pm.damping_min = 4.0
			pm.damping_max = 8.0
			pm.scale_min = 0.3
			pm.scale_max = 0.6
		else:
			## venting gas, slower and wider than sparks, and buoyant rather than falling.
			pm.spread = 34.0
			pm.initial_velocity_min = 1.2
			pm.initial_velocity_max = 2.8
			pm.gravity = Vector3(0.0, 0.5, 0.0)
			pm.damping_min = 3.0
			pm.damping_max = 6.0
			pm.scale_min = 0.6
			pm.scale_max = 1.4
		pm.color = Color(color.r * 1.8, color.g * 1.8, color.b * 1.8, 1.0)
		_spark_pms[key] = pm
	return _spark_pms[key]


## build the caches at load so the first shot does not compile pipelines mid game.
static func warm() -> void:
	if _card_quad == null:
		_card_quad = QuadMesh.new()
		_card_quad.size = Vector2(0.16, 0.16)
		_spark_quad = QuadMesh.new()
		_spark_quad.size = Vector2(0.03, 0.03)
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		smat.albedo_color = Color.WHITE
		smat.disable_receive_shadows = true
		_spark_quad.material = smat
	_card_mat(GAS_COLOR, 0.4, Style.GAS)
	_spark_pm(GAS_COLOR, Style.GAS)


static func spawn(world: Node, at: Vector3, dir: Vector3, color := GAS_COLOR,
		scale_mult := 1.0, intensity := 0.4, style := Style.GAS) -> void:
	if world == null:
		return
	if _card_quad == null:
		warm()

	var root := Node3D.new()
	world.add_child(root)
	root.global_position = at
	if dir.length() > 0.01:
		var d := dir.normalized()
		var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.985 else Vector3.FORWARD
		root.look_at(at + d, up)
	root.scale = Vector3.ONE * scale_mult

	var cards := Node3D.new()
	root.add_child(cards)
	## a random roll per shot so rapid fire never looks stamped from the same frame.
	cards.rotation.z = randf() * TAU
	for i in 2:
		var card := MeshInstance3D.new()
		card.mesh = _card_quad
		card.material_override = _card_mat(color, intensity, style)
		card.rotation.z = float(i) * PI * 0.5
		card.scale = Vector3.ONE * randf_range(0.8, 1.2)
		cards.add_child(card)

	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 1.6
	light.light_energy = 4.0 * intensity
	light.shadow_enabled = false
	root.add_child(light)

	var puff := GPUParticles3D.new()
	puff.amount = 8
	puff.lifetime = 0.32 if style == Style.GAS else 0.18
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.emitting = true
	puff.process_material = _spark_pm(color, style)
	puff.draw_pass_1 = _spark_quad
	root.add_child(puff)

	var fade := 0.16 if style == Style.GAS else 0.06
	var grow := 2.2 if style == Style.GAS else 1.5

	## fades tween node properties only, the materials are shared between every shot.
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(light, "light_energy", 0.0, fade * 0.5).set_ease(Tween.EASE_OUT)
	tw.tween_property(cards, "scale", cards.scale * grow, fade).set_ease(Tween.EASE_OUT)
	for card in cards.get_children():
		tw.tween_property(card, "transparency", 1.0, fade)
	tw.set_parallel(false)
	## a dead light must not sit in the cluster for the rest of the node's life.
	tw.tween_callback(func() -> void: light.visible = false)

	root.get_tree().create_timer(puff.lifetime + 0.25).timeout.connect(root.queue_free)
