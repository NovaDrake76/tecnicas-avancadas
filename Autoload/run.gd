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
## the mission's own objectives moved, finished, or the live one changed. the hud draws them.
signal objectives_changed()
## the player started or finished a job on an objective, and the hud puts the ring up on it.
signal objective_working(objective, active: bool)
## and walked away from one that had already started.
signal objective_abandoned(objective)
signal time_changed(seconds: float)
signal level_cleared(index: int, summary: Dictionary)
## the player went down. nothing is booked, the same card shows the run, and it goes home like a clear.
signal level_failed(index: int, summary: Dictionary)
## the player has read the report card and pressed the key. main takes the run home on this.
signal results_dismissed
signal run_finished(summary: Dictionary)
signal state_changed(state: int)
## the player gave up on this attempt and wants the same mission from the top. nothing here reloads
## anything: main hosts the level scene, so main is what swaps it, and this is only the word going
## out. it is a signal rather than a call into main so the pause menu, which is an autoload with no
## idea what is hosting the level, does not have to go looking for it.
signal restart_requested(index: int)
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
## the gunship is OFF: every mission has "reinforcements" false, so the countdown never starts and
## nothing is ever dispatched. the helicopter, the searchlight, the door gun and the whole
## reinforcement clock are built and still covered by the gate, which drives Alarm directly rather
## than reading this table -- switching a mission back on is this one flag and nothing else, and
## "reinforce_time" is left in place for when it goes back. the briefs lost the sentence promising a
## gunship at the same time: a brief that names a threat which cannot arrive is a lie the player
## plans around.
## "reinforcements" is whether a full alarm calls the gunship, and "reinforce_time" how long the horn
## gives you before it arrives: off on the first mission on purpose, a mechanic that appears in mission
## one has nowhere to go; slow on the second so it is a warning; the finale's own on the third.
const LEVELS := [
	{"path": "res://Levels/level_01.tscn", "name": "North Field", "par": 90.0, "reinforcements": false,
		"optional": ["clear_field", "no_shots", "horn_cut", "no_body_found"],
		"brief": "A forward supply camp. Command wants the two advanced birds working out of it taken off the board, and the crate of range-finding gear they brought with them. Take them out, take the case, and walk out the way you came. The camp keeps three ordinary sentries and an alarm horn by the container: a bird that sees you runs for it.",
		"image": "res://UI/missions/level_01.png"},
	{"path": "res://Levels/level_02.tscn", "name": "The Woods", "par": 110.0, "reinforcements": false, "reinforce_time": 60.0,
		"optional": ["no_shots", "no_body_found", "ghost"],
		"brief": "The field station the camp reported to. The records room holds the empire's supply manifests: take them and get out, and nobody needs to know you were here. The woods are held by six birds, one of them armoured with laser eyes, a sniper watching the approach and a mortar that shells wherever they last saw you.",
		"image": "res://UI/missions/level_02.png"},
	{"path": "res://Levels/level_03.tscn", "name": "The Summit", "par": 130.0, "reinforcements": false, "reinforce_time": 45.0,
		"optional": ["horn_cut", "no_body_found", "ghost"],
		"brief": "The manifests named this place: the depot the whole northern front is armed out of. Put charges on both stores and be off the mountain when they go. A walled compound, a sniper on the watchtower who sees the whole approach, two armoured laser kiwis, a mortar and a horn in the yard. The charges are loud by design, so the way out is the hard half.",
		"image": "res://UI/missions/level_03.png"},
]

## how many missions are open before anyone has cleared one. every clear opens one more.
const OPEN_AT_START := 2

const POINTS_PER_TARGET := 100
const ACCURACY_BONUS := 250
## what one optional objective is worth. they pay MONEY and never move the letter: the grade
## rates how the run went, and doing extra work is a wage rather than a better run.
const OPTIONAL_BONUS := 150
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
## bbs that landed on something that could be hit. accuracy is hits over shots now, which is a
## question a run that took nobody out can still answer.
var shots_hit := 0
## every Objective node the level put in the group, in the order it declared them.
var objectives: Array = []
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


## start this mission again from the beginning. nothing is booked and nothing is kept: begin_level
## already zeroes the clock, the shots, the detections, the alarm and the squad, so a restart is the
## level scene being built again and nothing more. only a mission in progress can be restarted -- in
## the safe house there is nothing to restart, and once the report card is up the run is already
## scored, and letting a bad grade be taken back would make every letter mean "the best of however
## many times I tried".
func restart_level() -> bool:
	if state != State.PLAYING:
		return false
	restart_requested.emit(level_index)
	return true


## called by main once the level scene is in the tree and its kiwis have run _ready.
func begin_level(level: Node) -> void:
	elapsed = 0.0
	shots_fired = 0
	shots_hit = 0
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

	## the LEVEL declares what the mission is: every Objective node it placed, in tree order.
	## nothing here names them, so adding an objective is placing a node and nothing else, and a
	## level that declares none keeps the old rule of clearing the field.
	objectives.clear()
	for node in get_tree().get_nodes_in_group("objective"):
		var o := node as Objective
		if o == null:
			continue
		objectives.append(o)
		if not o.completed.is_connected(_on_objective_done):
			o.completed.connect(_on_objective_done)
		if not o.working_changed.is_connected(_on_objective_working.bind(o)):
			o.working_changed.connect(_on_objective_working.bind(o))
		if not o.abandoned.is_connected(_on_objective_abandoned.bind(o)):
			o.abandoned.connect(_on_objective_abandoned.bind(o))

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
	if state == State.PLAYING:
		shots_hit += 1
	shot_hit.emit(lethal)


func alert_level() -> float:
	return _alert_level


func stealth_text() -> String:
	if detections <= 0:
		return "UNDETECTED"
	return "SPOTTED  %d" % detections


