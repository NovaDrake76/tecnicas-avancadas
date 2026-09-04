class_name BB
extends RigidBody3D

const AIR_DENSITY := 1.225
const DRAG_COEFF := 0.47
const BB_RADIUS := 0.003

@export_range(0.00001, 0.01, 0.00001, "or_greater") var bb_mass: float = 0.0002
@export_range(0.0, 0.01, 0.00001, "or_greater") var BackspinDrag: float = 0.0002
@export var lifetime: float = 5.0
@export var despawn_on_impact := true
## how far a bb landing on the world is heard. a bb makes no noise where it was FIRED, only where
## it lands, so a miss betrays what you were shooting at and never where you were shooting from:
## Wildlands' explosive rule, and the one that makes missing at range survivable. it is shorter
## than a walking footstep (14 m) on purpose, and like every other noise in this game it turns
## birds and raises nothing. the alarm still has exactly two sources.
@export var impact_hearing := 8.0
@export var mark_surface := true

@export var draw_trail: bool = true
@export var trail_color: Color = Color(0.4, 0.9, 1.0)
@export var trail_fade_time: float = 0.0
@export var trail_every: int = 1

var _area: float = PI * BB_RADIUS * BB_RADIUS
var _frame := 0
var _impacted := false
## the velocity going INTO the step that lands. by the time _integrate_forces reports the contact
## the solver has already taken the impact out of the body, and the energy read there was a tenth
## of what arrived: every shot bounced off the plate, seen in the probe before this existed.
var _incoming := Vector3.ZERO
var _crumb_mesh: SphereMesh
var _crumb_mat: StandardMaterial3D


func _ready() -> void:
	mass = bb_mass
	linear_damp = 0.0
	angular_damp = 0.0
	contact_monitor = true
	max_contacts_reported = 1
	if draw_trail:
		_build_crumb_assets()
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


## the first contact is the shot landing, everything after it is a bounce we do not care about.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _impacted or state.get_contact_count() == 0:
		return
	_impacted = true
	var hit_body := state.get_contact_collider_object(0)
	var point := state.get_contact_collider_position(0)
	var normal := state.get_contact_local_normal(0)
	## force the normal to oppose the incoming velocity, the engine's sign varies by body pair.
	if normal.dot(state.linear_velocity) > 0.0:
		normal = -normal
	## the energy the bb actually arrives with, after every metre of drag it flew through. this is
	## the number that decides whether a shot beats armour, and it is the same number the bench
	## draws as impact at range, so what the bench promises is what the plate feels.
	var arriving := _incoming if _incoming.length_squared() > 0.0 else state.linear_velocity
	var energy := 0.5 * bb_mass * arriving.length_squared()
	_on_impact.call_deferred(point, normal, hit_body, energy)


func _on_impact(point: Vector3, normal: Vector3, hit_body: Object, energy: float) -> void:
	var world := get_tree().current_scene
	ImpactFx.spawn(world, point, normal)

	var target := hit_body != null and is_instance_valid(hit_body) and hit_body.has_method("take_bb_hit")
	if target:
		hit_body.take_bb_hit(1.0, point, energy)
		## asked AFTER the hit, so a kiwi that this bb just put down answers yes and the marker
		## comes up red. a range target has no such answer and gets the plain one.
		Run.report_hit(hit_body.has_method("is_down") and hit_body.is_down())

	## what it landed on says what it sounds like; the birds and the targets answer for themselves
	if not target:
		Sfx.play("bb_" + String(Sfx.surface_of(hit_body)), point)
		_heard_at(point)

	## decals belong on static world surfaces only, a hole stamped on a kiwi hangs in the air once it moves.
	if mark_surface and not target:
		BulletHoles.mark(point, normal)
	if despawn_on_impact:
		queue_free()


