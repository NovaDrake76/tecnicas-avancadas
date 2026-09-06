class_name AimScope
extends Node


signal aim_changed(aiming: bool)

@export var ads_fov := 52.0
@export var ads_in_speed := 12.0
## movement multiplier while fully aimed.
@export var ads_speed_mult := 0.55
## how far into the raise a TELESCOPIC sight takes over.
@export_range(0.0, 0.95, 0.05) var scope_at := 0.6
## an optic the player HOLDS instead of the weapon -- the binoculars.
@export var optic_in_speed := 5.0

var _cam: Camera3D
var _viewmodel: ViewmodelMotion
var _weapon_fov := 0.0
var _gun: Gun
var _hid := false
var _base_fov := 75.0
var _optic_fov := 0.0
var _t := 0.0
var _aiming := false
var _ready_ok := false


func _ready() -> void:
	add_to_group("aim_scope")
	## the camera marks itself current during the ready cascade, so it is read one idle frame later.
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

	var glassing := _optic_fov > 0.0
	var want := glassing or Input.is_action_pressed("aim")
	if want != _aiming:
		_aiming = want
		aim_changed.emit(_aiming)
		if not glassing:
			Sfx.play_2d(&"ads")

	_t = move_toward(_t, 1.0 if want else 0.0, (optic_in_speed if glassing else ads_in_speed) * delta)
	_cam.fov = lerpf(_base_fov, target_fov(), _t)

	if _viewmodel != null:
		_viewmodel.set_ads(_t)
	if _gun != null and is_instance_valid(_gun):
		var hide := scope_amount() >= 0.5 or (glassing and _t >= 0.5)
		if hide != _hid:
			_hid = hide
			_gun.visible = not hide


func _on_weapon_changed(gun: Gun) -> void:
	if _hid and _gun != null and is_instance_valid(_gun):
		_gun.visible = true
	_hid = false
	_gun = gun
	_weapon_fov = gun.aim_fov if gun != null else 0.0


func scope_amount() -> float:
	if _weapon_fov <= 0.0 or scope_at >= 1.0:
		return 0.0
	return clampf((_t - scope_at) / (1.0 - scope_at), 0.0, 1.0)


func target_fov() -> float:
	if _optic_fov > 0.0:
		return _optic_fov
	return _weapon_fov if _weapon_fov > 0.0 else ads_fov


func raise_optic(fov: float) -> void:
	_optic_fov = maxf(fov, 1.0)


func lower_optic() -> void:
	_optic_fov = 0.0


func has_optic() -> bool:
	return _optic_fov > 0.0


func base_fov() -> float:
	return _base_fov


func aim_amount() -> float:
	return _t


func is_aiming() -> bool:
	return _aiming


func speed_mult() -> float:
	return lerpf(1.0, ads_speed_mult, _t)


func sensitivity_mult() -> float:
	if not _ready_ok or _base_fov <= 0.0:
		return 1.0
	return clampf(_cam.fov / _base_fov, 0.05, 1.0)
