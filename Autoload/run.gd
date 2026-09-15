extends Node


enum State { IDLE, PLAYING, CLEARED, FINISHED, ARMORY, FAILED }

signal level_started(index: int, name: String)
signal armory_entered(next_index: int, name: String)
signal targets_changed(down: int, total: int)
signal objectives_changed()
signal objective_working(objective, active: bool)
signal objective_abandoned(objective)
signal time_changed(seconds: float)
signal level_cleared(index: int, summary: Dictionary)
signal level_failed(index: int, summary: Dictionary)
signal results_dismissed
signal run_finished(summary: Dictionary)
signal state_changed(state: int)
signal restart_requested(index: int)
signal alert_changed(value: float)
signal watcher_changed(kiwi: Node3D, value: float)
signal watcher_tier(kiwi: Node3D, tier: int)
signal detections_changed(count: int)
signal shot_hit(lethal: bool)

const LEVELS := [
	{"path": "res://Levels/level_01-A.tscn", "name": "North Field", "par": 90.0, "reinforcements": true,
		"optional": ["clear_field", "no_shots", "horn_cut", "no_body_found"],
		"brief": "A forward supply camp. Command wants the two advanced birds working out of it taken off the board, and the crate of range-finding gear they brought with them. Take them out, take the case, and walk out the way you came. The camp keeps three ordinary sentries and an alarm horn by the container: a bird that sees you runs for it.",
		"image": "res://UI/missions/level_01.png",
		"briefing": [
			{"view": [-14.0, 136.0, 1.0], "time": 0.0, "hold": 0.6},
			{"say": "GHOST KIWI RECON. BRIEFING FOR OPERATION NORTH FIELD.", "hold": 0.8},
			{"say": "THE KIWI EMPIRE ROSE IN NEW ZEALAND.", "stain": ["NZL"], "hold": 1.0},
			{"say": "THE EAST COAST OF AUSTRALIA WAS THE FIRST TO FALL.", "stain": ["AUS-E"], "hold": 1.0},
			{"say": "FROM THERE THE BIRDS WENT NORTH.", "stain": ["PNG", "IDN", "PHL"], "hold": 1.0},
			{"say": "INDOCHINA FELL IN ONE SEASON.", "stain": ["THA", "KHM", "VNM", "LAO"], "hold": 1.0},
			{"say": "THREE CHINESE PROVINCES ARE UNDER THE BIRD.", "stain": ["CN-GX", "CN-FJ", "CN-ZJ"], "hold": 1.0},
			{"say": "JAPAN AND KOREA WENT QUIET LAST MONTH.", "stain": ["JPN", "KOR"], "hold": 1.4},
			{"clear": true, "say": "YOUR MISSION: INFILTRATE THE EMPIRE AND BREAK IT FROM THE INSIDE.", "hold": 1.6},
			{"clear": true, "view": [-37.9, 176.6, 7.0], "time": 2.6, "say": "DEPLOYMENT: POINT X. BAY OF PLENTY, NORTH ISLAND.", "hold": 0.4},
			{"mark": [-37.75, 176.9, "POINT X"], "hold": 0.8},
			{"say": "FIRST TASK: AN ADVANCED KIWI POST NEAR THE COAST. TWO ADVANCED BIRDS, AND THE CASE THEY BROUGHT WITH THEM.", "hold": 1.0},
			{"say": "TAKE THEM OUT, TAKE THE CASE, WALK OUT THE WAY YOU CAME.", "hold": 1.0},
		]},
	{"path": "res://Levels/level_02-A.tscn", "name": "Hilltown", "par": 110.0, "reinforcements": true,
		"optional": ["no_shots", "no_body_found", "ghost"],
		"brief": "The field station the camp reported to. The records room holds the empire's supply manifests: take them and get out, and nobody needs to know you were here. Hilltown is held by six birds, two snipers are watching your approach, be careful.",
		"image": "res://UI/missions/level_02.png",
		"briefing": [
			{"view": [-14.0, 136.0, 1.0], "time": 0.0, "stain": ["NZL", "AUS-E", "PNG", "IDN", "PHL", "THA", "KHM", "VNM", "LAO", "CN-GX", "CN-FJ", "CN-ZJ", "JPN", "KOR"], "stagger": 0.08, "hold": 0.8},
			{"say": "GHOST KIWI RECON. MISSION 02: THE WOODS.", "hold": 0.8},
			{"say": "THE COAST POST IS QUIET. THE CASE YOU BROUGHT OUT NAMED THE STATION IT REPORTED TO.", "hold": 1.0},
			{"clear": true, "view": [-38.1, 176.7, 5.0], "time": 2.6, "mark": [-37.75, 176.9, "NORTH FIELD", "done"], "say": "A FIELD STATION IN THE KAINGAROA PINES, SOUTH OF THE COAST.", "hold": 0.4},
			{"line": [-37.75, 176.9, -38.45, 176.55], "mark": [-38.45, 176.55, "THE WOODS"], "hold": 1.0},
			{"say": "THE RECORDS ROOM HOLDS THE EMPIRE'S SUPPLY MANIFESTS. TAKE THEM AND LEAVE NOBODY THE WISER.", "hold": 1.0},
			{"say": "SIX BIRDS HOLD THE WOODS. ONE IS ARMOURED, WITH LASER EYES. A SNIPER WATCHES THE APPROACH. A MORTAR ANSWERS WHEREVER THEY LAST SAW YOU.", "hold": 1.2},
			{"say": "GO IN QUIET. THE STATION MUST NOT KNOW IT WAS READ.", "hold": 1.0},
		]},
	{"path": "res://Levels/level_03.tscn", "name": "The Summit", "par": 130.0, "reinforcements": true,
		"optional": ["horn_cut", "no_body_found", "ghost"],
		"brief": "The manifests named this place: the depot the whole northern front is armed out of. Put charges on both stores and be off the mountain when they go. A walled compound, a sniper on the watchtower who sees the whole approach, two armoured laser kiwis, a mortar and a horn in the yard. The charges are loud by design, so the way out is the hard half.",
		"image": "res://UI/missions/level_03.png",
		"briefing": [
			{"view": [-14.0, 136.0, 1.0], "time": 0.0, "stain": ["NZL", "AUS-E", "PNG", "IDN", "PHL", "THA", "KHM", "VNM", "LAO", "CN-GX", "CN-FJ", "CN-ZJ", "JPN", "KOR"], "stagger": 0.08, "hold": 0.8},
			{"say": "GHOST KIWI RECON. MISSION 03: THE SUMMIT.", "hold": 0.8},
			{"say": "THE MANIFESTS NAMED THE DEPOT THAT ARMS THE WHOLE NORTHERN FRONT.", "hold": 1.0},
			{"clear": true, "view": [-38.9, 176.1, 4.6], "time": 2.6, "mark": [-37.75, 176.9, "NORTH FIELD", "done"], "say": "A WALLED COMPOUND ON THE CENTRAL PLATEAU, UNDER THE VOLCANOES.", "hold": 0.2},
			{"mark": [-38.45, 176.55, "THE WOODS", "done"], "line": [-38.45, 176.55, -39.28, 175.57], "hold": 0.2},
			{"mark": [-39.28, 175.57, "THE SUMMIT"], "hold": 1.0},
			{"say": "PUT CHARGES ON BOTH STORES AND BE OFF THE MOUNTAIN WHEN THEY GO.", "hold": 1.0},
			{"say": "A SNIPER ON THE WATCHTOWER SEES THE WHOLE APPROACH. TWO ARMOURED BIRDS, A MORTAR, AND A HORN IN THE YARD.", "hold": 1.2},
			{"say": "THE CHARGES ARE LOUD BY DESIGN. THE WAY OUT IS THE HARD HALF.", "hold": 1.0},
		]},
	{"path": "res://Levels/level_04.tscn", "name": "The Crossing", "par": 100.0, "reinforcements": true,
		"optional": ["no_shots", "horn_cut", "no_body_found"],
		"brief": "The road the depot fed. A staging camp went up on the crossing within a week of the mountain going quiet, and the paperwork moving through it is the next thread: take the manifests out of it and leave the way you came. The camp is held in numbers now: ten sentries on the crates and the gate, two armoured birds with laser eyes, a pair of chargers that close the moment they hear you, a sniper on the open ground and a mortar behind the containers. Every one of them carries a blaster, the manifests are guarded up the road, and the horn in the yard calls more.",
		"image": "res://UI/missions/level_04.png",
		"briefing": [
			{"view": [-14.0, 136.0, 1.0], "time": 0.0, "stain": ["NZL", "AUS-E", "PNG", "IDN", "PHL", "THA", "KHM", "VNM", "LAO", "CN-GX", "CN-FJ", "CN-ZJ", "JPN", "KOR"], "stagger": 0.08, "hold": 0.8},
			{"say": "GHOST KIWI RECON. MISSION 04: THE CROSSING.", "hold": 0.8},
			{"say": "THE MOUNTAIN WENT QUIET. WITHIN A WEEK A STAGING CAMP WENT UP ON THE ROAD THE DEPOT FED.", "hold": 1.0},
			{"clear": true, "view": [-39.7, 175.9, 4.2], "time": 2.6, "mark": [-38.45, 176.55, "THE WOODS", "done"], "say": "THE MANAWATU GORGE, WHERE THE ROAD CROSSES TO THE SOUTH.", "hold": 0.2},
			{"mark": [-39.28, 175.57, "THE SUMMIT", "done"], "line": [-39.28, 175.57, -40.32, 175.78], "hold": 0.2},
			{"mark": [-40.32, 175.78, "THE CROSSING"], "hold": 1.0},
			{"say": "THE PAPERWORK MOVING THROUGH IT IS THE NEXT THREAD. TAKE THE MANIFESTS AND LEAVE THE WAY YOU CAME.", "hold": 1.0},
			{"say": "TEN SENTRIES ON THE CRATES AND THE GATE. TWO ARMOURED BIRDS. TWO CHARGERS THAT CLOSE THE MOMENT THEY HEAR YOU. A SNIPER ON THE OPEN GROUND, A MORTAR BEHIND THE CONTAINERS.", "hold": 1.2},
			{"say": "EVERY ONE OF THEM CARRIES A BLASTER, AND THE HORN CALLS MORE.", "hold": 1.0},
		]},
	{"path": "res://Levels/level_05.tscn", "name": "The Long Yard", "par": 115.0, "reinforcements": true,
		"optional": ["horn_cut", "no_body_found", "ghost"],
		"brief": "The empire answered the crossing by building bigger. The long yard is the same camp twice over -- twice the crates, twice the walls, the same six birds spread thin across it -- and the manifests are at the far end of it. More cover to cross means more cover to use; the mortar behind it means standing still in that cover is what gets you killed.",
		"image": "res://UI/missions/level_05.png",
		"briefing": [
			{"view": [-14.0, 136.0, 1.0], "time": 0.0, "stain": ["NZL", "AUS-E", "PNG", "IDN", "PHL", "THA", "KHM", "VNM", "LAO", "CN-GX", "CN-FJ", "CN-ZJ", "JPN", "KOR"], "stagger": 0.08, "hold": 0.8},
			{"say": "GHOST KIWI RECON. MISSION 05: THE LONG YARD.", "hold": 0.8},
			{"say": "THE EMPIRE ANSWERED THE CROSSING BY BUILDING BIGGER.", "hold": 1.0},
			{"clear": true, "view": [-40.7, 175.3, 4.2], "time": 2.6, "mark": [-39.28, 175.57, "THE SUMMIT", "done"], "say": "A YARD IN THE HUTT VALLEY, AT THE GATES OF THE CAPITAL.", "hold": 0.2},
			{"mark": [-40.32, 175.78, "THE CROSSING", "done"], "line": [-40.32, 175.78, -41.2, 174.92], "hold": 0.2},
			{"mark": [-41.2, 174.92, "THE LONG YARD"], "hold": 1.0},
			{"say": "THE SAME CAMP TWICE OVER: TWICE THE CRATES, TWICE THE WALLS, SIX BIRDS SPREAD THIN ACROSS IT.", "hold": 1.0},
			{"say": "THE MANIFESTS ARE AT THE FAR END. MORE COVER TO CROSS MEANS MORE COVER TO USE.", "hold": 1.0},
			{"say": "THE MORTAR BEHIND IT MEANS STANDING STILL IN THAT COVER IS WHAT GETS YOU KILLED.", "hold": 1.0},
			{"say": "THIS IS THE LAST THREAD. PULL IT.", "hold": 1.2},
		]},
	{"path": "res://Levels/level_06.tscn", "name": "The Village", "par": 150.0, "reinforcements": true,
		"optional": ["no_shots", "horn_cut", "no_body_found", "ghost"],
		"brief": "A hill village the empire emptied and moved into, cut into the side of a mountain in three terraces: a street with a gate at each end, the command house above it, the barracks and the garage below. You start behind the spur to the east, higher than the village; look before you move. The signal log is upstairs in the command house, and the way out is the road down to the valley. Twelve sentries hold the village, two of them walking the street and one each on the lower yard and the upper terrace, a sniper on the barracks roof, a mortar in a pit on the upper terrace, an armoured bird on the street and a charger by the garage. The horn is inside the east gate. There are more ways in than the gates.",
		"image": "res://UI/missions/level_06.png",
		"briefing": [
			{"view": [-14.0, 136.0, 1.0], "time": 0.0, "stain": ["NZL", "AUS-E", "PNG", "IDN", "PHL", "THA", "KHM", "VNM", "LAO", "CN-GX", "CN-FJ", "CN-ZJ", "JPN", "KOR"], "stagger": 0.08, "hold": 0.8},
			{"say": "GHOST KIWI RECON. MISSION 06: THE VILLAGE.", "hold": 0.8},
			{"say": "THE YARD WAS THE CAPITAL'S LAST DOOR. THE BIRDS PULLED BACK INTO THE HILLS AND TOOK A VILLAGE WITH THEM.", "hold": 1.0},
			{"clear": true, "view": [-41.1, 175.3, 4.6], "time": 2.6, "mark": [-41.2, 174.92, "THE LONG YARD", "done"], "say": "A HILL VILLAGE IN THE RIMUTAKA RANGE, EMPTIED AND GARRISONED.", "hold": 0.2},
			{"line": [-41.2, 174.92, -41.1, 175.32], "mark": [-41.1, 175.32, "THE VILLAGE"], "hold": 1.0},
			{"say": "YOU START BEHIND THE SPUR ABOVE IT. LOOK BEFORE YOU MOVE.", "hold": 1.0},
			{"say": "THE SIGNAL LOG IS UPSTAIRS IN THE COMMAND HOUSE. THE WAY OUT IS THE ROAD DOWN TO THE VALLEY.", "hold": 1.2},
			{"say": "TWELVE SENTRIES, A SNIPER ON THE BARRACKS ROOF, A MORTAR, AN ARMOURED BIRD, A CHARGER. THE HORN IS INSIDE THE EAST GATE.", "hold": 1.2},
			{"say": "THERE ARE MORE WAYS IN THAN THE GATES.", "hold": 1.0},
		]},
]

