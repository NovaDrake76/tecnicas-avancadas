@tool
class_name LooseProp
extends RigidBody3D


signal clattered(at: Vector3, radius: float)

## a prop at or under this many kilograms can be picked up; anything heavier is furniture that
## only the world moves. one number decides both how far it flies and whether it can be lifted.
const CARRY_MASS := 14.0
const SETTLE_GAP := 0.4

## the model, exactly as a Prop takes it: swapping the class is what makes a prop loose.
@export var model: PackedScene:
	set(value):
		model = value
		if is_inside_tree():
			_rebuild()
## what it sounds like when a bb or the ground hits it: metal, wood, concrete, dirt, gravel or grass.
@export var material_tag := &""

@export_group("Noise")
## a landing that sheds less speed than this in one tick is a roll, not a clatter.
@export var clatter_drop := 2.2
## one landing is one noise, however many contacts the tumble makes.
@export var clatter_gap := 0.35
## how far the clatter is walked over to; 0 works it out from the mass.
@export var noise_radius := 0.0

@export_group("Push")
## how hard a bb shoves it, per joule of the bb's energy. a real bb could not move a paint can;
## this one has to, or shooting a can to pull a bird away is a verb nobody would ever use.
@export var bb_push := 4.0
## a blast's shove is scaled by mass, so heavy and light scatter alike; a bb's is not.
@export var blast_push := 1.0

var _cd := 0.0
var _prev_speed := 0.0
var _carrier: Node3D = null
var _rest_layer := 1
var _rest_mask := 1
var _settle := 0.0


func _ready() -> void:
	add_to_group("loose_prop")
	collision_layer = 1
	collision_mask = 1
	_rest_layer = collision_layer
	_rest_mask = collision_mask
	if physics_material_override == null:
		var slide := PhysicsMaterial.new()
		slide.friction = 0.7
		physics_material_override = slide
	_rebuild()
	if Engine.is_editor_hint():
		return
	if can_carry():
		var take := Interactable.new()
		take.name = "Interactable"
		take.prompt = "Pick up"
		take.interacted.connect(_on_taken)
		add_child(take)


func _rebuild() -> void:
	Prop.dress(self, model)


## the mass is the whole rule: a can is picked up, a barrel is not.
func can_carry() -> bool:
	return mass <= CARRY_MASS


func hearing_radius() -> float:
	if noise_radius > 0.0:
		return noise_radius
	return clampf(6.0 + mass * 1.6, 6.0, 26.0)


func surface() -> StringName:
	if material_tag != &"":
		return material_tag
	var hint := model.resource_path.get_file().to_lower() if model != null else ""
	return Sfx.surface_from_name(hint + " " + name.to_lower())


func is_carried() -> bool:
	return _carrier != null and is_instance_valid(_carrier)


## ---------------------------------------------------------------- landing
## the impact is the SPEED DROP over one tick, not a contact: friction and gravity never shed this
## much in a tick, and a sleeping prop costs nothing to skip, which is the reason a
## room full of crates is free until something touches one.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_cd = maxf(_cd - delta, 0.0)
	if sleeping or freeze:
		_prev_speed = 0.0
		_settle_check(delta)
		return
	var speed := linear_velocity.length()
	if _prev_speed - speed >= clatter_drop and _cd <= 0.0:
		_cd = clatter_gap
		_clatter(global_position)
	_prev_speed = speed
	_settle = 0.0


func _clatter(at: Vector3) -> void:
	var radius := hearing_radius()
	Sfx.play(StringName("bb_" + String(surface())), at, 6.0)
	clattered.emit(at, radius)
	if multiplayer.is_server():
		walk_over(get_tree(), at, radius)
	else:
		_ask_walk_over.rpc_id(1, at, radius)


## the whole point of the thing: a bird near enough goes and looks at where the noise came from.
static func walk_over(tree: SceneTree, at: Vector3, radius: float) -> void:
	for node in tree.get_nodes_in_group("kiwi"):
		var bird := node as Node3D
		if bird != null and bird.has_method("investigate") \
				and bird.global_position.distance_to(at) <= radius:
			bird.investigate(at)


