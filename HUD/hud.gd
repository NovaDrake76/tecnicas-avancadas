extends CanvasLayer

const ALERT_COLOR := Color(1.0, 0.35, 0.3)
const CLEAR_COLOR := Color(0.55, 0.85, 0.6)

@onready var type_label: Label = %Type
@onready var ammo_label: Label = %Ammo
@onready var mass_label: Label = %Mass
@onready var mode_label: Label = %Mode
@onready var hopup_label: Label = %Hopup
@onready var message_label: Label = %Message
@onready var prompt_label: Label = %Prompt
@onready var objective_label: Label = %Objective
@onready var timer_label: Label = %Timer
@onready var banner_label: Label = %Banner
@onready var summary_label: Label = %Summary
@onready var alert_ring: AlertRing = %AlertRing
@onready var stealth_label: Label = %Stealth
@onready var crosshair: Label = %Crosshair

var _weapon: Gun
var _interactor: Interactor
var _message_tween: Tween
var _flash_tween: Tween
var _aim_tween: Tween


func _ready() -> void:
	add_to_group("hud")
	message_label.text = ""
	prompt_label.text = ""
	banner_label.text = ""
	summary_label.text = ""
	objective_label.text = ""
	timer_label.text = ""
	stealth_label.text = ""
	alert_ring.clear()

	Run.level_started.connect(_on_level_started)
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
	]


func _on_level_started(index: int, name: String) -> void:
	banner_label.text = ""
	summary_label.text = ""
	_on_detections_changed(0)
	alert_ring.clear()
	show_message("Level %d  %s" % [index + 1, name])


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
	banner_label.text = "LEVEL CLEAR"
	summary_label.text = _summary_text(summary)
	alert_ring.clear()


func _on_run_finished(summary: Dictionary) -> void:
	banner_label.text = "MISSION COMPLETE"
	summary_label.text = _summary_text(summary)
	objective_label.text = ""
	stealth_label.text = ""
	alert_ring.clear()


## every line is something the player did, so the score can be explained back to them.
func _summary_text(s: Dictionary) -> String:
	var seen := int(s["detections"])
	var stealth := "undetected" if seen == 0 else "spotted by %d" % seen
	return "targets %d / %d          shots %d          accuracy %d%%
time %s   (par %s)          %s   +%d

level %d          run %d" % [
		int(s["targets"]), int(s["total"]), int(s["shots"]), int(round(float(s["accuracy"]) * 100.0)),
		_clock(float(s["time"])), _clock(float(s["par"])), stealth, int(s["stealth"]),
		int(s["level_score"]), int(s["run_score"])]


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
	if _aim_tween != null and _aim_tween.is_valid():
		_aim_tween.kill()
	_aim_tween = create_tween()
	_aim_tween.tween_property(crosshair, "modulate:a", 0.0 if aiming else 1.0, 0.07)


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
