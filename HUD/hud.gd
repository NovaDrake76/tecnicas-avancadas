extends CanvasLayer

const ALERT_COLOR := Color(1.0, 0.35, 0.3)
const CLEAR_COLOR := Color(0.55, 0.85, 0.6)

@onready var type_label: Label = %Type
@onready var ammo_label: Label = %Ammo
@onready var capacity_label: Label = %Capacity
@onready var mass_label: Label = %Mass
@onready var mode_label: Label = %Mode
@onready var mode_icon: FireModeIcon = %ModeIcon
@onready var mode_hint: KeyCap = %ModeHint
@onready var hopup_label: Label = %Hopup
@onready var gear_rows: HBoxContainer = %GearRows
@onready var melee_row: HBoxContainer = %MeleeRow
@onready var melee_label: Label = %Melee
@onready var melee_key: KeyCap = %MeleeKey
@onready var message_label: Label = %Message
@onready var prompt_label: Label = %Prompt
@onready var prompt_key: KeyCap = %PromptKey
@onready var prompt_row: HBoxContainer = %PromptRow
@onready var objective_label: Label = %Objective
@onready var targets_label: Label = %Targets
@onready var timer_label: Label = %Timer
@onready var alarm_label: Label = %Alarm
@onready var report_card: ReportCard = %ReportCard
@onready var alert_ring: AlertRing = %AlertRing
@onready var status_label: Label = %Status
@onready var crosshair: Crosshair = %Crosshair
@onready var hit_marker: HitMarker = %HitMarker
@onready var spare_label: Label = %Spare
@onready var reload_ring: ReloadRing = %ReloadRing
@onready var vitals: Vitals = %Vitals

var _weapon: Gun
var _interactor: Interactor
var _message_tween: Tween
var _flash_tween: Tween
var _aim_tween: Tween
var _spare_tween: Tween
var _aiming := false
## -1 until a level has said what the count is, so the first value is not a change.
var _last_detections := -1
var _status_tween: Tween
var _pouch: MagazinePouch
var _belt: UtilityBelt
## what the belt looked like when the rows were last built, and the two controls in each row.
## the rows are only rebuilt when the KINDS change, which is once a mission: throwing something
## must not free and rebuild the label that is about to be pulsed.
var _gear_shown: Array[String] = []
var _gear_cells := {}
var _bound := false


func _ready() -> void:
	add_to_group("hud")
	message_label.text = ""
	prompt_label.text = ""
	prompt_row.visible = false
	_style()
	_clear_field_readout()
	alert_ring.clear()
	## the key is read off the input map instead of typed into the scene, so a rebind can
	## never leave the hud telling the player to press a key that does nothing. the cap resolves
	## its own letter; the scene says which ACTION it is showing and nothing more.
	mode_hint.refresh()

	Run.level_started.connect(_on_level_started)
	report_card.dismissed.connect(func() -> void: Run.dismiss_results())
	Run.armory_entered.connect(_on_armory_entered)
	Run.targets_changed.connect(_on_targets_changed)
	Run.time_changed.connect(_on_time_changed)
	Run.level_cleared.connect(_on_level_cleared)
	Run.level_failed.connect(_on_level_failed)
	Run.run_finished.connect(_on_run_finished)
	Run.watcher_changed.connect(_on_watcher_changed)
	Run.watcher_tier.connect(_on_watcher_tier)
	Run.objectives_changed.connect(_on_objectives_changed)
	Run.objective_working.connect(_on_objective_working)
	Run.objective_abandoned.connect(_on_objective_abandoned)
	Run.detections_changed.connect(_on_detections_changed)
	## the ring says WHO is noticing you; this strip says HOW BAD it is for the whole compound, and
	## how long until it gets worse. the two do not overlap.
	Alarm.stage_changed.connect(_on_alarm_stage)
	Alarm.reinforcements_changed.connect(_on_reinforcements)
	_refresh_alarm()
	## the bb that landed is the only thing that knows what it landed on, and it is gone a frame
	## later. Run carries the word across because it is the one node both ends already know.
	Run.shot_hit.connect(hit_marker.strike)

	Net.local_player_ready.connect(func(_who: Node) -> void: _bind_weapon())
	_bind_weapon.call_deferred()


