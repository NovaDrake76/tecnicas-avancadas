class_name Takedown
extends Node

## the verb that never runs out. walk into contact with a kiwi, press the key, and it goes down
## without a shot being fired.
##
## it exists because the game had no FLOOR. every other way to put a bird down spends something --
## a bb, a magazine, a spare -- and a mission whose objective names a bird could be walked into a
## state where the player had nothing left and no way to finish it. restarting is an exit from a
## mistake, not a play. every stealth game this one takes from guarantees one silent option at arm's
## length for exactly this reason: MGS's CQC, Chaos Theory's grab, Dishonored's choke.
##
## it is also the answer to a hole that had nothing to do with running dry: being close to a bird
## was ONLY ever a punishment. inside its sight it sees you, at contact range it sees you at once and
## starts its call, and there was no reward anywhere for taking that risk. now there is, and it pairs
## with the carry: put one down quietly, pick it up, and put it behind the container.
##
## and it is airsoft rather than a fantasy bolted onto airsoft. a KNIFE KILL is a real milsim
## convention -- touch an opponent with a rubber training knife and they are out, no bb fired -- so
## the one mechanic that closes the soft lock is also the one that makes the game truer to its own
## subject.

## a bird came into reach, or left it. read once a tick and compared, the same way the objective
## publishes whether a job is running: the hud may not go looking through the scene every frame, and
## this node is the one that owns the answer anyway.
signal reach_changed(within: bool)
signal started(target: Node3D)
## it landed, or it was called off. the hud brightens on reach, not on either of these.
signal finished(target: Node3D)
signal cancelled()

## how far the hand reaches, measured on the FLAT. a kiwi's middle is 0.3 m off the ground and the
## player's eye is at 1.6, so measuring the real distance would mean a bird at the player's feet was
## somehow further away than one across the room, and looking down at it would be part of the verb.
## the player has to be facing it and standing next to it; where their eyes are pointing is not the
## question.
@export var reach := 1.8
## how far off the player's own facing the bird may be. generous, because at this range a small
## angle is a large step.
@export var cone_deg := 70.0
## and how far up or down: enough for a bird on a crate, not enough for one on the watchtower.
@export var lift := 2.0
## the wind-up. this is the whole cost of the verb: for this long the bird is still a bird, its eyes
## still work, and if it can see you it is already reaching for its radio. taking one down in front
## of a bird that is looking at you is a gamble, not a freebie.
@export var wind_up := 0.35
## a beat afterwards, so one press cannot walk down a row of them.
@export var cooldown := 0.6

var _player: CharacterBody3D
var _target: Kiwi
var _left := 0.0
var _cooldown := 0.0
var _within := false


func _ready() -> void:
	add_to_group("takedown")
	_player = get_parent() as CharacterBody3D


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("takedown"):
		if begin():
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var now := is_working() or can_reach()
	if now != _within:
		_within = now
		reach_changed.emit(now)
	if _target == null:
		return
	## the target can be freed, shot by something else, or simply walked away from mid swing.
	if not is_instance_valid(_target) or _target.is_down() or not _in_range(_target):
		_target = null
		_left = 0.0
		cancelled.emit()
		return
	_left -= delta
	if _left > 0.0:
		return
	_land()


## whether there is a bird in reach right now, for the hud. it says so BEFORE the press, because a verb
## nobody knows they have is not a verb.
func can_reach() -> bool:
	return _cooldown <= 0.0 and _target == null and target() != null


func is_working() -> bool:
	return _target != null


func begin() -> bool:
	if _cooldown > 0.0 or _target != null:
		return false
	## both hands are full. this is a reason to put the body down rather than a rule for its own
	## sake: a player carrying a corpse into contact range has already made their decision.
	var carry := get_tree().get_first_node_in_group("body_drag")
	if carry != null and carry.is_carrying():
		return false
	var mark := target()
	if mark == null:
		return false
	_target = mark
	_left = wind_up
	Sfx.play_2d(&"takedown_swing")
	var view := get_tree().get_first_node_in_group("viewmodel") as ViewmodelMotion
	if view != null:
		view.apply_punch()
	started.emit(_target)
	return true


## the nearest bird in reach, or null. everything it asks is a thing the player can see: how far, how
## far round, and whether there is a wall in between.
func target() -> Kiwi:
	if _player == null:
		return null
	var best: Kiwi = null
	var nearest := INF
	for node in get_tree().get_nodes_in_group("kiwi"):
		var bird := node as Kiwi
		if bird == null or bird.is_down():
			continue
		if not _in_range(bird):
			continue
		var flat := _flat_to(bird)
		if flat < nearest:
			nearest = flat
			best = bird
	return best


func _in_range(bird: Kiwi) -> bool:
	if not is_instance_valid(bird):
		return false
	var to: Vector3 = bird.global_position - _player.global_position
	if absf(to.y) > lift:
		return false
	var flat := Vector2(to.x, to.z)
	if flat.length() > reach:
		return false
	var facing: Vector3 = -_player.global_transform.basis.z
	var ahead := Vector2(facing.x, facing.z)
	if flat.length_squared() > 0.0001 and ahead.length_squared() > 0.0001:
		if rad_to_deg(ahead.normalized().angle_to(flat.normalized())) > cone_deg:
			return false
	## a wall between the two hands is a wall. the world layer only: another bird standing in the
	## way is not cover, it is a queue.
	var space := _player.get_world_3d().direct_space_state
	var from: Vector3 = _player.global_position + Vector3.UP * 0.6
	var at: Vector3 = bird.global_position + Vector3.UP * 0.3
	var query := PhysicsRayQueryParameters3D.create(from, at, 1)
	query.exclude = [_player.get_rid()]
	return space.intersect_ray(query).is_empty()


func _flat_to(bird: Node3D) -> float:
	var to: Vector3 = bird.global_position - _player.global_position
	return Vector2(to.x, to.z).length()


## it goes straight through. a bb is stopped by a plate because a bb arrives with an energy; a hand
## at the back of the neck does not, so the armoured kiwi is no harder to take down than any other
## -- getting to it is the whole of the difficulty. -1 energy is what the rest of the game already
## calls a scripted hit.
func _land() -> void:
	var bird := _target
	_target = null
	_left = 0.0
	_cooldown = cooldown
	if not is_instance_valid(bird):
		return
	var at := bird.global_position + Vector3.UP * 0.3
	Sfx.play(&"takedown", at)
	bird.take_bb_hit(999.0, at, -1.0)
	finished.emit(bird)
