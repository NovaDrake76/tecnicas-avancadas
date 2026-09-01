class_name AimScope
extends Node

## hold aim to bring the weapon up, narrow the camera and slow both movement and look.
## this node owns the camera fov, nothing else may write it.

signal aim_changed(aiming: bool)

@export var ads_fov := 52.0
@export var ads_in_speed := 12.0
## movement multiplier while fully aimed.
@export var ads_speed_mult := 0.55

var _cam: Camera3D
var _viewmodel: ViewmodelMotion
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
	if _cam != null:
		_base_fov = _cam.fov
		_ready_ok = true


func _process(delta: float) -> void:
	if not _ready_ok:
		return

	var want := Input.is_action_pressed("aim") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if want != _aiming:
		_aiming = want
		aim_changed.emit(_aiming)

	_t = move_toward(_t, 1.0 if _aiming else 0.0, ads_in_speed * delta)
	_cam.fov = lerpf(_base_fov, ads_fov, _t)

	if _viewmodel != null:
		_viewmodel.set_ads(_t)


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
