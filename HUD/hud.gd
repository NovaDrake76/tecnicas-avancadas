extends CanvasLayer

const ALERT_COLOR := Color(1.0, 0.35, 0.3)
const CLEAR_COLOR := Color(0.55, 0.85, 0.6)

@onready var type_label: Label = %Type
@onready var ammo_label: Label = %Ammo
@onready var mass_label: Label = %Mass
@onready var mode_label: Label = %Mode
@onready var mode_icon: FireModeIcon = %ModeIcon
@onready var mode_hint: Label = %ModeHint
@onready var hopup_label: Label = %Hopup
@onready var message_label: Label = %Message
@onready var prompt_label: Label = %Prompt
@onready var objective_label: Label = %Objective
@onready var timer_label: Label = %Timer
@onready var report_card: ReportCard = %ReportCard
@onready var alert_ring: AlertRing = %AlertRing
@onready var stealth_label: Label = %Stealth
@onready var crosshair: Label = %Crosshair
@onready var spare_label: Label = %Spare
@onready var reload_ring: ReloadRing = %ReloadRing

var _weapon: Gun
var _interactor: Interactor
var _message_tween: Tween
var _flash_tween: Tween
var _aim_tween: Tween
var _spare_tween: Tween
var _aiming := false
var _pouch: MagazinePouch


func _ready() -> void:
	add_to_group("hud")
	message_label.text = ""
	prompt_label.text = ""
	objective_label.text = ""
	timer_label.text = ""
	stealth_label.text = ""
	alert_ring.clear()

	Run.level_started.connect(_on_level_started)
	Run.armory_entered.connect(_on_armory_entered)
	Run.targets_changed.connect(_on_targets_changed)
	Run.time_changed.connect(_on_time_changed)
	Run.level_cleared.connect(_on_level_cleared)
	Run.run_finished.connect(_on_run_finished)
	Run.watcher_changed.connect(_on_watcher_changed)
	Run.detections_changed.connect(_on_detections_changed)

	_bind_weapon.call_deferred()


func _bind_weapon() -> void:
	var rack := get_tree().get_first_node_in_group("weapon_rack") as WeaponRack
	if rack != null:
		rack.weapon_changed.connect(_follow_weapon)
		_follow_weapon(rack.current())
	else:
		_follow_weapon(get_tree().get_first_node_in_group("weapon") as Gun)
	if _weapon == null:
		push_warning("hud.gd: no weapon to follow; HUD will stay blank.")

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
	_update_spare()
	show_message(_weapon.weapon_model)


func _weapon_signals() -> Array:
	return [
		["ammo_changed", _on_ammo_changed],
		["magazine_changed", _on_magazine_changed],
		["fire_mode_changed", _on_fire_mode_changed],
		["hopup_changed", _on_hopup_changed],
		["fire_failed", _on_fire_failed],
		["magazine_rejected", _on_magazine_rejected],
		["mode_refused", show_message],
		["reload_started", _on_reload_started],
		["reload_finished", _on_reload_finished],
		["reload_cancelled", _on_reload_cancelled],
		["reload_failed", _on_reload_failed],
	]


func _on_level_started(index: int, name: String) -> void:
	report_card.hide_card()
	_on_detections_changed(0)
	alert_ring.clear()
	show_message("Level %d  %s" % [index + 1, name])


func _on_armory_entered(next_index: int, name: String) -> void:
	report_card.hide_card()
	timer_label.text = ""
	stealth_label.text = ""
	alert_ring.clear()
	objective_label.text = "ARMORY"
	show_message("Bench: your kit.   Board: pick a mission.   Range: test it.")


func _on_targets_changed(_down: int, _total: int) -> void:
	objective_label.text = Run.objective_text()


func _on_time_changed(seconds: float) -> void:
	timer_label.text = "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


## one arc per bird that is noticing you, drawn at its bearing, so you can tell WHICH one and
## turn the right way. a bar in the middle of the screen could never say that.
func _on_watcher_changed(kiwi: Node3D, value: float) -> void:
	alert_ring.set_watcher(kiwi, value)


func _on_detections_changed(count: int) -> void:
	stealth_label.text = Run.stealth_text()
	stealth_label.modulate = ALERT_COLOR if count > 0 else CLEAR_COLOR


func _on_level_cleared(_index: int, summary: Dictionary) -> void:
	_clear_field_readout()
	report_card.play(summary, "MISSION CLEAR")
	alert_ring.clear()


func _on_run_finished(summary: Dictionary) -> void:
	_clear_field_readout()
	report_card.play(summary, "ALL MISSIONS COMPLETE")
	alert_ring.clear()


## the card carries the objective, the clock and the stealth line itself, so the field readout that
## was showing them stands down rather than competing with it.
func _clear_field_readout() -> void:
	objective_label.text = ""
	timer_label.text = ""
	stealth_label.text = ""


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


func _on_ammo_changed(count: int, capacity: int) -> void:
	ammo_label.text = "%d / %d" % [count, capacity]


func _on_magazine_changed(mag: Magazine) -> void:
	if mag == null:
		type_label.text = "NO MAGAZINE"
		mass_label.text = "--"
		return
	type_label.text = "%s   %s" % [_weapon.weapon_model if _weapon != null else "", mag.type_label().to_upper()]
	mass_label.text = "%.2f g" % mag.mass_grams()


func _on_fire_mode_changed(mode: Gun.FireMode) -> void:
	mode_label.text = "AUTO" if mode == Gun.FireMode.AUTO else "SEMI"
	var can_auto := _weapon != null and _weapon.allow_auto
	mode_icon.set_state(mode, can_auto)
	## the key hint fades on a weapon that has no second mode, so nobody hunts for a broken key
	mode_hint.modulate.a = 1.0 if can_auto else 0.35


func _on_hopup_changed(value: float, min_value: float, max_value: float) -> void:
	var span := max_value - min_value
	var pct := 0.0 if span <= 0.0 else (value - min_value) / span * 100.0
	hopup_label.text = "HOP-UP  %.0f%%  (%.5f)" % [pct, value]


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


func show_message(text: String) -> void:
	message_label.text = text
	message_label.modulate.a = 1.0
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(1.2)
	_message_tween.tween_property(message_label, "modulate:a", 0.0, 0.4)