const OPEN_AT_START := 2

const POINTS_PER_TARGET := 100
const ACCURACY_BONUS := 250
const OPTIONAL_BONUS := 150
const TIME_BONUS_PER_SECOND := 4
const STEALTH_BONUS := 400
const GHOST_BONUS := 300
const ALARM_BUDGET_OF_PAR := 0.5

const GRADE_STEALTH := 0.40
const GRADE_ACCURACY := 0.30
const GRADE_TIME := 0.30
const GRADE_TIME_FULL := 0.5
const GRADE_TIME_ZERO := 2.0
const GRADES := [["A+", 0.95], ["A", 0.85], ["B", 0.70], ["C", 0.55], ["D", 0.35], ["F", 0.0]]

const CLEAR_PAUSE := 5.5

var state := State.IDLE
var level_index := 0
var elapsed := 0.0
var shots_fired := 0
var shots_hit := 0
var objectives: Array = []
var targets_total := 0
var targets_down := 0
var detections := 0
var run_score := 0
var completed := {}
## every mission open on the board, so whoever is building a level can go straight to it. on when the game runs from the editor and off in an exported build, which keeps the progression.
var open_all := OS.has_feature("editor")
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


func has_briefing(index: int) -> bool:
	return index >= 0 and index < LEVELS.size() and not (LEVELS[index].get("briefing", []) as Array).is_empty()


