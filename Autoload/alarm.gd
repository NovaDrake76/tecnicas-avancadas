extends Node


enum Stage { CALM, SEARCHING, ALARM }

signal stage_changed(stage: int)
signal reinforcements_changed(seconds_left: float)
signal reinforcements_due(at: Vector3)
signal marked_changed(marked: bool)

const CONTACT_HOLD := 0.35
const SEARCH_CALM := 20.0
const ALARM_CALM := 30.0
const REINFORCE_TIME := 45.0
const SEARCH_WEIGHT := 0.35
const MARK_HOLD := 0.5
const SEARCH_SPREAD := 1.4
const SEARCH_SPREAD_MAX := 20.0

var stage := Stage.CALM
var last_known := Vector3.ZERO
var has_last_known := false
var search_calm := SEARCH_CALM
var alarm_calm := ALARM_CALM
var reinforce_time := REINFORCE_TIME
var reinforcements_enabled := false

var _quiet := 0.0
var _alarm_time := 0.0
var _reinforce := -1.0
var _reinforce_shown := -1
var _marked := false
var _mark_quiet := 0.0
var _ever_hot := false
var _age := 999.0
var _bodies_found := 0


func _process(delta: float) -> void:
	if Run.state != Run.State.PLAYING:
		return
	_quiet += delta
	_mark_quiet += delta
	_age += delta
	if _marked and _mark_quiet > MARK_HOLD:
		_marked = false
		marked_changed.emit(false)

	match stage:
		Stage.ALARM:
			_alarm_time += delta
			if _reinforce >= 0.0:
				_reinforce -= delta
				if _reinforce <= 0.0:
					_reinforce = -1.0
					reinforcements_changed.emit(-1.0)
					reinforcements_due.emit(last_known)
				elif int(ceil(_reinforce)) != _reinforce_shown:
					_reinforce_shown = int(ceil(_reinforce))
					reinforcements_changed.emit(_reinforce)
			if _quiet >= alarm_calm:
				## the search needs its own quiet stretch on top, so the way down is two steps and not one.
				_quiet = 0.0
				_set_stage(Stage.SEARCHING)
		Stage.SEARCHING:
			_alarm_time += delta * SEARCH_WEIGHT
			if _quiet >= search_calm:
				stand_down()


func reset() -> void:
	_quiet = 0.0
	_alarm_time = 0.0
	_ever_hot = false
	_age = 999.0
	_bodies_found = 0
	has_last_known = false
	last_known = Vector3.ZERO
	_cancel_reinforcements()
	if _marked:
		_marked = false
		marked_changed.emit(false)
	_set_stage(Stage.CALM)


func report_contact(at: Vector3) -> void:
	_quiet = 0.0
	_age = 0.0
	last_known = at
	has_last_known = true


func raise_search(at: Vector3) -> void:
	report_contact(at)
	if stage == Stage.CALM:
		_set_stage(Stage.SEARCHING)


func raise_alarm(at: Vector3) -> void:
	report_contact(at)
	if stage != Stage.ALARM:
		_set_stage(Stage.ALARM)
	if reinforcements_enabled and _reinforce < 0.0:
		_reinforce = reinforce_time
		_reinforce_shown = int(ceil(_reinforce))
		reinforcements_changed.emit(_reinforce)


func stand_down() -> void:
	_cancel_reinforcements()
	_set_stage(Stage.CALM)
	for node in get_tree().get_nodes_in_group("kiwi"):
		if node.has_method("stand_down"):
			node.stand_down()


func mark(at: Vector3) -> void:
	report_contact(at)
	_mark_quiet = 0.0
	if not _marked:
		_marked = true
		marked_changed.emit(true)


func is_marked() -> bool:
	return _marked


func knowledge_age() -> float:
	return _age


func search_spread() -> float:
	if not has_last_known:
		return 0.0
	return minf(_age * SEARCH_SPREAD, SEARCH_SPREAD_MAX)


func note_body_found() -> void:
	_bodies_found += 1


func bodies_found() -> int:
	return _bodies_found


func search_point(seed_id: int) -> Vector3:
	if not has_last_known:
		return last_known
	var spread := search_spread()
	if spread <= 0.5:
		return last_known
	var angle := float(absi(seed_id) % 360) * (PI / 180.0)
	return last_known + Vector3(cos(angle), 0.0, sin(angle)) * spread


func alarm_time() -> float:
	return _alarm_time


func force_age(seconds: float) -> void:
	_age = maxf(seconds, 0.0)


func force_alarm_time(seconds: float) -> void:
	_alarm_time = maxf(seconds, 0.0)
	if _alarm_time > 0.0:
		_ever_hot = true


func reinforcements_left() -> float:
	return _reinforce


func is_hot() -> bool:
	return stage != Stage.CALM


func was_ever_hot() -> bool:
	return _ever_hot


func stage_name() -> String:
	match stage:
		Stage.SEARCHING:
			return "SEARCHING"
		Stage.ALARM:
			return "ALARM"
	return "CALM"


func _set_stage(value: int) -> void:
	if value != Stage.CALM:
		_ever_hot = true
	if stage == value:
		return
	if multiplayer.is_server():
		_push_stage.rpc(value, _ever_hot)
	@warning_ignore("int_as_enum_without_cast")
	stage = value
	if stage != Stage.ALARM:
		_cancel_reinforcements()
	stage_changed.emit(stage)


@rpc("authority", "call_remote", "reliable")
func _push_stage(value: int, hot: bool) -> void:
	_ever_hot = hot
	if stage == value:
		return
	@warning_ignore("int_as_enum_without_cast")
	stage = value
	stage_changed.emit(stage)


func _cancel_reinforcements() -> void:
	if _reinforce < 0.0:
		return
	_reinforce = -1.0
	_reinforce_shown = -1
	reinforcements_changed.emit(-1.0)