## every size and colour comes from HudStyle rather than from a theme override typed into the
## scene, so the scale stays in one file and a new label cannot invent a fourteenth size.
func _style() -> void:
	HudStyle.tune(type_label, HudStyle.T_LABEL, HudStyle.DIM)
	HudStyle.tune(ammo_label, HudStyle.T_HERO, HudStyle.BRIGHT)
	HudStyle.tune(capacity_label, HudStyle.T_UNIT, HudStyle.DIM)
	HudStyle.tune(spare_label, HudStyle.T_UNIT, HudStyle.DIM)
	HudStyle.tune(mode_label, HudStyle.T_VALUE, HudStyle.HOT)
	## the brief wants these two permanently on screen. they stay, quietly, and speak up on change.
	HudStyle.tune(mass_label, HudStyle.T_MICRO, HudStyle.FAINT)
	HudStyle.tune(hopup_label, HudStyle.T_MICRO, HudStyle.FAINT)
	HudStyle.tune(melee_label, HudStyle.T_MICRO, HudStyle.FAINT)
	HudStyle.tune(objective_label, HudStyle.T_LABEL, HudStyle.DIM)
	HudStyle.tune(targets_label, HudStyle.T_VALUE, HudStyle.BRIGHT)
	HudStyle.tune(timer_label, HudStyle.T_UNIT, HudStyle.FAINT)
	HudStyle.tune(alarm_label, HudStyle.T_LABEL, HudStyle.HOT)
	HudStyle.tune(status_label, HudStyle.T_VALUE, HudStyle.ALERT)
	HudStyle.tune(message_label, HudStyle.T_VALUE, HudStyle.HOT)
	HudStyle.tune(prompt_label, HudStyle.T_UNIT, HudStyle.BRIGHT)


## everything on this screen that belongs to the operative this machine drives. it is called twice
## on purpose: once a frame after the hud is built, which is when a solo player already exists, and
## again the moment a player node arrives -- a joined machine gets its operative from the host a
## beat after the hud has finished asking for one, and a hud that only ever asked once would spend
## the whole mission blank. the flag is what stops the second call connecting everything twice.
func _bind_weapon() -> void:
	if _bound or Player.local(get_tree()) == null:
		return
	_bound = true
	var rack := get_tree().get_first_node_in_group("weapon_rack") as WeaponRack
	if rack != null:
		rack.weapon_changed.connect(_follow_weapon)
		_follow_weapon(rack.current())
	else:
		_follow_weapon(get_tree().get_first_node_in_group("weapon") as Gun)
	if _weapon == null:
		push_warning("hud.gd: no weapon to follow; HUD will stay blank.")

	vitals.watch(Player.local(get_tree()))

	_interactor = get_tree().get_first_node_in_group("interactor") as Interactor
	if _interactor != null:
		_interactor.focus_changed.connect(_on_focus_changed)
		_interactor.focus_lost.connect(_on_focus_lost)

	var scope := get_tree().get_first_node_in_group("aim_scope") as AimScope
	if scope != null:
		scope.aim_changed.connect(_on_aim_changed)

	_pouch = get_tree().get_first_node_in_group("pouch") as MagazinePouch
	if _pouch != null:
		_pouch.changed.connect(_update_spare)
		_pouch.refused.connect(_on_pouch_refused)
		_pouch.added.connect(_on_spare_added)
	_update_spare()

	## the takedown only names itself when there is a bird to use it on. it used to sit in the block
	## all mission, on the grounds that a verb nobody knows they have is not a verb -- but a line that
	## is always there is one the eye stops reading by the second mission, and it was taking footer
	## room from the things that DO change. Nathan's call, and it makes the row a prompt rather than a
	## label: it appears exactly when it means something, which is what every other prompt here does.
	## the controls page still lists it, which is where a player looks for a verb they have forgotten.
	var hands := get_tree().get_first_node_in_group("takedown")
	if hands != null:
		hands.reach_changed.connect(_on_takedown_reach)
		hands.started.connect(func(_t: Node3D) -> void: pulse(melee_label))
	melee_row.visible = false

	## a teammate on the floor. the ring is the same one a reload and a job use, and the prompt is
	## the same row an interactable uses: the game has one shape for "something is running" and one
	## for "there is something here", and a third of either would be a third thing to learn.
	var hands_up := get_tree().get_first_node_in_group("revive")
	if hands_up != null:
		hands_up.working_changed.connect(func(active: bool) -> void:
			reload_ring.watch_job(hands_up if active else null)
			_show_crosshair(not active and not _aiming))
		hands_up.reach_changed.connect(func(within: bool) -> void:
			if within:
				_on_focus_changed("Revive", &"interact", null)
			else:
				_on_focus_lost())

	## the belt sits with the other quiet figures and speaks up when something is thrown
	_belt = get_tree().get_first_node_in_group("utility") as UtilityBelt
	if _belt != null:
		_belt.changed.connect(_on_gear_changed)
	_sync_gear(true)


