extends Node

## owns the run: which level is loaded, what the objective is, the clock, the score and the ending.
## the level owns its kiwis and its spawn, the hud only renders what this emits. nothing else
## may decide that a level is finished.

## in a script with no class_name, an enum used as a PARAMETER type resolves to "run.gd.State"
## while the annotation resolves to "State", and every call fails to parse. the enum stays as
## named constants and anything typed takes a plain int, which is what a gdscript enum is.
enum State { IDLE, PLAYING, CLEARED, FINISHED, ARMORY, FAILED }

signal level_started(index: int, name: String)
## the safe house is up. index and name are the level the player will deploy into next.
signal armory_entered(next_index: int, name: String)
signal targets_changed(down: int, total: int)
signal time_changed(seconds: float)
signal level_cleared(index: int, summary: Dictionary)
## the player went down. nothing is booked, the same card shows the run, and it goes home like a clear.
signal level_failed(index: int, summary: Dictionary)
## the player has read the report card and pressed the key. main takes the run home on this.
signal results_dismissed
signal run_finished(summary: Dictionary)
signal state_changed(state: int)
signal alert_changed(value: float)
signal watcher_changed(kiwi: Node3D, value: float)
## the same birds, but what each of them KNOWS rather than how close it is to seeing you.
signal watcher_tier(kiwi: Node3D, tier: int)
signal detections_changed(count: int)
## a bb landed on something that could be hit, and whether that put it down. only the hud listens:
## nothing is counted here, the score already counts what went down and what was fired.
signal shot_hit(lethal: bool)

## a mission is a scene, a name, the time you are expected to need (beating it is worth points), a
## brief for the board and a picture for it. the pictures are shots of the level itself.
## "reinforcements" is whether a full alarm calls the gunship, and "reinforce_time" how long the horn
## gives you before it arrives: off on the first mission on purpose, a mechanic that appears in mission
## one has nowhere to go; slow on the second so it is a warning; the finale's own on the third.
const LEVELS := [
	{"path": "res://Levels/level_01.tscn", "name": "North Field", "par": 90.0, "reinforcements": false,
		"brief": "A supply camp on open ground: a container, barricades, three sentries who wander and an alarm horn by the container. A bird that sees you runs for the horn; drop it first, or cut the horn before you are seen.",
		"image": "res://UI/missions/level_01.png"},
	{"path": "res://Levels/level_02.tscn", "name": "The Woods", "par": 110.0, "reinforcements": true, "reinforce_time": 60.0,
		"brief": "Six birds in the open with the trees for cover. One has laser eyes and armour and comes for you: aim for the eyes. A sniper at the far edge lines you up with a thin green line: move. A mortar drops shells on your last known spot: watch the ring. If the horn goes and you stay in sight for a minute, a gunship comes.",
		"image": "res://UI/missions/level_02.png"},
	{"path": "res://Levels/level_03.tscn", "name": "The Summit", "par": 130.0, "reinforcements": true, "reinforce_time": 45.0,
		"brief": "A walled compound with a watchtower, a sniper on it who sees the whole approach, two armoured laser kiwis, a mortar and a horn in the yard. If the horn goes, a gunship follows in forty-five seconds: get under something or leave.",
		"image": "res://UI/missions/level_03.png"},
]

## how many missions are open before anyone has cleared one. every clear opens one more.
const OPEN_AT_START := 2

const POINTS_PER_TARGET := 100
const ACCURACY_BONUS := 250
const TIME_BONUS_PER_SECOND := 4
## the stealth reward. a bb that misses is silent, so the only way to lose this is to be seen, and
## it is paid on how long the compound stayed hot rather than on how many birds saw you.
const STEALTH_BONUS := 400
## the alarm never went up at all, not once, not briefly. a cliff and not a curve on purpose: "they
## never knew you were there" is a different thing from "they nearly caught you", and the design
## promise is that the first one is always possible.
const GHOST_BONUS := 300
## how long you may be hot before the stealth term is spent, as a fraction of par. a mission that
## expects more time also allows more trouble, which is why it is per mission like par is.
const ALARM_BUDGET_OF_PAR := 0.5

