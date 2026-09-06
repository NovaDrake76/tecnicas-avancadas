class_name FragGrenade
extends Throwable

## the loud option. a fuse, a bounce, and a lamp that blinks faster the closer it gets to going off.
##
## everything else the player carries is quiet on purpose: a bb that misses is silent, a takedown
## tells nobody, taking an objective tells nobody. this is the one thing in the kit that ENDS the
## infiltration, and it says so out loud -- the blast raises the compound the way the sabotage charge
## does, because a bomb the player set on a fuse they could watch is a thing the player did. that is
## the whole of its design: it is not a better gun, it is a decision to stop being quiet, and it is
## bought with points so the decision is made at the bench as well as in the field.
##
## it draws NO blast circle, which is the one place it deliberately parts company with the mortar
## shell. a shell is fired at you by somebody you cannot see, so the ring on the ground is the only
## warning there is and the game owes you one. a grenade is a thing you chose, threw, and watched
## land: you know what it does because you bought it and the bench told you, and painting its radius
## on the grass turns your own tool into a diagram. Nathan's call, and it is the same reasoning that
## took the words off the middle of the screen everywhere else. what is left is the object and its
## lamp -- where it is and how long you have -- which is what a grenade on the floor has always
## said.

const FIRE := Color(1.0, 0.72, 0.25)
const SMOKE := Color(0.32, 0.29, 0.26)
const SHELL := Color(0.18, 0.21, 0.14)
## how much bigger than life the model is drawn. the collision is not scaled with it.
const DRAWN := 1.6

## seconds from the throw. long enough to be thrown properly, short enough that a bird cannot walk
## out of it, and short enough that a bad throw comes back at you, which is the price of the tool.
@export var fuse := 3.2
## the circle. a bird inside it with nothing in the way goes down; a player inside it is hurt in
## proportion to how near the middle they were.
@export var radius := 5.0
@export var damage := 70.0
## what a wall between you and it is worth. harsher than the mortar shell's 0.35: a shell comes down
## from above and a grenade does not, so cover at ground level counts for more against this one.
@export var cover_factor := 0.3

## the belt that threw it, handed over rather than looked up: a grenade thrown by the operative on
## the other machine belongs to a belt that has deliberately left every group this machine reads.
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
	## it bounces off a wall and rolls a little, which is what makes throwing one through a doorway
	## a skill and throwing one at a wall a mistake. more bounce than this and it comes back off
	## everything; less and it sticks where it lands and the fuse stops meaning anything.
	bouncy.bounce = 0.34
	bouncy.friction = 0.75
	physics_material_override = bouncy
	super()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	## the collision is the real thing, 5 cm across. what it LOOKS like is another question and the
	## answer is below: this project already keeps the two apart on purpose, the bb's mesh being
	## sixteen times its physical radius so it can be seen at all.
	ball.radius = 0.05
	shape.shape = ball
	add_child(shape)

	var olive := StandardMaterial3D.new()
	olive.albedo_color = SHELL
	olive.roughness = 0.75
	olive.metallic = 0.35
	var mi := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	## drawn HALF AGAIN as big as a real grenade. photographed at true size it was a dark speck on
	## grass at six metres, which is nothing for the person who threw it and worse for the teammate
	## standing where it landed. the pickups do the same and for the same reason.
	body.radius = 0.045 * DRAWN
	body.height = 0.135 * DRAWN
	body.radial_segments = 10
	body.rings = 4
	mi.mesh = body
	mi.material_override = olive
	add_child(mi)
	## the lever, so it reads as a grenade and not as a pebble at the one size it is ever seen at.
	var lever := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.012, 0.09, 0.02) * DRAWN
	lever.mesh = bar
	lever.material_override = olive
	lever.position = Vector3(0.05 * DRAWN, 0.01, 0.0)
	add_child(lever)

	## the fuse has to be visible on a thing this small from across a yard, and a blink that speeds
	## up says how long is left without a number. the ring says the same thing on the ground; this
	## says it at the grenade, which is where the eye goes while it is still in the air.
	##
	## it is a LAMP and a light, not a light alone: an omni light of this size is nothing at all in
	## the middle of a sunlit field, and what actually reads is a small unshaded blob that is its own
	## colour whatever the sun is doing. the laser kiwi's eyes are built the same way for the same
	## reason. the light is what puts it on the wall of a shed at night.
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


## the clock and the blink run on EVERY copy, because a teammate has to be able to see how long is
## left on a grenade somebody else threw. only the thrower's copy is allowed to decide the MOMENT it
## goes off: a bouncing body does not come to rest in the same place twice, and two machines each
## detonating their own would put the blast in two places.
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


## it clatters off what it hits, on every machine, because the sound is how a player behind cover
## learns that a grenade came round the wall at them. the guard is not the table's cooldown doing the
## same job twice: a grenade settling reports a contact every tick, and what that would make is a
## buzz rather than a series of bounces.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _gone or state.get_contact_count() == 0:
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now - _bounced < 0.14 or state.linear_velocity.length() < 1.8:
		return
	_bounced = now
	Sfx.play(&"frag_bounce", state.get_contact_collider_position(0))
	_landed = true


## the thrower's copy went off. everybody is shown it at the same spot, and the host is the only one
## that decides what it did.
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
		## an explosion is not a noise, it is an event: the compound knows, and it knows where. the
		## same rule the sabotage charge follows, and the reason this is the loud option.
		Alarm.raise_alarm(at)
	queue_free()


func _pop(at: Vector3) -> void:
	var world := get_tree().current_scene
	if world == null:
		return
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


## a bird inside the circle with nothing between it and the blast goes down, whatever it is wearing:
## a plate stops a bb because a bb arrives with an energy, and this does not arrive with an energy.
## a bird behind a crate is saved by the crate, which is the same cover the player uses.
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
	## it does not know whose side anybody is on. two operatives who sheltered behind the same wall
	## made that decision together, and two who did not made the other one together.
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
