extends Node3D

## the boot scene. the backdrop is live: the same sky as the game, a patch of grass and one kiwi
## standing on it doing its idle clips. the camera drifts so the frame is never a still.

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
	## the body's forward is -Z, which is what look_at points, so this is all it takes.
	var kiwi := $Kiwi as Node3D
	kiwi.look_at(Vector3(_rest.x, kiwi.global_position.y, _rest.z))


func _process(delta: float) -> void:
	_t += delta
	var angle := deg_to_rad(orbit_degrees) * sin(_t * TAU / orbit_period)
	## orbit the authored position rather than the live one, or float drift walks the camera away.
	var offset := _rest - focus
	_cam.position = focus + offset.rotated(Vector3.UP, angle)
	_cam.look_at(focus)