## the only readout in the block that answers to where the player is STANDING rather than to what
## they are carrying, and now the only one that comes and goes with it.
func _on_takedown_reach(within: bool) -> void:
	melee_row.visible = within
	if within:
		melee_label.add_theme_color_override("font_color", HudStyle.BRIGHT)
		melee_key.ink = HudStyle.BRIGHT
		melee_key.edge = Color(HudStyle.BRIGHT, 0.55)
		melee_key.refresh()
		pulse(melee_label)


func _on_gear_changed() -> void:
	_sync_gear(false)


## the belt, one row per kind: a key, the name and how many are left. the row for the thing in hand
## is bright and wears the THROW key; the others are faint and wear the key that would bring them to
## hand, which is the only sentence either of them needs. the order is the table's and never the
## selection's, because a row that jumps as you cycle cannot be read at a glance -- and a kind stays
## on screen at x0, since the count going to nothing is how the player learns they are out.
func _sync_gear(force: bool) -> void:
	if _belt == null or not is_instance_valid(_belt):
		return
	if force or _gear_shown != _belt.carried:
		_gear_shown = _belt.carried.duplicate()
		_gear_cells.clear()
		for child in gear_rows.get_children():
			gear_rows.remove_child(child)
			child.queue_free()
		for id in _gear_shown:
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_theme_constant_override("separation", 5)
			gear_rows.add_child(row)
			## the number that puts this kind in hand, always shown, whether it is in hand or not:
			## the key means the same thing every time it is pressed, which is the whole reason it
			## is a number and not a cycle.
			var pick := KeyCap.new()
			pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pick.text_size = 19
			pick.action = UtilityBelt.key_for(id)
			row.add_child(pick)
			## and the throw key, on the row that is in hand and nowhere else, so the pair reads as
			## one sentence: press this number, then press this to throw it.
			var cap := KeyCap.new()
			cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cap.text_size = 19
			cap.action = &"throw"
			row.add_child(cap)
			var label := Label.new()
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			HudStyle.tune(label, HudStyle.T_MICRO, HudStyle.FAINT)
			row.add_child(label)
			_gear_cells[id] = {"pick": pick, "cap": cap, "label": label}
	var picked := _belt.selected()
	for id in _gear_shown:
		var cell: Dictionary = _gear_cells[id]
		var pick := cell["pick"] as KeyCap
		var cap := cell["cap"] as KeyCap
		var label := cell["label"] as Label
		var here := id == picked
		var shade := HudStyle.BRIGHT if here else HudStyle.FAINT
		cap.visible = here
		for k in [pick, cap]:
			k.ink = shade
			k.edge = Color(shade, 0.55)
			k.refresh()
		var was := label.text
		label.text = "%s  x%d" % [UtilityBelt.title_of(id), _belt.count(id)]
		label.add_theme_color_override("font_color", shade)
		if was != "" and was != label.text:
			pulse(label)


## the hud listens to exactly one weapon at a time. switching moves every connection over,
## and the new one is asked to state itself so nothing shows stale.
func _follow_weapon(gun: Gun) -> void:
	if _weapon != null and is_instance_valid(_weapon):
		for pair in _weapon_signals():
			var sig: Signal = _weapon.get(pair[0])
			if sig.is_connected(pair[1]):
				sig.disconnect(pair[1])
	_weapon = gun
	if _weapon == null:
		return
	for pair in _weapon_signals():
		var sig: Signal = _weapon.get(pair[0])
		sig.connect(pair[1])
	_weapon.emit_state()
	reload_ring.watch(_weapon)
	crosshair.watch(_weapon)
	_update_spare()
	show_message(_weapon.weapon_model)


