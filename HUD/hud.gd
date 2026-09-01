extends CanvasLayer

const ALERT_COLOR := Color(1.0, 0.35, 0.3)

@onready var type_label: Label = %Type
@onready var ammo_label: Label = %Ammo
@onready var mass_label: Label = %Mass
@onready var mode_label: Label = %Mode
@onready var hopup_label: Label = %Hopup
@onready var message_label: Label = %Message
@onready var prompt_label: Label = %Prompt

var _weapon: Gun
var _interactor: Interactor
var _message_tween: Tween
var _flash_tween: Tween


func _ready() -> void:
	message_label.text = ""
	prompt_label.text = ""
	_bind_weapon.call_deferred()


func _bind_weapon() -> void:
	_weapon = get_tree().get_first_node_in_group("weapon") as Gun
	if _weapon == null:
		push_warning("hud.gd: no node in group 'weapon'; HUD will stay blank.")
		return

	_weapon.ammo_changed.connect(_on_ammo_changed)
	_weapon.magazine_changed.connect(_on_magazine_changed)
	_weapon.fire_mode_changed.connect(_on_fire_mode_changed)
	_weapon.hopup_changed.connect(_on_hopup_changed)
	_weapon.fire_failed.connect(_on_fire_failed)
	_weapon.magazine_rejected.connect(_on_magazine_rejected)
	_weapon.emit_state()

	_interactor = get_tree().get_first_node_in_group("interactor") as Interactor
	if _interactor != null:
		_interactor.focus_changed.connect(_on_focus_changed)
		_interactor.focus_lost.connect(_on_focus_lost)


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
	type_label.text = mag.type_label().to_upper()
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
