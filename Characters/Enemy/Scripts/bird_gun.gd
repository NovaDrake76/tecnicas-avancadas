class_name BirdGun
extends Node3D


## off for a bird whose eyes do something else: the sniper's are the slug or nothing.
@export var enabled := true
## what one bolt costs the player.
@export var damage := 5.0
## bolts per burst.
@export var rounds := 2
@export var round_gap := 0.12
@export var burst_gap := 0.9
@export var reach := 30.0
## the chance one bolt lands on a standing player in the open at point blank; everything else scales it down.
@export_range(0.0, 1.0) var hit_base := 0.7
## bolts let out per pull; one for a sentry, several for a rusher's scatter.
@export var pellets := 1
@export var pellet_spread := 0.0
## the bolt's light: the green of every kiwi's eyes.
@export var colour := Color(0.25, 1.0, 0.3)
## where a bolt leaves when the model has no eye bones to read: the beak, in the bird's own frame.
@export var muzzle := Vector3(0.0, 0.42, -0.32)

const STANCE_FACTOR := [1.0, 0.55, 0.3]
const SPRINT_FACTOR := 2.0
const DUCK_FACTOR := 0.5
const DART_LENGTH := 2.2
const DART_SPEED := 70.0
const CORE_RADIUS := 0.018
const GLOW_RADIUS := 0.06

static var _cyl: CylinderMesh
static var _sphere: SphereMesh
static var _mats := {}

var _kiwi: Kiwi
var _skeleton: Skeleton3D
var _eye_l := -1
var _eye_r := -1
var _timer := 0.0
var _left := 0
var _shots := 0
var _hits := 0
var _last_chance := 0.0
var _glow_eyes: Array[MeshInstance3D] = []
var _glow_light: OmniLight3D
var _lit := false


func _ready() -> void:
	_kiwi = get_parent() as Kiwi
	if _kiwi == null:
		return
	_skeleton = _kiwi.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton == null:
		return
	for i in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(i).to_lower()
		if bone_name.begins_with("eye.l"):
			_eye_l = i
		elif bone_name.begins_with("eye.r"):
			_eye_r = i
	if _has_laser_eyes() or _eye_l < 0 or _eye_r < 0:
		return
	_warm()
	for _i in 2:
		var eye := MeshInstance3D.new()
		eye.mesh = _sphere
		eye.material_override = _mat_for(colour)["eye"]
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.top_level = true
		eye.visible = false
		add_child(eye)
		_glow_eyes.append(eye)
	_glow_light = LaserEyes.make_light(colour, 1.8)
	_glow_light.light_cull_mask = 1
	_glow_light.light_energy = 1.2
	_glow_light.top_level = true
	_glow_light.visible = false
	add_child(_glow_light)


func _has_laser_eyes() -> bool:
	return _kiwi != null and "eyes" in _kiwi and _kiwi.eyes != null and is_instance_valid(_kiwi.eyes)


const GLOW_FAR := 60.0


func _process(_delta: float) -> void:
	if _glow_eyes.is_empty():
		return
	_lit = enabled and _kiwi != null and _kiwi.is_hunting() and not _kiwi.is_down()
	var shown := _lit and _glow_in_view()
	if not shown and not _glow_light.visible:
		return
	for i in 2:
		var eye := _glow_eyes[i]
		eye.visible = shown
		if shown:
			eye.global_position = _eye_point(_eye_l if i == 0 else _eye_r)
	_glow_light.visible = shown
	if shown:
		_glow_light.global_position = muzzle_point()


func _glow_in_view() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return true
	var at := _kiwi.global_position + Vector3.UP * 0.4
	return cam.global_position.distance_squared_to(at) < GLOW_FAR * GLOW_FAR and cam.is_position_in_frustum(at)


func eyes_lit() -> bool:
	if _has_laser_eyes():
		return _kiwi.eyes.is_lit()
	return _lit


func tick(delta: float, target: Node3D, may_fire: bool) -> void:
	if not enabled:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if _left > 0:
		if target != null and is_instance_valid(target):
			_shoot(target)
		_left -= 1
		_timer = round_gap if _left > 0 else burst_gap
		return
	if not may_fire or target == null or not is_instance_valid(target):
		return
	_left = rounds


func hit_chance(target: Node3D) -> float:
	if _kiwi == null or target == null or not is_instance_valid(target):
		return 0.0
	var eye := _kiwi.global_position + Vector3.UP * 0.35
	var at := VisionCone.sight_point(target)
	var d := eye.distance_to(at)
	if d > reach:
		return 0.0
	var clear := clear_fraction(target)
	if clear <= 0.0:
		return 0.0
	var stance: float = STANCE_FACTOR[clampi(VisionCone.stance_of(target), 0, 2)]
	var far := clampf(1.0 - 0.5 * d / reach, 0.2, 1.0)
	var moving := SPRINT_FACTOR if target.has_method("is_running") and target.is_running() else 1.0
	var duck := DUCK_FACTOR if _kiwi.is_suppressed() else 1.0
	return clampf(hit_base * stance * far * clear * moving * duck, 0.0, 0.95)


func clear_fraction(target: Node3D) -> float:
	var eye := _kiwi.global_position + Vector3.UP * 0.35
	var top := VisionCone.sight_point(target)
	var low := target.global_position + Vector3.UP * 0.35
	var mid := (top + low) * 0.5
	var space := get_world_3d().direct_space_state
	var n := 0
	for point in [top, mid, low]:
		var query := PhysicsRayQueryParameters3D.create(eye, point, 1)
		query.exclude = [_kiwi.get_rid()]
		if space.intersect_ray(query).is_empty():
			n += 1
	return float(n) / 3.0