func _weapon_signals() -> Array:
	return [
		["ammo_changed", _on_ammo_changed],
		["magazine_changed", _on_magazine_changed],
		["fire_mode_changed", _on_fire_mode_changed],
		["fired", _on_weapon_fired],
		["hopup_changed", _on_hopup_changed],
		["fire_failed", _on_fire_failed],
		["magazine_rejected", _on_magazine_rejected],
		["mode_refused", show_message],
		["reload_started", _on_reload_started],
		["reload_finished", _on_reload_finished],
		["reload_cancelled", _on_reload_cancelled],
		["reload_failed", _on_reload_failed],
	]


## no level title on the way in: the board already named the mission and showed its picture, so the
## banner was telling the player something they had just read. the message line is cleared rather than
## left alone, or the safe house hint could still be fading when the level starts.
func _on_level_started(_index: int, _name: String) -> void:
	report_card.hide_card()
	_on_detections_changed(0)
	alert_ring.clear()
	_clear_message()


## nothing is announced here either. the safe house says what it is by what is in it: a bench, a board
## and a range, each with its own prompt when you look at it.
func _on_armory_entered(_next_index: int, _name: String) -> void:
	report_card.hide_card()
	_clear_field_readout()
	alert_ring.clear()
	objective_label.text = "ARMORY"
	_clear_message()


## the caption names the job and the count is the thing you glance at, so they are two labels at
## two sizes rather than one sentence with numbers buried in it.
func _on_targets_changed(_down: int, _total: int) -> void:
	## upper case because it is a caption naming the job, not a sentence being said to the player.
	objective_label.text = Run.objective_caption().to_upper()
	targets_label.text = Run.objective_count()


func _on_time_changed(seconds: float) -> void:
	timer_label.text = "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


## one arc per bird that is noticing you, drawn at its bearing, so you can tell WHICH one and
## turn the right way. a bar in the middle of the screen could never say that.
## the mission moved on. the caption and the count are Run's own two pieces, the same way the
## kiwi count always was; only the SIZES are the hud's business.
func _on_objectives_changed() -> void:
	if Run.state != Run.State.PLAYING:
		return
	objective_label.text = Run.objective_caption().to_upper()
	targets_label.text = Run.objective_count()


## a job on an objective is the same sentence as a reload -- something is running, wait for it -- so
## it gets the same ring round the same crosshair. it says it with the RING and with nothing else:
## words flashed in the middle of the screen were doing the ring's job twice, and the second time in
## a place the player is trying to see the compound through.
func _on_objective_working(which, active: bool) -> void:
	reload_ring.watch_job(which if active else null)
	_show_crosshair(not active and not _aiming)


## the ring going out IS the message. it appeared when the job started and it leaves when the job
## stops, which is the same fact either way round and needs no word for it.
func _on_objective_abandoned(_which) -> void:
	reload_ring.watch_job(null)
	_show_crosshair(not _aiming)


func _on_watcher_changed(kiwi: Node3D, value: float) -> void:
	alert_ring.set_watcher(kiwi, value)


## the ring carries the tier and nothing is written on the screen about it. a bird on the radio is a
## two second window and it still has to be READABLE, but the fast blinking arc says it better than
## words did: it says the same thing AND says which direction to shoot in, which a line in the middle
## of the screen never could.
func _on_watcher_tier(kiwi: Node3D, tier: int) -> void:
	alert_ring.set_tier(kiwi, tier)


## being spotted is an EVENT, so it is announced and then it goes. a line that sits there saying
## UNDETECTED for a whole mission is telling the player something they already know; the ring of
## arcs is what carries the live state, one arc per bird, at its bearing.
func _on_detections_changed(count: int) -> void:
	if _last_detections >= 0 and count > _last_detections:
		flash_status(Run.stealth_text(), HudStyle.ALERT)
	_last_detections = count


## hidden while the compound is calm. SEARCHING in the ring's amber, ALARM in its red, and the
## seconds to the reinforcements next to the word once they are counting. signals only, no polling.
func _on_alarm_stage(_stage: int) -> void:
	_refresh_alarm()