## the birds walk over to the hole, the way they do for a thrown magazine. they are told about the
## IMPACT and nothing else: no bird learns anything about the shooter from a shot going past it.
func _heard_at(point: Vector3) -> void:
	if impact_hearing <= 0.0:
		return
	for node in get_tree().get_nodes_in_group("kiwi"):
		var bird := node as Node3D
		if bird == null or not bird.has_method("investigate"):
			continue
		if bird.global_position.distance_to(point) <= impact_hearing:
			bird.investigate(point)


func _physics_process(_delta: float) -> void:
	_incoming = linear_velocity
	if draw_trail:
		_frame += 1
		if _frame % maxi(1, trail_every) == 0:
			_drop_crumb()

	var vel := linear_velocity
	var speed := vel.length()
	if speed < 0.01:
		return

	var dir := vel / speed

	var drag_mag := 0.5 * AIR_DENSITY * DRAG_COEFF * _area * speed * speed
	apply_central_force(-dir * drag_mag)

	var spin_axis := dir.cross(Vector3.UP)
	if spin_axis.length_squared() > 0.000001:
		spin_axis = spin_axis.normalized()
		var lift_dir := spin_axis.cross(dir).normalized()
		var lift_mag := sqrt(speed) * BackspinDrag
		apply_central_force(lift_dir * lift_mag)


## the same flight, on paper: drag, backspin lift and gravity integrated in the vertical plane, with the
## constants and the lift formula this node uses in _physics_process. the bench asks this so the bars it
## shows are the game's own physics and not a second opinion of it. returns metres, seconds and joules.
## reach is how far the bb flies before it has dropped half a metre below the line of fire.
static func flight(speed: float, mass_kg: float, backspin: float, at_distance := 30.0) -> Dictionary:
	var area := PI * BB_RADIUS * BB_RADIUS
	var dt := 1.0 / 240.0
	var pos := Vector2.ZERO
	var vel := Vector2(speed, 0.0)
	var t := 0.0
	var reach := -1.0
	var at := {}
	var m := maxf(mass_kg, 0.00001)
	while t < 4.0:
		var v := vel.length()
		if v < 5.0:
			break
		var dir := vel / v
		var drag := 0.5 * AIR_DENSITY * DRAG_COEFF * area * v * v
		var lift := sqrt(v) * backspin
		var accel := -dir * (drag / m) + Vector2(-dir.y, dir.x) * (lift / m) + Vector2(0.0, -9.81)
		vel += accel * dt
		var next := pos + vel * dt
		if at.is_empty() and next.x >= at_distance:
			var frac := (at_distance - pos.x) / maxf(next.x - pos.x, 0.000001)
			var y := lerpf(pos.y, next.y, frac)
			var vv := vel.length()
			at = {"drop": -y, "time": t + dt * frac, "impact": 0.5 * m * vv * vv, "speed": vv}
		pos = next
		t += dt
		if reach < 0.0 and pos.y < -0.5:
			reach = pos.x
	if reach < 0.0:
		reach = pos.x
	return {
		"v0": speed,
		"reach": reach,
		"drop": float(at.get("drop", 99.0)),
		"time": float(at.get("time", 9.0)),
		"impact": float(at.get("impact", 0.0)),
		"speed_at": float(at.get("speed", 0.0)),
		"distance": at_distance,
	}


func _build_crumb_assets() -> void:
	_crumb_mesh = SphereMesh.new()
	_crumb_mesh.radius = 0.12
	_crumb_mesh.height = 0.24
	_crumb_mesh.radial_segments = 6
	_crumb_mesh.rings = 3

	_crumb_mat = StandardMaterial3D.new()
	_crumb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crumb_mat.albedo_color = trail_color
	_crumb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _drop_crumb() -> void:
	var m := MeshInstance3D.new()
	m.mesh = _crumb_mesh
	m.material_override = _crumb_mat if trail_fade_time <= 0.0 else _crumb_mat.duplicate()
	get_tree().current_scene.add_child(m)
	m.global_position = global_position

	if trail_fade_time > 0.0:
		var tw := m.create_tween()
		tw.tween_property(m.material_override, "albedo_color:a", 0.0, trail_fade_time)
		tw.tween_callback(m.queue_free)