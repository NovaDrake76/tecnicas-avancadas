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
@onready var glass_row: HBoxContainer = %GlassRow
@onready var glass_key: KeyCap = %GlassKey
@onready var glass_label: Label = %Glass
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
@onready var damage_marks: DamageMarks = %DamageMarks
@onready var magazine_check: MagazineCheck = %MagazineCheck

var _weapon: Gun
var _interactor: Interactor
var _message_tween: Tween
var _flash_tween: Tween
var _aim_tween: Tween
var _spare_tween: Tween
var _aiming := false
var _last_detections := -1
var _status_tween: Tween
var _pouch: MagazinePouch
var _belt: UtilityBelt
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
	Alarm.stage_changed.connect(_on_alarm_stage)
	Alarm.reinforcements_changed.connect(_on_reinforcements)
	_refresh_alarm()
	Run.shot_hit.connect(hit_marker.strike)

	Net.local_player_ready.connect(func(_who: Node) -> void: _bind_weapon())
	_bind_weapon.call_deferred()


func _style() -> void:
	HudStyle.tune(type_label, HudStyle.T_LABEL, HudStyle.DIM)
	HudStyle.tune(ammo_label, HudStyle.T_HERO, HudStyle.BRIGHT)
	HudStyle.tune(capacity_label, HudStyle.T_UNIT, HudStyle.DIM)
	HudStyle.tune(spare_label, HudStyle.T_UNIT, HudStyle.DIM)
	HudStyle.tune(mode_label, HudStyle.T_VALUE, HudStyle.HOT)
	## the brief wants these permanently on screen ("exiba permanentemente"); they stay quiet and speak up on change.
	HudStyle.tune(mass_label, HudStyle.T_MICRO, HudStyle.FAINT)
	HudStyle.tune(hopup_label, HudStyle.T_MICRO, HudStyle.FAINT)
	HudStyle.tune(melee_label, HudStyle.T_MICRO, HudStyle.FAINT)
	HudStyle.tune(glass_label, HudStyle.T_MICRO, HudStyle.BRIGHT)
	HudStyle.tune(objective_label, HudStyle.T_LABEL, HudStyle.DIM)
	HudStyle.tune(targets_label, HudStyle.T_VALUE, HudStyle.BRIGHT)
	HudStyle.tune(timer_label, HudStyle.T_UNIT, HudStyle.FAINT)
	HudStyle.tune(alarm_label, HudStyle.T_LABEL, HudStyle.HOT)
	HudStyle.tune(status_label, HudStyle.T_VALUE, HudStyle.ALERT)
	HudStyle.tune(message_label, HudStyle.T_VALUE, HudStyle.HOT)
	HudStyle.tune(prompt_label, HudStyle.T_UNIT, HudStyle.BRIGHT)


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
	damage_marks.watch(Player.local(get_tree()))

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

	var hands := get_tree().get_first_node_in_group("takedown")
	if hands != null:
		hands.reach_changed.connect(_on_takedown_reach)
		hands.started.connect(func(_t: Node3D) -> void: pulse(melee_label))
	melee_row.visible = false

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

	var glass := get_tree().get_first_node_in_group("binoculars") as Binoculars
	if glass != null:
		glass_key.visible = false
		glass.raised_changed.connect(func(up: bool) -> void:
			glass_row.visible = up
			_update_glass(glass))
		glass.marked.connect(func(_bird: Node3D) -> void:
			_update_glass(glass)
			pulse(glass_label))
		glass.zoom_changed.connect(func() -> void: _update_glass(glass))
	glass_row.visible = false

	_belt = get_tree().get_first_node_in_group("utility") as UtilityBelt
	if _belt != null:
		_belt.changed.connect(_on_gear_changed)
	_sync_gear(true)


func _on_takedown_reach(within: bool) -> void:
	melee_row.visible = within
	if within:
		melee_label.add_theme_color_override("font_color", HudStyle.BRIGHT)
		melee_key.ink = HudStyle.BRIGHT
		melee_key.edge = Color(HudStyle.BRIGHT, 0.55)
		melee_key.refresh()
		pulse(melee_label)


func _update_glass(glass: Binoculars) -> void:
	if glass == null or not is_instance_valid(glass):
		return
	var n := glass.marked_count()
	glass_label.text = "ZOOM %.1fx    MARKED %d" % [glass.magnification(), n]


func _on_gear_changed() -> void:
	_sync_gear(false)


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
			var pick := KeyCap.new()
			pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pick.text_size = 19
			pick.action = UtilityBelt.key_for(id)
			row.add_child(pick)
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
	magazine_check.hide_check()
	_show_crosshair(not _aiming and not reload_ring.is_showing())
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
		["check_started", _on_check_started],
		["check_ended", _on_check_ended],
	]


