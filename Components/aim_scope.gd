class_name AimScope
extends Node

## hold aim to bring the weapon up, narrow the camera and slow both movement and look.
## this node owns the camera fov, nothing else may write it.

signal aim_changed(aiming: bool)

@export var ads_fov := 52.0
@export var ads_in_speed := 12.0
## movement multiplier while fully aimed.
@export var ads_speed_mult := 0.55
## how far into the raise a TELESCOPIC sight takes over. below it the weapon is coming up like any
## other; above it the sight picture fades in and the weapon leaves the screen, because a scope is
## looked through rather than looked at (see HUD/scope_view.gd for why it is drawn and not modelled).
@export_range(0.0, 0.95, 0.05) var scope_at := 0.6

var _cam: Camera3D
var _viewmodel: ViewmodelMotion
## the fov the weapon in hand wants, which is ads_fov for anything without a telescope on it. read
## once when the weapon changes rather than every frame: what is in the player's hands is a fact
## that arrives on a signal, and asking the tree for it sixty times a second to get the same answer
## is the poll this project keeps out of anything that draws.
var _weapon_fov := 0.0
var _gun: Gun
## whether the sight picture is what took the weapon off the screen. without this the scope would
## hand back a weapon it never hid, and a HOLSTERED weapon would be made visible the moment the
## player switched to another one.
var _hid := false
var _base_fov := 75.0
var _t := 0.0
var _aiming := false
var _ready_ok := false


func _ready() -> void:
	add_to_group("aim_scope")
	## the camera marks itself current during the ready cascade, so read it one idle frame later.
	_late_setup.call_deferred()


func _late_setup() -> void:
	if not is_inside_tree():
		return
	_cam = get_viewport().get_camera_3d()
	_viewmodel = get_tree().get_first_node_in_group("viewmodel") as ViewmodelMotion
	var rack := get_tree().get_first_node_in_group("weapon_rack") as WeaponRack
	if rack != null:
		rack.weapon_changed.connect(_on_weapon_changed)
		_on_weapon_changed(rack.current())
	if _cam != null:
		_base_fov = _cam.fov
		_ready_ok = true


func _process(delta: float) -> void:
	if not _ready_ok:
		return

	## the pause menu stops this node, so the action alone decides. tying it to the captured mouse
	## made aiming impossible in an unfocused window, which is where the screenshots are taken.
	var want := Input.is_action_pressed("aim")
	if want != _aiming:
		_aiming = want
		aim_changed.emit(_aiming)
		Sfx.play_2d(&"ads")

	_t = move_toward(_t, 1.0 if _aiming else 0.0, ads_in_speed * delta)
	_cam.fov = lerpf(_base_fov, target_fov(), _t)

	if _viewmodel != null:
		_viewmodel.set_ads(_t)
	## the model comes off the screen once the sight picture is up. it is done here rather than in
	## the viewmodel because this node is the one that knows a telescope is involved at all, and the
	## rack only ever writes visibility when the weapon CHANGES, so the two never fight.
	if _gun != null and is_instance_valid(_gun):
		var hide := scope_amount() >= 0.5
		if hide != _hid:
			_hid = hide
			_gun.visible = not hide


func _on_weapon_changed(gun: Gun) -> void:
	## a weapon swapped away WHILE SCOPED would otherwise stay invisible in the player's hands for
	## the rest of the mission. only one this node hid is handed back, or holstering would be undone.
	if _hid and _gun != null and is_instance_valid(_gun):
		_gun.visible = true
	_hid = false
	_gun = gun
	_weapon_fov = gun.aim_fov if gun != null else 0.0


## 0 for a weapon with no telescope on it, and for one that is not being looked through yet; 1 with
## the eye fully on the glass. the hud draws the sight picture off this and nothing else.
func scope_amount() -> float:
	if _weapon_fov <= 0.0 or scope_at >= 1.0:
		return 0.0
	return clampf((_t - scope_at) / (1.0 - scope_at), 0.0, 1.0)


## what fully aimed means for the weapon in hand.
func target_fov() -> float:
	return _weapon_fov if _weapon_fov > 0.0 else ads_fov


## eased, 0 at the hip and 1 fully aimed.
func aim_amount() -> float:
	return _t


## raw intent, true the instant aim is pressed so a quick shot still counts as aimed.
func is_aiming() -> bool:
	return _aiming


func speed_mult() -> float:
	return lerpf(1.0, ads_speed_mult, _t)


## scales with the zoom so a narrower fov turns proportionally slower, which is what makes fine aim possible.
func sensitivity_mult() -> float:
	if not _ready_ok or _base_fov <= 0.0:
		return 1.0
	return clampf(_cam.fov / _base_fov, 0.05, 1.0)