func objective_text() -> String:
	var caption := objective_caption()
	var count := objective_count()
	return caption if count == "" else "%s  %s" % [caption, count]


## the objectives a mission cannot end without, in the order the level declared them.
func required_objectives() -> Array:
	var out: Array = []
	for o in objectives:
		if is_instance_valid(o) and not o.optional:
			out.append(o)
	return out


## the one the hud names: the first required objective still open, skipping the way out until
## there is a reason to use it.
func live_objective():
	var exfil = null
	for o in required_objectives():
		if o.is_done():
			continue
		if o.kind == Objective.Kind.EXFIL:
			exfil = o
			continue
		return o
	return exfil


func objectives_left() -> int:
	var n := 0
	for o in required_objectives():
		if not o.is_done():
			n += 1
	return n


## one line per objective for the report card: what it was, and whether it happened.
func objective_lines() -> Array:
	var out: Array = []
	for o in objectives:
		if is_instance_valid(o) and not o.optional:
			out.append({"name": o.label, "done": o.is_done()})
	return out


## the same objective in two pieces, for a hud that draws the name and the count at two sizes.
## the wording stays here: what the mission asks for is the run's business, not the overlay's.
func objective_caption() -> String:
	var live = live_objective()
	if live != null:
		return live.label
	if not objectives.is_empty():
		return "Mission complete"
	return "No targets" if targets_total == 0 else "Take out the kiwis"


func objective_count() -> String:
	var required := required_objectives()
	if not required.is_empty():
		return "%d / %d" % [required.size() - objectives_left(), required.size()]
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


## what landed against what was spent, and a run that never fired is PERFECTLY accurate.
##
## it used to be kiwis down over shots taken, returning 0.0 when nothing was down at all. that was
## fine while the only mission was to clear the field and indefensible the moment one was not: a
## player who walked into a compound, took what they came for and left without firing scored zero
## on thirty percent of the letter and could not beat a B. The most stealthy run the game can
## produce was graded below a mediocre shooting one, which is the opposite of what the whole design
## promises. a shell still counts once whatever it lets out, so hits are clamped to shots: three
## pellets from one cartridge are one shot that hit.
func accuracy_ratio() -> float:
	if shots_fired <= 0:
		return 1.0
	## the clamp is what makes a shotgun honest: one cartridge is one shot and lets out three
	## pellets, so three hits over one shot is 300 percent until it is bounded. a shell that lands is
	## one shot that hit.
	return clampf(float(shots_hit) / float(shots_fired), 0.0, 1.0)


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


## an objective finished. the mission ends when the required ones are all done and there is no
## way out to walk to; where there is one, reaching it is what ends the mission.
## couriers, like watcher_changed: nothing here decides anything, the objective does.
func _on_objective_working(active: bool, which) -> void:
	if state == State.PLAYING:
		objective_working.emit(which, active)


func _on_objective_abandoned(which) -> void:
	if state == State.PLAYING:
		objective_abandoned.emit(which)


func _on_objective_done(which) -> void:
	if state != State.PLAYING:
		return
	objectives_changed.emit()
	if which != null and which.optional:
		return
	if objectives_left() > 0:
		return
	_clear_level()


## the optional objectives a mission offers, as rules rather than places: each is a question the
## run can be asked at the end. the pair worth having in every mission is one that CONFLICTS with
## another, because that is what makes a second run a different run instead of a faster one.
const OPTIONAL_RULES := {
	"clear_field": "Leave nobody standing",
	"no_shots": "Never fire a shot",
	"horn_cut": "Cut the horn",
	"no_body_found": "No body found",
	"ghost": "Never wake the compound",
}


func optional_done(rule: String) -> bool:
	match rule:
		"clear_field":
			return targets_total > 0 and targets_down >= targets_total
		"no_shots":
			return shots_fired == 0
		"horn_cut":
			var horns := get_tree().get_nodes_in_group("alarm_horn")
			if horns.is_empty():
				return false
			for h in horns:
				if h.has_method("is_usable") and h.is_usable():
					return false
			return true
		"no_body_found":
			return Alarm.bodies_found() == 0
		"ghost":
			return not Alarm.was_ever_hot()
	return false


## the ones this mission actually offers, from its row in the table.
func optional_rules() -> Array:
	var out: Array = []
	for r in current().get("optional", []):
		if OPTIONAL_RULES.has(String(r)):
			out.append(String(r))
	return out


func optional_lines() -> Array:
	var out: Array = []
	for r in optional_rules():
		out.append({"name": String(OPTIONAL_RULES[r]), "done": optional_done(r)})
	for o in objectives:
		if is_instance_valid(o) and o.optional:
			out.append({"name": o.label, "done": o.is_done()})
	return out


func optional_points() -> int:
	var n := 0
	for line in optional_lines():
		if bool(line["done"]):
			n += 1
	return n * OPTIONAL_BONUS


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
	## clearing the field is only the win condition on a level that declared no objectives of its
	## own. where there are objectives the birds are the obstacle course, not the point, and a
	## mission that ended the moment the last one went down could never be robbed and left.
	if objectives.is_empty() and targets_down >= targets_total:
		_clear_level()
	else:
		objectives_changed.emit()


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
	var base := targets_down * POINTS_PER_TARGET + optional_points()

	## one shot per kiwi is perfect. every miss dilutes it.
	var accuracy_points := int(round(ACCURACY_BONUS * accuracy_ratio()))

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
	return {
		"level": level_index + 1,
		"name": String(current()["name"]),
		"targets": targets_down,
		"total": targets_total,
		"shots": shots_fired,
		"accuracy": accuracy_ratio(),
		"hits": shots_hit,
		"objectives": objective_lines(),
		"optional": optional_lines(),
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
