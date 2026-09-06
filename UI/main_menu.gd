extends Node3D


@export var orbit_degrees := 6.0
@export var orbit_period := 28.0
@export var focus := Vector3(-0.55, 0.3, 0.0)

@onready var _cam: Camera3D = $Camera3D

var _rest: Vector3
var _t := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Fade.uncover()
	Score.menu_theme()
	_rest = _cam.position
	_cam.look_at(focus)
	var kiwi := $Kiwi as Node3D
	kiwi.look_at(Vector3(_rest.x, kiwi.global_position.y, _rest.z))


func _process(delta: float) -> void:
	_t += delta
	var angle := deg_to_rad(orbit_degrees) * sin(_t * TAU / orbit_period)
	var offset := _rest - focus
	_cam.position = focus + offset.rotated(Vector3.UP, angle)
	_cam.look_at(focus)
