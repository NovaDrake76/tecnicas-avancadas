class_name BirdGun
extends Node3D


## what one bb costs the player.
@export var damage := 5.0
## bbs per burst.
@export var rounds := 2
@export var round_gap := 0.12
@export var burst_gap := 0.9
@export var reach := 30.0
## the chance one bb lands on a standing player in the open at point blank; everything else scales it down.
@export_range(0.0, 1.0) var hit_base := 0.7
## bbs let out per trigger pull; one for a blaster, several for a scattergun.
@export var pellets := 1
@export var pellet_spread := 0.0
## where the bbs leave, in the bird's own frame: the beak.
@export var muzzle := Vector3(0.0, 0.42, -0.32)

const STANCE_FACTOR := [1.0, 0.55, 0.3]
const SPRINT_FACTOR := 2.0
const DUCK_FACTOR := 0.5
const TRACER := Color(0.95, 0.9, 0.75, 0.85)

var _kiwi: Kiwi
var _timer := 0.0
var _left := 0
var _shots := 0
var _hits := 0
var _last_chance := 0.0


func _ready() -> void:
	_kiwi = get_parent() as Kiwi


func tick(delta: float, target: Node3D, may_fire: bool) -> void:
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


func _shoot(target: Node3D) -> void:
	var from := _kiwi.global_transform * muzzle
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
			Sfx.play("bb_" + String(Sfx.surface_of(body)), end)
			ImpactFx.spawn(world, end, found["normal"])
	streak(world, from, end)


static func streak(world: Node, from: Vector3, to: Vector3) -> void:
	if world == null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = TRACER
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var line := KitMesh.rod(world, from, to, 0.006, mat)
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := line.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.09)
	tw.tween_callback(line.queue_free)


func shots() -> int:
	return _shots


func hits() -> int:
	return _hits


func last_chance() -> float:
	return _last_chance
