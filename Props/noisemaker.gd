class_name Noisemaker
extends RigidBody3D

## a spent magazine thrown to make a noise somewhere else. it is the one deliberate sound the player
## can make, and it does something a footstep never does: the birds that hear it WALK OVER to look.
## a footstep turns a head; a clatter in the bushes is an event. "a missed bb is silent" is untouched,
## because a bb still calls neither. the model is the m4's own magazine, split out of its mesh for
## the pickups, so it is in the fiction and reads at once as something small that was thrown.

signal landed(at: Vector3)

const MODEL := "res://Models/Ammo/rifle_mag.obj"

## a landing slower than this is a roll, not a clatter, and makes no noise.
@export var clank_speed := 2.5
@export var noise_radius := 18.0
@export var lifetime := 12.0

## the copy on another machine falls and clatters like this one; only the thrower's asks the birds
## to come and look, or one magazine would pull the same patrol twice.
var mine := true
var _landed := false


func _ready() -> void:
	add_to_group("noisemaker")
	collision_layer = 4
	collision_mask = 1
	mass = 0.12
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.06, 0.13, 0.03)
	shape.shape = box
	add_child(shape)
	if ResourceLoader.exists(MODEL):
		var mesh := load(MODEL) as Mesh
		if mesh != null:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			var bounds := mesh.get_aabb()
			mi.position = -bounds.get_center()
			add_child(mi)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _landed or state.get_contact_count() == 0:
		return
	if state.linear_velocity.length() < clank_speed and linear_velocity.length() < clank_speed:
		return
	_landed = true
	_on_landed.call_deferred(state.get_contact_collider_position(0))


## the clatter: a sound for the player, and a walk-over for every calm bird in earshot. it raises
## nothing and touches no alarm stage, ever.
func _on_landed(at: Vector3) -> void:
	Sfx.play(&"clank", at)
	## the clatter is heard on every machine that has a copy of this thing, and answered on one.
	if multiplayer.is_server():
		_walk_over(at)
	elif mine:
		_ask_walk_over.rpc_id(1, at)
	landed.emit(at)


func _walk_over(at: Vector3) -> void:
	for node in get_tree().get_nodes_in_group("kiwi"):
		if node.has_method("investigate") and node.global_position.distance_to(at) <= noise_radius:
			node.investigate(at)


@rpc("any_peer", "call_remote", "reliable")
func _ask_walk_over(at: Vector3) -> void:
	if multiplayer.is_server():
		_walk_over(at)


func has_landed() -> bool:
	return _landed