func _on_reinforcements(_seconds_left: float) -> void:
	_refresh_alarm()


func _refresh_alarm() -> void:
	if Alarm.stage == Alarm.Stage.CALM or Run.state != Run.State.PLAYING:
		alarm_label.text = ""
		return
	var text := Alarm.stage_name()
	var left := Alarm.reinforcements_left()
	if left >= 0.0:
		text += "   REINFORCEMENTS %s" % _clock(left)
	alarm_label.text = text
	alarm_label.add_theme_color_override("font_color",
		HudStyle.ALERT if Alarm.stage == Alarm.Stage.ALARM else HudStyle.HOT)


func alarm_text() -> String:
	return alarm_label.text


func flash_status(text: String, colour: Color) -> void:
	if _status_tween != null and _status_tween.is_valid():
		_status_tween.kill()
	status_label.text = text
	status_label.add_theme_color_override("font_color", colour)
	status_label.modulate.a = 1.0
	_status_tween = create_tween()
	_status_tween.tween_interval(1.8)
	_status_tween.tween_property(status_label, "modulate:a", 0.0, 0.5)


func _on_level_cleared(_index: int, summary: Dictionary) -> void:
	_clear_field_readout()
	report_card.play(summary, "MISSION CLEAR")
	alert_ring.clear()


## the same card, a different heading. the numbers still say what happened before the laser found you.
func _on_level_failed(_index: int, summary: Dictionary) -> void:
	_clear_field_readout()
	report_card.play(summary, "MISSION FAILED")
	alert_ring.clear()


func _on_run_finished(summary: Dictionary) -> void:
	_clear_field_readout()
	report_card.play(summary, "ALL MISSIONS COMPLETE")
	alert_ring.clear()


## the card carries the objective, the clock and the stealth line itself, so the field readout that
## was showing them stands down rather than competing with it.
func _clear_field_readout() -> void:
	objective_label.text = ""
	targets_label.text = ""
	timer_label.text = ""
	alarm_label.text = ""
	status_label.text = ""
	_last_detections = -1