func briefing_of(index: int) -> Array:
	if not has_briefing(index):
		return []
	return LEVELS[index]["briefing"] as Array


func start_run() -> void:
	level_index = 0
	run_score = 0
	completed.clear()
	best_grades.clear()
	## quitting to the menu freed the player and its gun with it; without this no shot ever counts again.
	_gun_bound = false
	_set_state(State.IDLE)


func report_down(who: int) -> void:
	_report_down.rpc_id(1, who)


@rpc("any_peer", "call_local", "reliable")
func _report_down(_who: int) -> void:
	if not multiplayer.is_server() or state != State.PLAYING:
		return
	for node in get_tree().get_nodes_in_group("player"):
		var who := node as Player
		if who != null and who.is_alive():
			return
	fail_level()


func restart_level() -> bool:
	if state != State.PLAYING:
		return false
	restart_requested.emit(level_index)
	return true


## the level is going away: nothing may keep pointing into it. called before the free, because a
## `node as Objective` on a freed object throws, and the waypoint walks this list every frame.
func forget_level() -> void:
	objectives.clear()
	objectives_changed.emit()
	targets_total = 0
	targets_down = 0


func begin_level(level: Node) -> void:
	elapsed = 0.0
	shots_fired = 0
	shots_hit = 0
	targets_down = 0
	detections = 0
	_level_score = 0
	_awareness.clear()
	_alert_level = 0.0
	Alarm.reset()
	Alarm.reinforcements_enabled = bool(current().get("reinforcements", false))
	Alarm.reinforce_time = float(current().get("reinforce_time", Alarm.REINFORCE_TIME))
	Alarm.gunship = bool(current().get("gunship", false))
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

	if targets_total == 0:
		push_warning("run: level %d has no kiwi in group 'kiwi'" % (level_index + 1))
		_clear_level()