## the letter rates the run; the points are the wage, and they are different questions. a mission with
## seven kiwis pays more than one with three, so a grade built on the total would say the big mission
## was played better. these three terms are fractions of what was achievable, so the same play earns
## the same letter on any mission. COMPLETION is deliberately not a term: a mission only clears when
## every kiwi is down, so it would be 1.0 on every run and rate nothing.
const GRADE_STEALTH := 0.40
const GRADE_ACCURACY := 0.30
const GRADE_TIME := 0.30
## full marks at half par, nothing left at double par, a straight line between.
const GRADE_TIME_FULL := 0.5
const GRADE_TIME_ZERO := 2.0
## highest first. a clean, one-shot-each, unhurried run is a B; speed is what takes it to an A.
const GRADES := [["A+", 0.95], ["A", 0.85], ["B", 0.70], ["C", 0.55], ["D", 0.35], ["F", 0.0]]

## the report card waits for the player's key. this is only the fallback where there is no player to
## press one, headless, so tours and probes still come home.
const CLEAR_PAUSE := 5.5

var state := State.IDLE
var level_index := 0
var elapsed := 0.0
var shots_fired := 0
var targets_total := 0
var targets_down := 0
var detections := 0
var run_score := 0
## mission index -> best score. a mission is complete when it is in here.
var completed := {}
## mission index -> best grade ratio. its own record: a slower run that was cleaner keeps its letter.
var best_grades := {}

var _level_score := 0
var _gun_bound := false
var _awareness := {}
var _alert_level := 0.0


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
	completed.clear()
	best_grades.clear()
	## the gun lives on the player, and quitting to the menu freed that player with its gun.
	_gun_bound = false
	_set_state(State.IDLE)


## called by main once the level scene is in the tree and its kiwis have run _ready.
func begin_level(level: Node) -> void:
	elapsed = 0.0
	shots_fired = 0
	targets_down = 0
	detections = 0
	_level_score = 0
	_awareness.clear()
	_alert_level = 0.0
	## the garrison forgets everything between missions, and only the finale calls the gunship.
	Alarm.reset()
	Alarm.reinforcements_enabled = bool(current().get("reinforcements", false))
	Alarm.reinforce_time = float(current().get("reinforce_time", Alarm.REINFORCE_TIME))
	Squad.reset()

	var kiwis := _kiwis_in(level)
	targets_total = kiwis.size()
	for kiwi in kiwis:
		if not kiwi.downed.is_connected(_on_target_down):
			kiwi.downed.connect(_on_target_down)
		if not kiwi.alerted.is_connected(_on_kiwi_alerted):
			kiwi.alerted.connect(_on_kiwi_alerted)
		if not kiwi.awareness_changed.is_connected(_on_kiwi_awareness):
			kiwi.awareness_changed.connect(_on_kiwi_awareness)
		if not kiwi.tier_changed.is_connected(_on_kiwi_tier):
			kiwi.tier_changed.connect(_on_kiwi_tier)

	_bind_gun()
	_set_state(State.PLAYING)
	level_started.emit(level_index, String(current()["name"]))
	targets_changed.emit(targets_down, targets_total)
	time_changed.emit(0.0)
	detections_changed.emit(detections)
	alert_changed.emit(0.0)

	## a level with nothing to shoot is already finished, and saying so beats hanging forever.
	if targets_total == 0:
		push_warning("run: level %d has no kiwi in group 'kiwi'" % (level_index + 1))
		_clear_level()


## called by the bb itself. it is the only thing that knows what it hit, and it is freed a frame
## later, so it hands the fact over rather than expecting anyone to have watched it fly.
func report_hit(lethal: bool) -> void:
	shot_hit.emit(lethal)


func alert_level() -> float:
	return _alert_level


func stealth_text() -> String:
	if detections <= 0:
		return "UNDETECTED"
	return "SPOTTED  %d" % detections


func objective_text() -> String:
	if targets_total == 0:
		return "No targets"
	return "Take out the kiwis  %d / %d" % [targets_down, targets_total]


## the same objective in two pieces, for a hud that draws the name and the count at two sizes.
## the wording stays here: what the mission asks for is the run's business, not the overlay's.
func objective_caption() -> String:
	return "No targets" if targets_total == 0 else "Take out the kiwis"


func objective_count() -> String:
	return "" if targets_total == 0 else "%d / %d" % [targets_down, targets_total]


## the unlock rule: the first OPEN_AT_START missions are open; each clear opens the next one. mission
## i needs i + 1 - OPEN_AT_START clears, any missions, so a stuck player has somewhere else to go.
func is_unlocked(index: int) -> bool:
	return index >= 0 and index < LEVELS.size() and index < OPEN_AT_START + completed.size()


