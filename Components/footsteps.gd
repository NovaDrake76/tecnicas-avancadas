class_name Footsteps
extends SfxBank

## steps are spaced by DISTANCE, not by a timer, so they keep pace with the player at any speed
## and stay tied to the ground rather than to the framerate.

@export var stride := 2.2
## a shorter, quieter step. crouching already halves how far a kiwi can see you, this is the half
## of that the player can hear.
@export var crouch_stride := 1.5
@export var crouch_db := -9.0
@export var run_db := 2.0
@export var land_db := 3.0
@export var min_speed := 0.8

@export_group("How far it carries")
## a kiwi that hears this turns to face it. sneaking is the quiet option, sprinting announces you.
@export var crouch_noise := 5.0
@export var walk_noise := 14.0
@export var run_noise := 26.0
@export var land_noise := 22.0

var _body: CharacterBody3D
var _travelled := 0.0
var _airborne := false


func _ready() -> void:
	super()
	add_to_group("footsteps")
	_body = get_parent() as CharacterBody3D


## the whole rule, kept out of _physics_process so it can be driven and measured directly.
func advance(distance: float, crouched: bool) -> bool:
	_travelled += distance
	var step := crouch_stride if crouched else stride
	if _travelled < step:
		return false
	_travelled -= step
	return true


## broadcast rather than aimed at anything, so the player never has to know kiwis exist.
func carry(radius: float) -> void:
	for node in get_tree().get_nodes_in_group("kiwi"):
		var listener := node as Kiwi
		if listener != null:
			listener.hear(global_position, radius)


func _physics_process(delta: float) -> void:
	if _body == null:
		return

	if not _body.is_on_floor():
		_airborne = true
		return

	## the landing is a step in its own right, and the stride restarts from the touchdown.
	if _airborne:
		_airborne = false
		_travelled = 0.0
		play_one(land_db)
		carry(land_noise)
		return

	var speed := Vector2(_body.velocity.x, _body.velocity.z).length()
	if speed < min_speed:
		_travelled = 0.0
		return

	var crouched: bool = _body.has_method("is_crouching") and _body.is_crouching()
	if advance(speed * delta, crouched):
		var loud := crouch_db if crouched else 0.0
		var reach := walk_noise
		if crouched:
			reach = crouch_noise
		elif _body.has_method("is_running") and _body.is_running():
			loud = run_db
			reach = run_noise
		play_one(loud)
		carry(reach)
