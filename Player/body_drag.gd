class_name BodyDrag
extends Node

## a downed kiwi stays where it fell, so where it fell is a decision. this is the answer to it: look
## at a body, press interact, and drag it behind you until it is somewhere nobody looks. press again
## to let go. the bird keeps its weapon in hand, so this costs speed rather than the ability to
## shoot: the price of hauling a body is that you cannot get away quickly while you are doing it.
##
## there is no hiding PLACE and there does not need to be one. a bird finds a body by casting a ray
## at it, so a crate, a container or the far side of a hill hides one for free, and the level's own
## cover is the vocabulary. anything that blocks a sight line blocks this.

signal grabbed(body: Node3D)
signal dropped(body: Node3D)

## how far behind the player the body is dragged, and how much of the walk speed it costs.
@export var carry_distance := 1.15
@export var carry_height := 0.12
@export_range(0.1, 1.0) var speed_scale := 0.55
## the body is pulled to the anchor rather than teleported, so it swings behind a turn instead of
## snapping round it, and a corner takes a moment to clear.
@export var follow_speed := 9.0
@export var turn_speed := 8.0
## how far down it looks for the floor under the anchor, so a body dragged down a slope stays on it.
@export var ground_probe := 2.5

var _player: CharacterBody3D
var _body: Node3D
var _just_dropped := false


func _ready() -> void:
	add_to_group("body_drag")
	_player = get_parent() as CharacterBody3D


func is_carrying() -> bool:
	return _body != null and is_instance_valid(_body)


func carried() -> Node3D:
	return _body if is_carrying() else null


## the player is slowed while hauling. player.current_max_speed multiplies by this, the same way it
## already multiplies by the aim scope's, so there is one place speed is decided and this is a term
## in it rather than a second opinion.
func speed_mult() -> float:
	return speed_scale if is_carrying() else 1.0


## called by the body's own Interactable. it refuses a second body rather than swapping, so a press
## that lands on the frame a body was dropped cannot pick it straight back up.
func grab(body: Node3D) -> bool:
	if _player == null or _just_dropped or is_carrying():
		return false
	if body == null or not is_instance_valid(body):
		return false
	if body.has_method("is_down") and not body.is_down():
		return false
	_body = body
	if _body.has_method("set_dragged"):
		_body.set_dragged(true)
	Sfx.play_2d(&"body_grab")
	grabbed.emit(_body)
	return true


func drop() -> void:
	if not is_carrying():
		return
	var was := _body
	if was.has_method("set_dragged"):
		was.set_dragged(false)
	_body = null
	_just_dropped = true
	Sfx.play(&"body_drop", was.global_position)
	dropped.emit(was)


func _unhandled_input(event: InputEvent) -> void:
	if not is_carrying():
		return
	if event.is_action_pressed("interact"):
		drop()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_just_dropped = false
	if _player == null:
		return
	## the body can be freed under us by a level change or a probe, and a freed node compares equal
	## to null, so the carry is dropped by the same check that reads it.
	if _body != null and not is_instance_valid(_body):
		_body = null
		return
	if _body == null:
		return

	_body.global_position = _body.global_position.lerp(
		_anchor(), clampf(follow_speed * delta, 0.0, 1.0))
	_face_away(delta)


## behind the player at hip height, pulled in to the first wall between the two so a body is never
## dragged through a corner into a room the player is not in.
func _anchor() -> Vector3:
	var here := _player.global_position
	var back := _player.global_transform.basis.z
	back.y = 0.0
	if back.length_squared() < 0.0001:
		back = Vector3.BACK
	var want := here + back.normalized() * carry_distance

	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(here + Vector3.UP * 0.4, want + Vector3.UP * 0.4, 1)
	query.exclude = [_player.get_rid()]
	var wall := space.intersect_ray(query)
	if not wall.is_empty():
		want = (wall["position"] as Vector3) + (wall["normal"] as Vector3) * 0.2
		want.y = here.y

	var down := PhysicsRayQueryParameters3D.create(
		want + Vector3.UP * 0.6, want + Vector3.DOWN * ground_probe, 1)
	down.exclude = [_player.get_rid()]
	var floor_hit := space.intersect_ray(down)
	if not floor_hit.is_empty():
		want.y = (floor_hit["position"] as Vector3).y
	want.y += carry_height
	return want


func _face_away(delta: float) -> void:
	var to := _body.global_position - _player.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	var want := atan2(to.x, to.z)
	_body.rotation.y = lerp_angle(_body.rotation.y, want, clampf(turn_speed * delta, 0.0, 1.0))