func report_hit(lethal: bool) -> void:
	if state == State.PLAYING:
		if multiplayer.is_server():
			shots_hit += 1
		else:
			_add_tally.rpc_id(1, 0, 1)
	shot_hit.emit(lethal)


@rpc("any_peer", "call_remote", "reliable")
func _add_tally(shots: int, hits: int) -> void:
	if not multiplayer.is_server() or state != State.PLAYING:
		return
	shots_fired += shots
	shots_hit += hits


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


func required_objectives() -> Array:
	var out: Array = []
	for o in objectives:
		if is_instance_valid(o) and not o.optional:
			out.append(o)
	return out


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


func objective_lines() -> Array:
	var out: Array = []
	for o in objectives:
		if is_instance_valid(o) and not o.optional:
			out.append({"name": o.label, "done": o.is_done()})
	return out


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


func is_unlocked(index: int) -> bool:
	if index < 0 or index >= LEVELS.size():
		return false
	return open_all or index < OPEN_AT_START + completed.size()


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


func accuracy_ratio() -> float:
	if shots_fired <= 0:
		return 1.0
	return clampf(float(shots_hit) / float(shots_fired), 0.0, 1.0)


func alarm_budget() -> float:
	return float(current()["par"]) * ALARM_BUDGET_OF_PAR


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