func _on_check_started() -> void:
	magazine_check.show_for(_weapon, _pouch)
	_show_crosshair(false)


func _on_check_ended() -> void:
	magazine_check.hide_check()
	_show_crosshair(not _aiming and not reload_ring.is_showing())


func _on_level_started(_index: int, _name: String) -> void:
	report_card.hide_card()
	_on_detections_changed(0)
	alert_ring.clear()
	_clear_message()


func _on_armory_entered(_next_index: int, _name: String) -> void:
	report_card.hide_card()
	_clear_field_readout()
	alert_ring.clear()
	objective_label.text = "ARMORY"
	_clear_message()


func _on_targets_changed(_down: int, _total: int) -> void:
	objective_label.text = Run.objective_caption().to_upper()
	targets_label.text = Run.objective_count()


func _on_time_changed(seconds: float) -> void:
	timer_label.text = "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


func _on_objectives_changed() -> void:
	if Run.state != Run.State.PLAYING:
		return
	objective_label.text = Run.objective_caption().to_upper()
	targets_label.text = Run.objective_count()


func _on_objective_working(which, active: bool) -> void:
	reload_ring.watch_job(which if active else null)
	_show_crosshair(not active and not _aiming)


func _on_objective_abandoned(_which) -> void:
	reload_ring.watch_job(null)
	_show_crosshair(not _aiming)


func _on_watcher_changed(kiwi: Node3D, value: float) -> void:
	alert_ring.set_watcher(kiwi, value)


func _on_watcher_tier(kiwi: Node3D, tier: int) -> void:
	alert_ring.set_tier(kiwi, tier)


func _on_detections_changed(count: int) -> void:
	if _last_detections >= 0 and count > _last_detections:
		flash_status(Run.stealth_text(), HudStyle.ALERT)
	_last_detections = count


func _on_alarm_stage(stage: int) -> void:
	alert_ring.set_stage(stage)
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


func _on_level_failed(_index: int, summary: Dictionary) -> void:
	_clear_field_readout()
	report_card.play(summary, "MISSION FAILED")
	alert_ring.clear()


func _on_run_finished(summary: Dictionary) -> void:
	_clear_field_readout()
	report_card.play(summary, "ALL MISSIONS COMPLETE")
	alert_ring.clear()


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


func _on_ammo_changed(count: int, _capacity: int) -> void:
	ammo_label.text = "%d" % count
	capacity_label.text = "/ %d" % _reserve()
	_update_spare()


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
	mode_hint.modulate.a = 1.0 if can_auto else 0.35


func _on_weapon_fired(_speed: float, _mass_kg: float) -> void:
	crosshair.bloom()


func _on_hopup_changed(value: float, min_value: float, max_value: float) -> void:
	var span := max_value - min_value
	var pct := 0.0 if span <= 0.0 else (value - min_value) / span * 100.0
	hopup_label.text = "HOP-UP  %.0f%%" % pct
	pulse(hopup_label)


func _on_fire_failed(reason: Gun.FireBlock, message: String) -> void:
	match reason:
		Gun.FireBlock.COOLDOWN, Gun.FireBlock.CHECKING:
			return
		Gun.FireBlock.EMPTY, Gun.FireBlock.NO_MAGAZINE:
			flash_ammo()
		_:
			show_message(message)


func _on_aim_changed(aiming: bool) -> void:
	_aiming = aiming
	_show_crosshair(not aiming and not (reload_ring != null and reload_ring.is_showing()))


func _show_crosshair(on: bool) -> void:
	if _weapon != null and is_instance_valid(_weapon) and not _weapon.hip_reticle:
		on = false
	if _aim_tween != null and _aim_tween.is_valid():
		_aim_tween.kill()
	_aim_tween = create_tween()
	_aim_tween.tween_property(crosshair, "modulate:a", 1.0 if on else 0.0, 0.07)


func _on_reload_started(_duration: float) -> void:
	_show_crosshair(false)


func _on_reload_finished(_mag: Magazine) -> void:
	_show_crosshair(not _aiming)
	_update_spare()


func _on_reload_cancelled() -> void:
	_show_crosshair(not _aiming)


func _on_spare_added(mag: Magazine) -> void:
	show_message("+1 %s magazine  %.2f g" % [mag.type_label(), mag.mass_grams()])


func _on_reload_failed(_message: String) -> void:
	blink_spare()
	buzz()


func _on_pouch_refused(message: String) -> void:
	show_message(message)
	blink_spare()
	buzz()


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


func _update_spare() -> void:
	if _weapon == null or _pouch == null:
		spare_label.text = ""
		return
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
