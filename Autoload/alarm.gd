extends Node

## the garrison's state of mind: calm, searching, or the whole compound up in arms. Run owns the run
## and this owns the alarm, because they are different questions: Run must not decide when the birds
## calm down, and this must not decide what a mission is worth. it is a stage machine driven by two
## things only, birds reporting what they can see and birds pulling the horn, and it DECAYS: quiet
## seconds take it back down, so being seen is a setback the player can recover from and not a mode
## the rest of the mission is stuck in. that decay is what makes re-stealthing real.

enum Stage { CALM, SEARCHING, ALARM }

signal stage_changed(stage: int)
## -1.0 when nothing is counting. published on whole seconds and on start and stop, not every tick.
signal reinforcements_changed(seconds_left: float)
## the countdown ran out. whoever brings the reinforcements listens here; this only keeps time.
signal reinforcements_due(at: Vector3)
signal marked_changed(marked: bool)

## how long a reported contact keeps the quiet clock at zero. a bird glancing at you every other
## tick is one unbroken contact, not a hundred short ones.
const CONTACT_HOLD := 0.35
## quiet seconds for SEARCHING to fall back to CALM.
const SEARCH_CALM := 20.0
## quiet seconds for ALARM to fall back to SEARCHING.
const ALARM_CALM := 30.0
## ALARM to the gunship.
const REINFORCE_TIME := 45.0
## what a second of SEARCHING costs against a second of ALARM. a local scare is not a compound alarm.
const SEARCH_WEIGHT := 0.35
## how long after the last paint the mark is dropped.
const MARK_HOLD := 0.5
## how fast the compound's belief SPREADS once nobody can see the player any more, and how far
## it is allowed to spread. a search that stays a single exact point is a crowd standing on a
## spot; one that widens with age is a net closing, and it is what makes moving after being seen
## worth anything at all.
const SEARCH_SPREAD := 1.4
const SEARCH_SPREAD_MAX := 20.0

var stage := Stage.CALM
var last_known := Vector3.ZERO
var has_last_known := false
## the constants above, as vars, so a probe can shorten a thirty second wait to one instead of
## sitting through it. every real run leaves them alone.
var search_calm := SEARCH_CALM
var alarm_calm := ALARM_CALM
var reinforce_time := REINFORCE_TIME
## set per mission by Run from the level table, along with reinforce_time. mission one never calls
## the gunship; the later missions call it after their own countdown.
var reinforcements_enabled := false

var _quiet := 0.0
var _alarm_time := 0.0
var _reinforce := -1.0
var _reinforce_shown := -1
var _marked := false
var _mark_quiet := 0.0
var _ever_hot := false
## seconds since anybody last had eyes on the player. the belief below is only as good as this.
var _age := 999.0
## how many bodies the garrison walked into this level. an optional objective is paid on it, and
## it is a fact the player can act on: it is the difference between a tidy run and a lucky one.
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


## Run.begin_level calls this: a fresh garrison that has never heard of you.
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


## a bird can see the player RIGHT NOW. it pins the quiet clock, nothing more: seeing is not the
## alarm, noticing is, and that is the cone's business.
func report_contact(at: Vector3) -> void:
	_quiet = 0.0
	_age = 0.0
	last_known = at
	has_last_known = true


## a bird noticed you, or was told about you. the compound starts looking.
func raise_search(at: Vector3) -> void:
	report_contact(at)
	if stage == Stage.CALM:
		_set_stage(Stage.SEARCHING)


## the horn went, or a runner reached a friend. everyone knows, and the clock to the gunship starts.
func raise_alarm(at: Vector3) -> void:
	report_contact(at)
	if stage != Stage.ALARM:
		_set_stage(Stage.ALARM)
	if reinforcements_enabled and _reinforce < 0.0:
		_reinforce = reinforce_time
		_reinforce_shown = int(ceil(_reinforce))
		reinforcements_changed.emit(_reinforce)


## everything goes back to calm and every bird forgets. the decay ends here on its own; probes call it
## to skip the wait.
func stand_down() -> void:
	_cancel_reinforcements()
	_set_stage(Stage.CALM)
	for node in get_tree().get_nodes_in_group("kiwi"):
		if node.has_method("stand_down"):
			node.stand_down()


## the gunship is painting the player. every hunter learns where you are without seeing you, and
## the paint counts as contact, so nothing calms down while the light is on you.
func mark(at: Vector3) -> void:
	report_contact(at)
	_mark_quiet = 0.0
	if not _marked:
		_marked = true
		marked_changed.emit(true)


func is_marked() -> bool:
	return _marked


## how old the compound's belief is. zero while a bird can see you.
func knowledge_age() -> float:
	return _age


## how far that belief has SPREAD from the last sighting: nothing while somebody has eyes on you,
## widening once nobody does, capped so a search never becomes the whole level. the birds fan onto
## a ring this wide and the hud draws it at exactly this radius, so what the garrison is doing and
## what the player is shown are one number rather than two that can drift.
func search_spread() -> float:
	if not has_last_known:
		return 0.0
	return minf(_age * SEARCH_SPREAD, SEARCH_SPREAD_MAX)


## a bird found a body. counted here rather than on the bird, because the question is about the
## whole garrison and no single bird can answer it.
func note_body_found() -> void:
	_bodies_found += 1


func bodies_found() -> int:
	return _bodies_found


## where a bird should go and LOOK, as against where the player provably is. the two are the same
## thing at the moment of a sighting and drift apart from there. the offset is deterministic per
## bird, so a squad fans out into a ring instead of every one of them picking the same random
## spot, and it never moves under a bird already walking to it.
func search_point(seed_id: int) -> Vector3:
	if not has_last_known:
		return last_known
	var spread := search_spread()
	if spread <= 0.5:
		return last_known
	var angle := float(absi(seed_id) % 360) * (PI / 180.0)
	return last_known + Vector3(cos(angle), 0.0, sin(angle)) * spread


## weighted seconds spent hot. what Run grades the stealth term on.
func alarm_time() -> float:
	return _alarm_time


## for probes and tools that need a run graded at a chosen point on the curve.
## the belief aged on purpose, so a probe can ask what a cold search looks like without sitting
## through twelve seconds of one.
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


## the alarm never went up at all, not once, not briefly. the ghost bonus is paid on this.
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
	## what the garrison KNOWS is the host's, and every machine has to agree on it: the strip at the
	## top of the screen, the music, the sirens and whether a run was a ghost all read this. only the
	## stage travels -- where the birds are looking is worked out where the birds are thought about.
	if multiplayer.is_server():
		_push_stage.rpc(value, _ever_hot)
	## the same as Run._set_state: an autoload's enum has two identities to the analyser, so the
	## warning is answered outright. the value is only ever one of Stage's own members.
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


## the alarm time is what the stealth grade is paid on, and it is counted on the host. it is pushed
## with the result rather than every tick: nothing on a client's screen reads it until the card.
## cancelled, not paused: dropping out of ALARM is what the player is paid for.
func _cancel_reinforcements() -> void:
	if _reinforce < 0.0:
		return
	_reinforce = -1.0
	_reinforce_shown = -1
	reinforcements_changed.emit(-1.0)