func grade_ratio() -> float:
	return GRADE_STEALTH * stealth_ratio() + GRADE_ACCURACY * accuracy_ratio() + GRADE_TIME * time_ratio()


func grade_letter(ratio: float) -> String:
	for step in GRADES:
		if ratio >= float(step[1]):
			return String(step[0])
	return String(GRADES[GRADES.size() - 1][0])


func all_done() -> bool:
	return completed.size() >= LEVELS.size()


func select_level(index: int) -> bool:
	if not is_unlocked(index):
		return false
	level_index = index
	return true


func record_result(index: int, score: int, ratio := -1.0) -> int:
	var previous := best(index)
	var gained := maxi(0, score - previous)
	completed[index] = maxi(previous, score)
	best_grades[index] = maxf(best_grade(index), grade_ratio() if ratio < 0.0 else ratio)
	return gained


func enter_armory() -> void:
	_set_state(State.ARMORY)
	armory_entered.emit(level_index, String(current()["name"]))


func in_armory() -> bool:
	return state == State.ARMORY


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


func adopt(kiwi: Node) -> void:
	if not kiwi.alerted.is_connected(_on_kiwi_alerted):
		kiwi.alerted.connect(_on_kiwi_alerted)
	if not kiwi.awareness_changed.is_connected(_on_kiwi_awareness):
		kiwi.awareness_changed.connect(_on_kiwi_awareness)
	if not kiwi.tier_changed.is_connected(_on_kiwi_tier):
		kiwi.tier_changed.connect(_on_kiwi_tier)


