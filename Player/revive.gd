class_name Revive
extends Node


signal reach_changed(within: bool)
signal working_changed(active: bool)

## how close you have to be.
@export var reach := 2.4
## and for how long.
@export var work_time := 3.0
## what they get up with.
@export var health_back := 40.0

var _player: Player
var _target: Player
var _work := 0.0
var _within := false


func _ready() -> void:
	add_to_group("revive")
	_player = get_parent() as Player


func target() -> Player:
	if _player == null or _player.is_down():
		return null
	var best: Player = null
	var near := INF
	for who in Player.downed(get_tree()):
		if who == _player:
			continue
		var d := who.global_position.distance_to(_player.global_position)
		if d <= reach and d < near:
			near = d
			best = who
	return best


func is_working() -> bool:
	return _target != null and _work > 0.0


func progress() -> float:
	return clampf(_work / maxf(work_time, 0.01), 0.0, 1.0)


func _process(delta: float) -> void:
	var mark := target()
	var within := mark != null
	if within != _within:
		_within = within
		reach_changed.emit(within)

	var was := is_working()
	if mark == null or not Input.is_action_pressed("interact"):
		_target = null
		_work = 0.0
	else:
		if mark != _target:
			_target = mark
			_work = 0.0
		_work += delta
		if _work >= work_time:
			_finish()
	var now := is_working()
	if now != was:
		working_changed.emit(now)


func _finish() -> void:
	var who := _target
	_target = null
	_work = 0.0
	if who == null or not is_instance_valid(who):
		return
	who.net_revive.rpc(health_back)
