extends CanvasLayer

const ALERT_COLOR := Color(1.0, 0.35, 0.3)
const CLEAR_COLOR := Color(0.55, 0.85, 0.6)

@onready var type_label: Label = %Type
@onready var ammo_label: Label = %Ammo
@onready var capacity_label: Label = %Capacity
@onready var mass_label: Label = %Mass
@onready var mode_label: Label = %Mode
@onready var mode_icon: FireModeIcon = %ModeIcon
@onready var mode_hint: Label = %ModeHint
@onready var hopup_label: Label = %Hopup
@onready var gear_label: Label = %Gear
@onready var message_label: Label = %Message
@onready var prompt_label: Label = %Prompt
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


func _ready() -> void:
	add_to_group("hud")
	message_label.text = ""
	prompt_label.text = ""
	_style()
	_clear_field_readout()
	alert_ring.clear()
	## the key is read off the input map instead of typed into the scene, so a rebind can
	## never leave the hud telling the player to press a key that does nothing.
	mode_hint.text = "[%s]" % _key_label(&"toggle_fire_mode")

	Run.level_started.connect(_on_level_started)
	report_card.dismissed.connect(func() -> void: Run.dismiss_results())
	Run.armory_entered.connect(_on_armory_entered)
	Run.targets_changed.connect(_on_targets_changed)
	Run.time_changed.connect(_on_time_changed)
	Run.level_cleared.connect(_on_level_cleared)
	Run.level_failed.connect(_on_level_failed)
	Run.run_finished.connect(_on_run_finished)
	Run.watcher_changed.connect(_on_watcher_changed)
	Run.detections_changed.connect(_on_detections_changed)
	## the ring says WHO is noticing you; this strip says HOW BAD it is for the whole compound, and
	## how long until it gets worse. the two do not overlap.
	Alarm.stage_changed.connect(_on_alarm_stage)
	Alarm.reinforcements_changed.connect(_on_reinforcements)
	_refresh_alarm()
	## the bb that landed is the only thing that knows what it landed on, and it is gone a frame
	## later. Run carries the word across because it is the one node both ends already know.
	Run.shot_hit.connect(hit_marker.strike)

	_bind_weapon.call_deferred()


## every size and colour comes from HudStyle rather than from a theme override typed into the
## scene, so the scale stays in one file and a new label cannot invent a fourteenth size.
func _style() -> void:
	HudStyle.tune(type_label, HudStyle.T_LABEL, HudStyle.DIM)
	HudStyle.tune(ammo_label, HudStyle.T_HERO, HudStyle.BRIGHT)
	HudStyle.tune(capacity_label, HudStyle.T_UNIT, HudStyle.DIM)
	HudStyle.tune(spare_label, HudStyle.T_UNIT, HudStyle.DIM)
	HudStyle.tune(mode_hint, HudStyle.T_LABEL, HudStyle.FAINT)
	HudStyle.tune(mode_label, HudStyle.T_VALUE, HudStyle.HOT)
	## the brief wants these two permanently on screen. they stay, quietly, and speak up on change.
	HudStyle.tune(mass_label, HudStyle.T_MICRO, HudStyle.FAINT)
	HudStyle.tune(hopup_label, HudStyle.T_MICRO, HudStyle.FAINT)
	HudStyle.tune(gear_label, HudStyle.T_MICRO, HudStyle.FAINT)
	HudStyle.tune(objective_label, HudStyle.T_LABEL, HudStyle.DIM)
	HudStyle.tune(targets_label, HudStyle.T_VALUE, HudStyle.BRIGHT)
	HudStyle.tune(timer_label, HudStyle.T_UNIT, HudStyle.FAINT)
	HudStyle.tune(alarm_label, HudStyle.T_LABEL, HudStyle.HOT)
	HudStyle.tune(status_label, HudStyle.T_VALUE, HudStyle.ALERT)
	HudStyle.tune(message_label, HudStyle.T_VALUE, HudStyle.HOT)
	HudStyle.tune(prompt_label, HudStyle.T_UNIT, HudStyle.BRIGHT)


func _bind_weapon() -> void:
	var rack := get_tree().get_first_node_in_group("weapon_rack") as WeaponRack
	if rack != null:
		rack.weapon_changed.connect(_follow_weapon)
		_follow_weapon(rack.current())
	else:
		_follow_weapon(get_tree().get_first_node_in_group("weapon") as Gun)
	if _weapon == null:
		push_warning("hud.gd: no weapon to follow; HUD will stay blank.")

	vitals.watch(get_tree().get_first_node_in_group("player"))

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

	## the thrown magazines sit with the other quiet figures and speak up when one is thrown
	var throw := get_tree().get_first_node_in_group("distraction")
	if throw != null:
		throw.changed.connect(_on_gear_changed)
		_on_gear_changed(throw.count, throw.max_count)


func _on_gear_changed(count: int, max_count: int) -> void:
	gear_label.text = "[%s] MAG  x%d" % [_key_label(&"throw"), count] if max_count > 0 else ""
	pulse(gear_label)


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
	timer_label.text = "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


## one arc per bird that is noticing you, drawn at its bearing, so you can tell WHICH one and
## turn the right way. a bar in the middle of the screen could never say that.
func _on_watcher_changed(kiwi: Node3D, value: float) -> void:
	alert_ring.set_watcher(kiwi, value)


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
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func _on_focus_changed(text: String, action: StringName, _target: Node) -> void:
	prompt_label.text = "[%s]  %s" % [_key_label(action), text]


func _on_focus_lost() -> void:
	prompt_label.text = ""


## resolves the bound key so the prompt still reads correctly after a rebind.
func _key_label(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return OS.get_keycode_string((event as InputEventKey).physical_keycode)
	return String(action).to_upper()


## the count is the hero and the capacity hangs off it at a third of the size, which is the whole
## of the trick in the reference sheet: one number to read, one to check.
func _on_ammo_changed(count: int, capacity: int) -> void:
	ammo_label.text = "%d" % count
	capacity_label.text = "/ %d" % capacity


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
	spare_label.text = _pouch.describe(_weapon.accepted_mag)


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