func _kiwis_in(level: Node) -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group("kiwi"):
		if level.is_ancestor_of(node) or node == level:
			out.append(node)
	return out


func _bind_gun() -> void:
	if _gun_bound:
		return
	var rack := get_tree().get_first_node_in_group("weapon_rack") as WeaponRack
	if rack != null:
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
	Squad.note_player_shot()
	if state == State.PLAYING:
		if multiplayer.is_server():
			shots_fired += 1
		else:
			_add_tally.rpc_id(1, 1, 0)


func _on_kiwi_alerted(_kiwi: Kiwi) -> void:
	if state != State.PLAYING:
		return
	detections += 1
	if multiplayer.is_server():
		_push_detections.rpc(detections)
	detections_changed.emit(detections)
	_awareness.erase(_kiwi.get_instance_id())
	watcher_changed.emit(_kiwi, 0.0)
	_push_alert()


func _on_kiwi_awareness(kiwi, value: float) -> void:
	if state != State.PLAYING:
		return
	_awareness[kiwi.get_instance_id()] = value
	watcher_changed.emit(kiwi, value)
	_push_alert()


func _on_kiwi_tier(kiwi, tier: int) -> void:
	if state != State.PLAYING:
		return
	watcher_tier.emit(kiwi, tier)


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
	if not multiplayer.is_server():
		return
	_awareness.erase(kiwi.get_instance_id())
	watcher_changed.emit(kiwi, 0.0)
	_push_alert()
	targets_down += 1
	_push_targets.rpc(targets_down)
	targets_changed.emit(targets_down, targets_total)
	if objectives.is_empty() and targets_down >= targets_total:
		_clear_level()
	else:
		objectives_changed.emit()


func fail_level() -> void:
	if state != State.PLAYING or not multiplayer.is_server():
		return
	_level_score = 0
	_last_gained = 0
	_set_state(State.FAILED)
	var s := _summary()
	for key in ["grade", "grade_stealth", "grade_accuracy", "grade_time"]:
		s[key] = 0.0
	s["letter"] = "F"
	s["failed"] = true
	_push_over.rpc(false, level_index, s)
	level_failed.emit(level_index, s)


func _clear_level() -> void:
	if not multiplayer.is_server():
		return
	_level_score = _score_level()
	var was_done := all_done()
	_last_gained = record_result(level_index, _level_score)
	run_score += _last_gained
	_set_state(State.CLEARED)
	_push_over.rpc(true, level_index, _summary())
	level_cleared.emit(level_index, _summary())
	if all_done() and not was_done:
		run_finished.emit(_summary())


@rpc("authority", "call_remote", "reliable")
func _push_targets(down: int) -> void:
	targets_down = down
	targets_changed.emit(targets_down, targets_total)
	objectives_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _push_detections(count: int) -> void:
	detections = count
	detections_changed.emit(detections)


@rpc("authority", "call_remote", "reliable")
func _push_over(cleared: bool, index: int, summary: Dictionary) -> void:
	level_index = index
	_set_state(State.CLEARED if cleared else State.FAILED)
	if cleared:
		_last_gained = record_result(index, int(summary.get("level_score", 0)),
			float(summary.get("grade", 0.0)))
		run_score += _last_gained
		level_cleared.emit(index, summary)
	else:
		level_failed.emit(index, summary)


var _last_gained := 0


func _score_level() -> int:
	var base := targets_down * POINTS_PER_TARGET + optional_points()

	var accuracy_points := int(round(ACCURACY_BONUS * accuracy_ratio()))

	var par := float(current()["par"])
	var time_points := int(round(maxf(par - elapsed, 0.0) * TIME_BONUS_PER_SECOND))

	return base + accuracy_points + time_points + stealth_points()


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
	@warning_ignore("int_as_enum_without_cast")
	state = value
	state_changed.emit(state)