func _clock(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


func _on_focus_changed(text: String, action: StringName, _target: Node) -> void:
	prompt_key.action = action
	prompt_label.text = text
	prompt_row.visible = true


func _on_focus_lost() -> void:
	prompt_label.text = ""
	prompt_row.visible = false


## the count is the hero and the figure after the slash hangs off it at a third of the size, which is
## the whole of the trick in the reference sheet: one number to read, one to check.
##
## that second figure is the RESERVE, not the magazine's capacity. it used to be the capacity, so a
## weapon with nothing in it and nothing to reload from read "0 / 30" -- and every shooter the player
## has ever touched uses that slot for rounds in the bag, so "0 / 30" says "thirty left". it said the
## exact opposite of the truth at the one moment the player most needs to know it.
func _on_ammo_changed(count: int, _capacity: int) -> void:
	ammo_label.text = "%d" % count
	capacity_label.text = "/ %d" % _reserve()
	_update_spare()


## rounds in the pouch that this weapon could reload from. the pouch owns the number.
func _reserve() -> int:
	if _weapon == null or _pouch == null:
		return 0
	return _pouch.rounds(_weapon.accepted_mag)


func _on_magazine_changed(mag: Magazine) -> void:
	if mag == null:
		type_label.text = "NO MAGAZINE"
		mass_label.text = "--"
		return
	type_label.text = "%s   %s" % [_weapon.weapon_model if _weapon != null else "", mag.type_label().to_upper()]
	mass_label.text = "%.2f g" % mag.mass_grams()
	pulse(mass_label)


func _on_fire_mode_changed(mode: Gun.FireMode) -> void:
	mode_label.text = "AUTO" if mode == Gun.FireMode.AUTO else "SEMI"
	var can_auto := _weapon != null and _weapon.allow_auto
	mode_icon.set_state(mode, can_auto)
	## the key hint fades on a weapon that has no second mode, so nobody hunts for a broken key
	mode_hint.modulate.a = 1.0 if can_auto else 0.35


## every shot throws the aim about a little, and the reticle opens by exactly one shot's worth.
## taken off the weapon's own signal, so it can never disagree with how many bbs left the barrel.
func _on_weapon_fired(_speed: float, _mass_kg: float) -> void:
	crosshair.bloom()


func _on_hopup_changed(value: float, min_value: float, max_value: float) -> void:
	var span := max_value - min_value
	var pct := 0.0 if span <= 0.0 else (value - min_value) / span * 100.0
	hopup_label.text = "HOP-UP  %.0f%%" % pct
	pulse(hopup_label)


func _on_fire_failed(reason: Gun.FireBlock, message: String) -> void:
	match reason:
		Gun.FireBlock.COOLDOWN:
			return
		Gun.FireBlock.EMPTY, Gun.FireBlock.NO_MAGAZINE:
			flash_ammo()
		_:
			show_message(message)


## the iron sights are the aiming device once you are looking down them, and the crosshair would
## sit right on the front post. it goes out faster than the weapon comes up.
func _on_aim_changed(aiming: bool) -> void:
	_aiming = aiming
	_show_crosshair(not aiming and not (reload_ring != null and reload_ring.is_showing()))


func _show_crosshair(on: bool) -> void:
	if _aim_tween != null and _aim_tween.is_valid():
		_aim_tween.kill()
	_aim_tween = create_tween()
	_aim_tween.tween_property(crosshair, "modulate:a", 1.0 if on else 0.0, 0.07)


## the ring takes the crosshair's place for the duration, then hands it back unless the player is aiming.
func _on_reload_started(_duration: float) -> void:
	_show_crosshair(false)


func _on_reload_finished(_mag: Magazine) -> void:
	_show_crosshair(not _aiming)
	_update_spare()


func _on_reload_cancelled() -> void:
	_show_crosshair(not _aiming)


func _on_spare_added(mag: Magazine) -> void:
	show_message("+1 %s magazine  %.2f g" % [mag.type_label(), mag.mass_grams()])


## the count is already on screen and it says x0. pointing at it beats a sentence saying the same.
func _on_reload_failed(_message: String) -> void:
	blink_spare()
	buzz()


## a full pouch keeps its sentence: the limit is a number the player sees nowhere else.
func _on_pouch_refused(message: String) -> void:
	show_message(message)
	blink_spare()
	buzz()


## a figure that lives at the bottom of the block in half tone, brightened for a moment when it
## changes. that is how the hop-up can answer the wheel without shouting for the rest of the run,
## and it stays on screen the whole time, which the brief requires and a fade out would break.
func pulse(label: Label) -> void:
	label.modulate = Color(1.7, 1.5, 0.95, 2.0)
	create_tween().tween_property(label, "modulate", Color.WHITE, 0.8)


func blink_spare() -> void:
	if _spare_tween != null and _spare_tween.is_valid():
		_spare_tween.kill()
	spare_label.modulate = ALERT_COLOR
	_spare_tween = create_tween()
	for _i in 3:
		_spare_tween.tween_property(spare_label, "modulate", Color.WHITE, 0.12)
		_spare_tween.tween_property(spare_label, "modulate", ALERT_COLOR, 0.12)
	_spare_tween.tween_property(spare_label, "modulate", Color.WHITE, 0.12)


func buzz() -> void:
	UiSfx.play("error")


## how many spares the weapon in hand can still reload from. the pouch owns the number.
func _update_spare() -> void:
	if _weapon == null or _pouch == null:
		spare_label.text = ""
		return
	## the reserve says how many ROUNDS are left; this says how many magazines they are spread over,
	## which is a different fact and the one that decides whether a reload is worth taking now.
	spare_label.text = _pouch.describe(_weapon.accepted_mag)
	capacity_label.text = "/ %d" % _reserve()


func flash_ammo() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	ammo_label.modulate = ALERT_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(ammo_label, "modulate", Color.WHITE, 0.35)


func _on_magazine_rejected(_offered: Magazine, message: String) -> void:
	show_message(message)


## drops whatever is on the message line right now, mid fade included.
func _clear_message() -> void:
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	message_label.text = ""
	message_label.modulate.a = 1.0


func show_message(text: String) -> void:
	message_label.text = text
	message_label.modulate.a = 1.0
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(1.2)
	_message_tween.tween_property(message_label, "modulate:a", 0.0, 0.4)