## the mission the board should open on: the one after the furthest you have cleared, if it is
## open, else the furthest open one. a fresh run opens on the first.
func suggested_level() -> int:
	var furthest := -1
	for i in completed.keys():
		furthest = maxi(furthest, int(i))
	var next := clampi(furthest + 1, 0, LEVELS.size() - 1)
	while next > 0 and not is_unlocked(next):
		next -= 1
	return next


func unlock_needs(index: int) -> int:
	return maxi(0, index + 1 - OPEN_AT_START - completed.size())


func best(index: int) -> int:
	return int(completed.get(index, 0))


func best_grade(index: int) -> float:
	return float(best_grades.get(index, 0.0))


## one shot per kiwi is perfect. a shotgun shell counts once whatever it lets out, which is the same
## unit of ammunition the brief spends.
func accuracy_ratio() -> float:
	if targets_down <= 0:
		return 0.0
	return clampf(float(targets_down) / float(maxi(shots_fired, targets_down)), 0.0, 1.0)


func alarm_budget() -> float:
	return float(current()["par"]) * ALARM_BUDGET_OF_PAR


## time spent hot against the budget. it used to be the square of the share of birds that never saw
## you, and that stopped meaning anything the moment one bird could tell the rest: the count went
## to everyone at once and forty percent of the letter became a coin flip. time is continuous, so
## it already punishes in proportion and needs no curve on top; the same number pays the bonus, so
## the letter and the money agree about being seen.
func stealth_ratio() -> float:
	var hot := Alarm.alarm_time()
	if hot <= 0.0:
		return 1.0
	return clampf(1.0 - hot / maxf(alarm_budget(), 0.001), 0.0, 1.0)


func time_ratio() -> float:
	var par := float(current()["par"])
	if par <= 0.0:
		return 0.0
	return clampf((GRADE_TIME_ZERO * par - elapsed) / ((GRADE_TIME_ZERO - GRADE_TIME_FULL) * par), 0.0, 1.0)


## 0 to 1. the letter is only this number read off the table.
func grade_ratio() -> float:
	return GRADE_STEALTH * stealth_ratio() + GRADE_ACCURACY * accuracy_ratio() + GRADE_TIME * time_ratio()


func grade_letter(ratio: float) -> String:
	for step in GRADES:
		if ratio >= float(step[1]):
			return String(step[0])
	return String(GRADES[GRADES.size() - 1][0])


func all_done() -> bool:
	return completed.size() >= LEVELS.size()


## the board picks a mission. locked ones are refused, replays are welcome.
func select_level(index: int) -> bool:
	if not is_unlocked(index):
		return false
	level_index = index
	return true


## books a clear: the best score is kept, and what the wallet earns is only the IMPROVEMENT over the
## previous best, so replaying pays for getting better, never for grinding the same mission.
## a negative ratio means "grade the run that is on the clock right now", which is every real call.
func record_result(index: int, score: int, ratio := -1.0) -> int:
	var previous := best(index)
	var gained := maxi(0, score - previous)
	completed[index] = maxi(previous, score)
	best_grades[index] = maxf(best_grade(index), grade_ratio() if ratio < 0.0 else ratio)
	return gained


## the armory is not a level: nothing is counted, the clock does not run, and no kiwi is bound.
func enter_armory() -> void:
	_set_state(State.ARMORY)
	armory_entered.emit(level_index, String(current()["name"]))


func in_armory() -> bool:
	return state == State.ARMORY


## the report card is done with. only a finished run, cleared or failed, can be dismissed, so a stray
## key in a level does nothing.
func dismiss_results() -> void:
	if state == State.CLEARED or state == State.FAILED:
		results_dismissed.emit()


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
	var rack := get_tree().get_first_node_in_group("weapon_rack") as WeaponRack
	if rack != null:
		## every weapon on the rack, not just the carried ones: the loadout changes between levels.
		for g in rack.all_weapons():
			g.fired.connect(_on_shot_fired)
		_gun_bound = true
		return
	var gun := get_tree().get_first_node_in_group("weapon") as Gun
	if gun == null:
		return
	gun.fired.connect(_on_shot_fired)
	_gun_bound = true


func _on_shot_fired(_speed: float, _mass_kg: float) -> void:
	if state == State.PLAYING:
		shots_fired += 1


func _on_kiwi_alerted(_kiwi: Kiwi) -> void:
	if state != State.PLAYING:
		return
	detections += 1
	detections_changed.emit(detections)
	## the meter is a warning. once this one has seen you there is nothing left to warn about.
	_awareness.erase(_kiwi.get_instance_id())
	watcher_changed.emit(_kiwi, 0.0)
	_push_alert()


