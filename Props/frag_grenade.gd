class_name FragGrenade
extends Throwable


const FIRE := Color(1.0, 0.72, 0.25)
const SMOKE := Color(0.32, 0.29, 0.26)
const SHELL := Color(0.18, 0.21, 0.14)
## how much bigger than life it is drawn; the collision is deliberately not scaled with it.
const DRAWN := 1.6

## seconds from the throw.
@export var fuse := 3.2
## the circle.
@export var radius := 5.0
@export var damage := 70.0
## what a wall between you and it is worth.
@export var cover_factor := 0.3
## how hard the blast throws loose props, per kilogram; they are scattered well past the hurt radius.
@export var blast_shove := 7.0

var belt: UtilityBelt

var _t := 0.0
var _gone := false
var _light: OmniLight3D
var _blip: MeshInstance3D
var _blink := 0.0
var _bounced := 0.0


func _ready() -> void:
	add_to_group("frag_grenade")
	mass = 0.4
	var bouncy := PhysicsMaterial.new()
	bouncy.bounce = 0.34
	bouncy.friction = 0.75
	physics_material_override = bouncy
	super()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.05
	shape.shape = ball
	add_child(shape)

	var olive := StandardMaterial3D.new()
	olive.albedo_color = SHELL
	olive.roughness = 0.75
	olive.metallic = 0.35
	var mi := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.045 * DRAWN
	body.height = 0.135 * DRAWN
	body.radial_segments = 10
	body.rings = 4
	mi.mesh = body
	mi.material_override = olive
	add_child(mi)
	var lever := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.012, 0.09, 0.02) * DRAWN
	lever.mesh = bar
	lever.material_override = olive
	lever.position = Vector3(0.05 * DRAWN, 0.01, 0.0)
	add_child(lever)

	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glass.albedo_color = Color(1.0, 0.28, 0.18, 1.0)
	glass.disable_receive_shadows = true
	_blip = MeshInstance3D.new()
	var bead := SphereMesh.new()
	bead.radius = 0.035
	bead.height = 0.07
	bead.radial_segments = 8
	bead.rings = 4
	_blip.mesh = bead
	_blip.material_override = glass
	_blip.position = Vector3(0.0, 0.075 * DRAWN, 0.0)
	_blip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_blip)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.3, 0.2)
	_light.omni_range = 3.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)


func _physics_process(delta: float) -> void:
	if _gone:
		return
	_t += delta
	var u := clampf(_t / maxf(fuse, 0.05), 0.0, 1.0)
	_blink += delta * lerpf(4.0, 22.0, u)
	var beat := maxf(sin(_blink), 0.0)
	_light.light_energy = 2.4 * beat
	_blip.scale = Vector3.ONE * (0.55 + 0.75 * beat)
	_blip.transparency = 1.0 - (0.35 + 0.65 * beat)
	if mine and u >= 1.0:
		burst()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _gone or state.get_contact_count() == 0:
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now - _bounced < 0.14 or state.linear_velocity.length() < 1.8:
		return
	_bounced = now
	Sfx.play(&"frag_bounce", state.get_contact_collider_position(0))
	_landed = true


func burst() -> void:
	if _gone:
		return
	var at := global_position
	if belt != null and is_instance_valid(belt):
		belt.report_burst(self, at)
	burst_at(at, multiplayer.is_server())


func burst_at(at: Vector3, do_damage: bool) -> void:
	if _gone:
		return
	_gone = true
	global_position = at
	_pop(at)
	if do_damage:
		_hurt(at)
		Alarm.raise_alarm(at)
	queue_free()


func _pop(at: Vector3) -> void:
	var world := get_tree().current_scene
	if world == null:
		return
	LooseProp.blast(get_tree(), at, radius * 1.6, blast_shove)
	BurstFx.spawn(world, at + Vector3.UP * 0.25, FIRE, 30, 9.0, 0.4)
	BurstFx.spawn(world, at + Vector3.UP * 0.4, SMOKE, 26, 5.0, 1.1)
	BurstFx.spawn(world, at + Vector3.UP * 0.15, Color(0.55, 0.5, 0.4), 24, 11.0, 0.7)
	ImpactFx.flash(world, at + Vector3.UP * 0.4, FIRE, 5.0, 0.13)
	var light := LaserEyes.make_light(FIRE, 11.0)
	light.light_energy = 8.0
	world.add_child(light)
	light.global_position = at + Vector3.UP * 0.8
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.28)
	tw.tween_callback(light.queue_free)
	Sfx.play(&"frag_blast", at)
	Sfx.hdr(at, 8.0, 24.0)


func _hurt(at: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group("kiwi"):
		var bird := node as Node3D
		if bird == null or not is_instance_valid(bird):
			continue
		if bird.global_position.distance_to(at) > radius:
			continue
		var eye := bird.global_position + Vector3.UP * 0.3
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.25, eye, 1)
		if not space.intersect_ray(query).is_empty():
			continue
		if bird.has_method("take_bb_hit"):
			bird.take_bb_hit(999.0, at, -1.0)
	for who in Player.all(get_tree()):
		_hurt_player(who, at)


func _hurt_player(player: Player, at: Vector3) -> void:
	if player == null or not is_instance_valid(player) or not player.is_alive():
		return
	var flat := player.global_position.distance_to(at)
	if flat > radius:
		return
	var dmg := damage * pow(1.0 - flat / radius, 0.7)
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.25, VisionCone.sight_point(player), 1)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		dmg *= cover_factor
	if dmg > 0.5:
		player.take_laser_hit(dmg, at)


func time_left() -> float:
	return maxf(0.0, fuse - _t)
