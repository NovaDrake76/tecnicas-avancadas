class_name Takedown
extends Node


signal reach_changed(within: bool)
signal started(target: Node3D)
signal finished(target: Node3D)
signal cancelled()

## how far the hand reaches, measured on the FLAT.
@export var reach := 1.8
## how far off the player's own facing the bird may be.
@export var cone_deg := 70.0
## and how far up or down: enough for a bird on a crate, not enough for one on the watchtower.
@export var lift := 2.0
## the wind-up.
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
	if not is_instance_valid(_target) or _target.is_down() or not _in_range(_target):
		_target = null
		_left = 0.0
		cancelled.emit()
		return
	_left -= delta
	if _left > 0.0:
		return
	_land()


func can_reach() -> bool:
	return _cooldown <= 0.0 and _target == null and target() != null


func is_working() -> bool:
	return _target != null


func begin() -> bool:
	if _cooldown > 0.0 or _target != null:
		return false
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
	var space := _player.get_world_3d().direct_space_state
	var from: Vector3 = _player.global_position + Vector3.UP * 0.6
	var at: Vector3 = bird.global_position + Vector3.UP * 0.3
	var query := PhysicsRayQueryParameters3D.create(from, at, 1)
	query.exclude = [_player.get_rid()]
	return space.intersect_ray(query).is_empty()


func _flat_to(bird: Node3D) -> float:
	var to: Vector3 = bird.global_position - _player.global_position
	return Vector2(to.x, to.z).length()


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