## the hud shows one meter, so this keeps the worst of them rather than a signal per bird.
func _on_kiwi_awareness(kiwi, value: float) -> void:
	if state != State.PLAYING:
		return
	_awareness[kiwi.get_instance_id()] = value
	watcher_changed.emit(kiwi, value)
	_push_alert()


## a courier, like watcher_changed: nothing here decides anything about the tier, the bird does.
func _on_kiwi_tier(kiwi, tier: int) -> void:
	if state != State.PLAYING:
		return
	watcher_tier.emit(kiwi, tier)


func _push_alert() -> void:
	var worst := 0.0
	for v in _awareness.values():
		worst = maxf(worst, float(v))
	if absf(worst - _alert_level) < 0.02 and worst > 0.0 and worst < 1.0:
		return
	_alert_level = worst
	alert_changed.emit(worst)


func _on_target_down(kiwi) -> void:
	if state != State.PLAYING:
		return
	## a bird that is out is no longer watching, so its share of the meter has to go with it.
	_awareness.erase(kiwi.get_instance_id())
	watcher_changed.emit(kiwi, 0.0)
	_push_alert()
	targets_down += 1
	targets_changed.emit(targets_down, targets_total)
	if targets_down >= targets_total:
		_clear_level()


## the player is down. a failed mission is an F on everything: there is no partial credit for the
## kiwis taken out before the laser found you, and nothing reaches the wallet or the records.
func fail_level() -> void:
	if state != State.PLAYING:
		return
	_level_score = 0
	_last_gained = 0
	_set_state(State.FAILED)
	var s := _summary()
	for key in ["grade", "grade_stealth", "grade_accuracy", "grade_time"]:
		s[key] = 0.0
	s["letter"] = "F"
	s["failed"] = true
	level_failed.emit(level_index, s)


func _clear_level() -> void:
	_level_score = _score_level()
	var was_done := all_done()
	_last_gained = record_result(level_index, _level_score)
	run_score += _last_gained
	_set_state(State.CLEARED)
	level_cleared.emit(level_index, _summary())
	if all_done() and not was_done:
		run_finished.emit(_summary())


var _last_gained := 0


## every term is something the player did, so the number can be explained back to them.
func _score_level() -> int:
	var base := targets_down * POINTS_PER_TARGET

	## one shot per kiwi is perfect. every miss dilutes it.
	var shots := maxi(shots_fired, targets_down)
	var accuracy := float(targets_down) / float(maxi(shots, 1))
	var accuracy_points := int(round(ACCURACY_BONUS * accuracy))

	var par := float(current()["par"])
	var time_points := int(round(maxf(par - elapsed, 0.0) * TIME_BONUS_PER_SECOND))

	return base + accuracy_points + time_points + stealth_points()


## the bonus shrinks with every second the compound was hot, and a run that never woke it at all is
## paid the ghost bonus on top.
func stealth_points() -> int:
	if targets_total <= 0:
		return 0
	var earned := int(round(STEALTH_BONUS * stealth_ratio()))
	return earned + (GHOST_BONUS if not Alarm.was_ever_hot() else 0)


func was_ghost() -> bool:
	return not Alarm.was_ever_hot()


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
		"detections": detections,
		"stealth": stealth_points(),
		"alarm_time": Alarm.alarm_time(),
		"alarm_budget": alarm_budget(),
		"ghost": was_ghost(),
		"grade": grade_ratio(),
		"letter": grade_letter(grade_ratio()),
		"grade_stealth": stealth_ratio(),
		"grade_accuracy": accuracy_ratio(),
		"grade_time": time_ratio(),
		"best_grade": best_grade(level_index),
		"level_score": _level_score,
		"gained": _last_gained,
		"best": best(level_index),
		"run_score": run_score,
		"cleared": completed.size(),
		"missions": LEVELS.size(),
		"all_done": all_done(),
		"last": level_index + 1 >= LEVELS.size(),
	}


func _set_state(value: int) -> void:
	if state == value:
		return
	## the analyser gives an AUTOLOAD's enum two identities, the local `State` and the global
	## `run.gd.State`, and refuses to convert between them: typing the parameter breaks every
	## caller and `as State` is rejected as an invalid cast. both were tried. the value is only
	## ever one of the enum's own members, so the warning is answered rather than worked around.
	@warning_ignore("int_as_enum_without_cast")
	state = value
	state_changed.emit(state)
