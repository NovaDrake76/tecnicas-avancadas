class_name Noisemaker
extends Throwable

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


func _ready() -> void:
	add_to_group("noisemaker")
	mass = 0.12
	super()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.06, 0.13, 0.03)
	shape.shape = box
	add_child(shape)
	_show_model(MODEL)


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