@rpc("any_peer", "call_remote", "reliable")
func _ask_walk_over(at: Vector3, radius: float) -> void:
	if multiplayer.is_server():
		walk_over(get_tree(), at, radius)


## ---------------------------------------------------------------- being shoved
## a bb: off centre on purpose, so a shot can spins away instead of sliding flat, and NOT scaled by
## mass, which is what makes a barrel shrug off what sends a bucket across the yard.
func shove(impulse: Vector3, at := Vector3.INF) -> void:
	if freeze or is_carried():
		return
	sleeping = false
	if at == Vector3.INF:
		apply_central_impulse(impulse)
	else:
		apply_impulse(impulse, at - global_position)


func bb_shove(along: Vector3, at: Vector3, energy: float) -> void:
	if along.length_squared() < 0.000001:
		return
	shove(along.normalized() * energy * bb_push, at)


## a blast: scaled BY the mass, so the yard scatters as one, plus a little lift or everything
## merely slides. called from the burst that every machine draws, so no message is needed.
static func blast(tree: SceneTree, at: Vector3, radius: float, force: float) -> int:
	var moved := 0
	for node in tree.get_nodes_in_group("loose_prop"):
		var prop := node as LooseProp
		if prop == null or not is_instance_valid(prop) or prop.freeze or prop.is_carried():
			continue
		var away: Vector3 = prop.global_position - at
		var far := away.length()
		if far > radius:
			continue
		if far < 0.001:
			away = Vector3.UP
			far = 0.001
		away = away / far
		away.y = maxf(away.y, 0.4)
		var falloff := 1.0 - far / radius
		prop.shove(away.normalized() * force * falloff * prop.mass * prop.blast_push)
		moved += 1
	return moved


## ---------------------------------------------------------------- carrying
func _on_taken(by: Node) -> void:
	var hands := (by as Node).get_node_or_null("PropCarry") as PropCarry if by != null else null
	if hands != null:
		hands.grab(self)


func held_by(who: Node3D) -> void:
	_carrier = who
	_rest_layer = collision_layer
	_rest_mask = collision_mask
	freeze = true
	## nothing carried is world any more: a crate in the hands would block a bird's sight line and
	## the player's own steps, and a vision cone that a held bucket blocked would be a bug nobody
	## could see the cause of.
	collision_layer = 0
	collision_mask = 0


func let_go() -> void:
	_carrier = null
	collision_layer = _rest_layer
	collision_mask = _rest_mask
	freeze = false
	sleeping = false
	_prev_speed = 0.0


## ---------------------------------------------------------------- the wire
## the thrower flies its own copy and the HOST says where it came to rest, because a tumbling rigid
## body does not stop in the same place twice. Between throws a prop is asleep and costs nothing.
@rpc("any_peer", "call_local", "reliable")
func net_held(peer: int) -> void:
	var hands := PropCarry.hands_of(get_tree(), peer)
	if hands == null:
		return
	held_by(hands.holder())
	hands.hold(self)


@rpc("any_peer", "call_local", "reliable")
func net_toss(from: Vector3, impulse: Vector3, spin: Vector3) -> void:
	var hands := _carrier.get_node_or_null("PropCarry") as PropCarry if is_carried() else null
	global_position = from
	let_go()
	if hands != null:
		hands.release()
	apply_central_impulse(impulse)
	angular_velocity = spin
	_prev_speed = linear_velocity.length()


@rpc("authority", "call_remote", "reliable")
func net_settle(where: Transform3D) -> void:
	if is_carried():
		return
	global_transform = where
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = true


func _settle_check(delta: float) -> void:
	if not multiplayer.is_server() or multiplayer.get_peers().is_empty():
		return
	if _settle < 0.0:
		return
	_settle += delta
	if _settle >= SETTLE_GAP:
		_settle = -1.0
		net_settle.rpc(global_transform)