func muzzle_point() -> Vector3:
	if _kiwi == null:
		return global_position
	if "eyes" in _kiwi and _kiwi.eyes != null and is_instance_valid(_kiwi.eyes):
		return _kiwi.eyes.between_eyes()
	if _skeleton != null and _eye_l >= 0 and _eye_r >= 0:
		return (_eye_point(_eye_l) + _eye_point(_eye_r)) * 0.5
	return _kiwi.global_transform * muzzle


func _eye_point(bone: int) -> Vector3:
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(bone)).origin


func _shoot(target: Node3D) -> void:
	_kiwi.fire_noise()
	var from := muzzle_point()
	var aim := VisionCone.sight_point(target)
	var chance := hit_chance(target)
	_last_chance = chance
	var landed := 0
	for _p in pellets:
		var hit := randf() < chance
		var to := aim
		if pellet_spread > 0.0:
			to += Vector3(randf_range(-pellet_spread, pellet_spread), randf_range(-pellet_spread, pellet_spread), randf_range(-pellet_spread, pellet_spread))
		if not hit:
			var side := (aim - from).cross(Vector3.UP).normalized()
			to += side * randf_range(0.4, 1.4) * (1.0 if randf() < 0.5 else -1.0) + Vector3.UP * randf_range(-0.3, 0.9)
		to = from + (to - from).normalized() * reach
		_net_shot.rpc(from, to, hit)
		_shots += 1
		if hit:
			_hits += 1
			landed += 1
	if multiplayer.is_server() and target.has_method("note_shot_at"):
		target.note_shot_at(landed > 0)
	if multiplayer.is_server() and landed > 0 and target.has_method("take_laser_hit"):
		target.take_laser_hit(damage * float(landed), _kiwi.global_position)


@rpc("authority", "call_local", "unreliable")
func _net_shot(from: Vector3, to: Vector3, _hit: bool) -> void:
	Sfx.play(&"kiwi_blaster", from, 0.0, 1.0, true)
	var world := get_tree().current_scene
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 3)
	if _kiwi != null:
		query.exclude = [_kiwi.get_rid()]
	var found := space.intersect_ray(query)
	var end := to
	if not found.is_empty():
		end = found["position"]
		var body := found["collider"] as Node
		if body != null and not body.has_method("take_laser_hit"):
			Sfx.play(&"laser_hit", end)
			BurstFx.spawn(world, end, colour, 10, 2.0, 0.35)
	_eye_flash(world, from)
	dart(world, from, end, colour)


func _eye_flash(world: Node, at: Vector3) -> void:
	if world == null:
		return
	var light := LaserEyes.make_light(colour, 1.6)
	light.light_energy = 3.0
	world.add_child(light)
	light.global_position = at
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.1)
	tw.tween_callback(light.queue_free)
	if _skeleton == null or _eye_l < 0 or _eye_r < 0:
		return
	_warm()
	for bone in [_eye_l, _eye_r]:
		var flare := MeshInstance3D.new()
		flare.mesh = _sphere
		flare.material_override = _mat_for(colour)["core"]
		flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(flare)
		flare.global_position = _eye_point(bone)
		var fw := flare.create_tween()
		fw.tween_interval(0.1)
		fw.tween_callback(flare.queue_free)


## a bolt that flies from the eyes to where the shot went, over the time a 90 m/s dart would take:
## the hit is already decided, this is only the light of it.
static func dart(world: Node, from: Vector3, to: Vector3, tint: Color) -> void:
	if world == null:
		return
	var d := to - from
	var dist := d.length()
	if dist < 0.05:
		return
	var dir := d / dist
	var length := minf(DART_LENGTH, dist)
	_warm()
	var mats: Dictionary = _mat_for(tint)
	var body := Node3D.new()
	world.add_child(body)
	body.global_position = from
	for i in 2:
		var part := MeshInstance3D.new()
		part.mesh = _cyl
		part.material_override = mats["core"] if i == 0 else mats["glow"]
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(part)
		LaserEyes.stretch(part, from, from + dir * length, CORE_RADIUS if i == 0 else GLOW_RADIUS)
	var flight := clampf((dist - length) / DART_SPEED, 0.03, 0.4)
	var tw := body.create_tween()
	tw.tween_property(body, "global_position", from + dir * (dist - length), flight)
	tw.tween_callback(body.queue_free)


static func _warm() -> void:
	if _cyl != null:
		return
	_cyl = CylinderMesh.new()
	_cyl.top_radius = 1.0
	_cyl.bottom_radius = 1.0
	_cyl.height = 1.0
	_cyl.radial_segments = 8
	_cyl.rings = 1
	_sphere = SphereMesh.new()
	_sphere.radius = 0.024
	_sphere.height = 0.048
	_sphere.radial_segments = 8
	_sphere.rings = 4


static func _mat_for(tint: Color) -> Dictionary:
	var key := tint.to_html(false)
	if _mats.has(key):
		return _mats[key]
	var core := StandardMaterial3D.new()
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.albedo_color = tint.lerp(Color.WHITE, 0.65)
	core.emission_enabled = true
	core.emission = tint.lerp(Color.WHITE, 0.4)
	core.emission_energy_multiplier = 3.0
	core.disable_receive_shadows = true
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = Color(tint, 0.45)
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.disable_receive_shadows = true
	var eye := StandardMaterial3D.new()
	eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.albedo_color = tint
	eye.emission_enabled = true
	eye.emission = tint
	eye.emission_energy_multiplier = 2.5
	eye.disable_receive_shadows = true
	_mats[key] = {"core": core, "glow": glow, "eye": eye}
	return _mats[key]


func shots() -> int:
	return _shots


func hits() -> int:
	return _hits


func last_chance() -> float:
	return _last_chance
