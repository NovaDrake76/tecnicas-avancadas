class_name LaserBolt
extends Node3D

## one bolt of a burst: a projectile, not a ray. it leaves the eye at bolt speed and arrives a beat
## later, and that beat belongs to the player. it is aimed where you WERE, so at 10 m a quarter of a
## second is enough to step out of its way, and at 3 m it is nothing, which is why closing in on a
## laser kiwi is the wrong idea and range is the player's tool. every tick it sweeps a ray over the
## ground it covers, so nothing thin is skipped at speed.

const LENGTH := 1.1

## a heavier round draws fatter and longer. the sniper's is a slug, not a spark.
var thickness := 1.0
var tail := LENGTH

var _dir := Vector3.FORWARD
var _speed := 38.0
var _left := 40.0
var _travelled := 0.0
var _damage := 7.0
var _shooter: CollisionObject3D
var _eyes: LaserEyes
var _core: MeshInstance3D
var _glow: MeshInstance3D


static func launch(world: Node, from: Vector3, toward: Vector3, speed: float, range_m: float,
		damage: float, shooter: CollisionObject3D, eyes: LaserEyes) -> LaserBolt:
	var bolt := LaserBolt.new()
	var dir := toward - from
	bolt._dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	bolt._speed = speed
	bolt._left = range_m
	bolt._damage = damage
	bolt._shooter = shooter
	bolt._eyes = eyes
	bolt.add_to_group("laser_bolt")
	world.add_child(bolt)
	bolt.global_position = from
	bolt._draw()
	return bolt


func _ready() -> void:
	var parts := LaserEyes.dart_parts()
	_core = parts[0]
	_glow = parts[1]
	add_child(_core)
	add_child(_glow)
	var light := LaserEyes.make_light(LaserEyes.GLOW, 1.8)
	light.light_energy = 1.6
	add_child(light)


func _physics_process(delta: float) -> void:
	var step := _speed * delta
	var from := global_position
	var to := from + _dir * step
	var query := PhysicsRayQueryParameters3D.create(from, to, 3)
	query.hit_from_inside = true
	if _shooter != null and is_instance_valid(_shooter):
		query.exclude = [_shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var body := hit["collider"] as Node
		var on_player := body != null and body.has_method("take_laser_hit")
		if _eyes != null and is_instance_valid(_eyes):
			_eyes.impact(hit["position"], on_player)
		if on_player:
			var origin := _shooter.global_position if _shooter != null and is_instance_valid(_shooter) else from
			body.take_laser_hit(_damage, origin)
		queue_free()
		return
	global_position = to
	_travelled += step
	_left -= step
	if _left <= 0.0:
		queue_free()
		return
	_draw()


## a tracer: the head is where the bolt is, the tail trails a metre behind but never behind the eye it
## left, so the first frame is a spark and not a rod sticking out of the bird's face.
func _draw() -> void:
	if _core == null:
		return
	var back := global_position - _dir * minf(tail, _travelled)
	var core_r: float = _eyes.bolt_core_radius if _eyes != null and is_instance_valid(_eyes) else 0.016
	var glow_r: float = _eyes.bolt_glow_radius if _eyes != null and is_instance_valid(_eyes) else 0.05
	LaserEyes.stretch(_core, back, global_position, core_r * thickness)
	LaserEyes.stretch(_glow, back, global_position, glow_r * thickness)
