class_name Revive
extends Node

## the reason to bring a second operative.
##
## an operative whose health reaches zero is not dead, they are DOWN: lying where they fell, watching,
## out of the fight. The mission only fails when nobody is left standing, and until then the other
## one can come and get them. That is the standard co-op rule and it is the one that makes two
## players matter to each other rather than being two solo runs sharing a level.
##
## it is a HOLD, not a press, for the same reason a mission objective is: the three seconds are spent
## standing still over a body in the middle of a compound, which is a decision about where and when
## rather than a button. The ring around the crosshair is the same one a reload and a job use, and it
## is the whole of the feedback -- "something is running, wait for it" is one sentence and the game
## has one shape for it.

signal reach_changed(within: bool)
## the hud puts the ring up on this, exactly as it does for a job on an objective.
signal working_changed(active: bool)

## how close you have to be. generous: you are kneeling over somebody, not threading a needle.
@export var reach := 2.4
## and for how long. long enough to be a risk in the open, short enough not to be a punishment.
@export var work_time := 3.0
## what they get up with. enough to move, not enough to be careless -- a revive is a reprieve and
## not a reset, and an operative who has been down once should want to stay behind the container.
@export var health_back := 40.0

var _player: Player
var _target: Player
var _work := 0.0
var _within := false


func _ready() -> void:
	add_to_group("revive")
	_player = get_parent() as Player


## the nearest operative on the floor within arm's reach. any angle, like the takedown: you are
## already standing over them, and asking a player to face a body they are kneeling on is a rule
## that only ever fires as a bug.
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
	## said to every machine, including this one: the operative getting up has to get up everywhere,
	## and the one who did it is the one who was standing there for three seconds.
	who.net_revive.rpc(health_back)
