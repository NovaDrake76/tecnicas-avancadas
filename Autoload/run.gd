extends Node

## owns the run: which level is loaded, what the objective is, the clock, the score and the ending.
## the level owns its kiwis and its spawn, the hud only renders what this emits. nothing else
## may decide that a level is finished.

## in a script with no class_name, an enum used as a PARAMETER type resolves to "run.gd.State"
## while the annotation resolves to "State", and every call fails to parse. the enum stays as
## named constants and anything typed takes a plain int, which is what a gdscript enum is.
enum State { IDLE, PLAYING, CLEARED, FINISHED }

signal level_started(index: int, name: String)
signal targets_changed(down: int, total: int)
signal time_changed(seconds: float)
signal level_cleared(index: int, summary: Dictionary)
signal run_finished(summary: Dictionary)
signal state_changed(state: int)

## a level is a scene path and the time you are expected to need. beating par is worth points.
const LEVELS := [
	{"path": "res://Levels/level_01.tscn", "name": "Ala Norte", "par": 90.0},
	{"path": "res://Levels/level_02.tscn", "name": "Bosque", "par": 110.0},
	{"path": "res://Levels/level_03.tscn", "name": "Cume", "par": 130.0},
]

const POINTS_PER_TARGET := 100
const ACCURACY_BONUS := 250
const TIME_BONUS_PER_SECOND := 4

## seconds the clear banner stays up before the next level loads.
const CLEAR_PAUSE := 3.5

var state := State.IDLE
var level_index := 0
var elapsed := 0.0
var shots_fired := 0
var targets_total := 0
var targets_down := 0
var run_score := 0

var _level_score := 0
var _gun_bound := false


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	elapsed += delta
	time_changed.emit(elapsed)


func level_count() -> int:
	return LEVELS.size()


func current() -> Dictionary:
	return LEVELS[clampi(level_index, 0, LEVELS.size() - 1)]


func level_path() -> String:
	return String(current()["path"])


func start_run() -> void:
	level_index = 0
	run_score = 0
	_set_state(State.IDLE)


## called by main once the level scene is in the tree and its kiwis have run _ready.
func begin_level(level: Node) -> void:
	elapsed = 0.0
	shots_fired = 0
	targets_down = 0
	_level_score = 0

	var kiwis := _kiwis_in(level)
	targets_total = kiwis.size()
	for kiwi in kiwis:
		if not kiwi.downed.is_connected(_on_target_down):
			kiwi.downed.connect(_on_target_down)

	_bind_gun()
	_set_state(State.PLAYING)
	level_started.emit(level_index, String(current()["name"]))
	targets_changed.emit(targets_down, targets_total)
	time_changed.emit(0.0)

	## a level with nothing to shoot is already finished, and saying so beats hanging forever.
	if targets_total == 0:
		push_warning("run: level %d has no kiwi in group 'kiwi'" % (level_index + 1))
		_clear_level()


func objective_text() -> String:
	if targets_total == 0:
		return "No targets"
	return "Take out the kiwis  %d / %d" % [targets_down, targets_total]


func advance() -> bool:
	if level_index + 1 >= LEVELS.size():
		_set_state(State.FINISHED)
		run_finished.emit(_summary())
		return false
	level_index += 1
	return true


func _kiwis_in(level: Node) -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group("kiwi"):
		if level.is_ancestor_of(node) or node == level:
			out.append(node)
	return out


## the gun lives on the player, which outlives every level, so this only ever binds once.
func _bind_gun() -> void:
	if _gun_bound:
		return
	var gun := get_tree().get_first_node_in_group("weapon") as Gun
	if gun == null:
		return
	gun.fired.connect(_on_shot_fired)
	_gun_bound = true


func _on_shot_fired(_speed: float, _mass_kg: float) -> void:
	if state == State.PLAYING:
		shots_fired += 1


func _on_target_down(_kiwi) -> void:
	if state != State.PLAYING:
		return
	targets_down += 1
	targets_changed.emit(targets_down, targets_total)
	if targets_down >= targets_total:
		_clear_level()


func _clear_level() -> void:
	_level_score = _score_level()
	run_score += _level_score
	_set_state(State.CLEARED)
	level_cleared.emit(level_index, _summary())


## every term is something the player did, so the number can be explained back to them.
func _score_level() -> int:
	var base := targets_down * POINTS_PER_TARGET

	## one shot per kiwi is perfect. every miss dilutes it.
	var shots := maxi(shots_fired, targets_down)
	var accuracy := float(targets_down) / float(maxi(shots, 1))
	var accuracy_points := int(round(ACCURACY_BONUS * accuracy))

	var par := float(current()["par"])
	var time_points := int(round(maxf(par - elapsed, 0.0) * TIME_BONUS_PER_SECOND))

	return base + accuracy_points + time_points


func _summary() -> Dictionary:
	var shots := maxi(shots_fired, targets_down)
	return {
		"level": level_index + 1,
		"name": String(current()["name"]),
		"targets": targets_down,
		"total": targets_total,
		"shots": shots_fired,
		"accuracy": float(targets_down) / float(maxi(shots, 1)),
		"time": elapsed,
		"par": float(current()["par"]),
		"level_score": _level_score,
		"run_score": run_score,
		"last": level_index + 1 >= LEVELS.size(),
	}


func _set_state(value: int) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(state)
