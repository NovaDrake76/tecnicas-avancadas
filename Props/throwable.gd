class_name Throwable
extends RigidBody3D

## anything the player can throw. the belt makes one of these, gives it a shove and forgets about it;
## what it does when it gets there is the subclass's business.
##
## it exists because the thrown magazine and the frag grenade are the same object twice over -- a
## small rigid body on the bb layer that hits the world and nothing else, carries a model, tidies
## itself up after a while, and knows whether it is the thrower's own copy or a picture of somebody
## else's. writing that twice is how the second one quietly stops matching the first.

## how long it lives if nothing else disposes of it. a level with thrown magazines lying about
## forever is a level that gets slower the longer it is played.
@export var lifetime := 12.0

## the copy on another machine falls and looks like this one and is otherwise inert: only the
## thrower's copy is entitled to make anything happen. the whole difference between a thing being
## laid on every screen and a thing being done is this flag.
var mine := true

var _landed := false


func _ready() -> void:
	## layer 3 is the bb layer, masking the world only: a thrown thing is stopped by the ground and
	## by cover, and is not a wall to walk into, not a thing to shoot, and not cover to hide behind.
	collision_layer = 4
	collision_mask = 1
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = true
	_build()
	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(_expire)


## the collision shape and the model. subclasses fill it in.
func _build() -> void:
	pass


func _expire() -> void:
	queue_free()


## the model, centred on its own bounds: the pack's meshes do not agree about where their origin is
## and a magazine spinning about a corner reads as broken.
func _show_model(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var mesh := load(path) as Mesh
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = -mesh.get_aabb().get_center()
	add_child(mi)


func has_landed() -> bool:
	return _landed
