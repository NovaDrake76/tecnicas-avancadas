class_name Binoculars
extends Node


signal raised_changed(up: bool)
signal zoom_changed()
signal marked(bird: Node3D)

## the zoom, as MAGNIFICATION rather than as a field of view, because that is the number a pair of binoculars is sold by...
@export var zoom_min := 2.0
@export var zoom_max := 8.0
## one notch of the wheel, as a factor.
@export var zoom_step := 1.15
## how fast the view settles on a new zoom.
@export var zoom_speed := 14.0
## how long the reticle has to stay on a bird before the tag takes.
@export var mark_time := 0.45
## how far a tag can be taken from.
@export var mark_range := 140.0
## how far off the middle of the view a bird may be and still be the one being looked at.
@export var mark_cone_deg := 3.0
## how long a tag lasts.
@export var tag_time := 25.0
## raising them is not instant, so they are never a free look in the middle of a fight.
@export var settle := 0.25

var _player: Player
var _aim: AimScope
var _up := false
var _want := 3.0
var _mag := 3.0
var _said := 0.0
var _held := 0.0
var _dwell := 0.0
var _target: Kiwi


func _ready() -> void:
	add_to_group("binoculars")
	_player = get_parent() as Player
	_aim = get_tree().get_first_node_in_group("aim_scope") as AimScope


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("binoculars"):
		set_raised(not _up)
		get_viewport().set_input_as_handled()
		return
	if not _up:
		return
	if event is InputEventMouseButton and event.is_pressed():
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(zoom_step)
			get_viewport().set_input_as_handled()
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / zoom_step)
			get_viewport().set_input_as_handled()
			return
	for action in ["fire", "aim", "reload", "throw", "takedown", "interact"]:
		if event.is_action_pressed(action):
			set_raised(false)
			get_viewport().set_input_as_handled()
			return


func set_raised(up: bool) -> void:
	if up == _up:
		return
	if up and (_player == null or _player.is_down()):
		return
	_up = up
	_held = 0.0
	_dwell = 0.0
	_target = null
	if _aim != null and is_instance_valid(_aim):
		if _up:
			_mag = _want
			_said = _mag
			_apply_fov()
		else:
			_aim.lower_optic()
	Sfx.play_2d(&"binocs_up" if _up else &"binocs_down")
	raised_changed.emit(_up)


func _zoom_by(factor: float) -> void:
	var was := _want
	_want = clampf(_want * factor, zoom_min, zoom_max)
	if not is_equal_approx(was, _want):
		UiSfx.play("switch")


func set_magnification(mag: float) -> void:
	_want = clampf(mag, zoom_min, zoom_max)
	_mag = _want
	_apply_fov()
	zoom_changed.emit()


func _fov_for(mag: float) -> float:
	var wide := _aim.base_fov() if _aim != null and is_instance_valid(_aim) else 75.0
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(wide * 0.5)) / maxf(mag, 0.01)))


func _apply_fov() -> void:
	if _aim != null and is_instance_valid(_aim):
		_aim.raise_optic(_fov_for(_mag))


func _process(delta: float) -> void:
	if not _up:
		return
	var state := Run.state
	var over := state == Run.State.CLEARED or state == Run.State.FAILED or state == Run.State.FINISHED
	if over or _player == null or _player.is_down():
		set_raised(false)
		return
	if Input.is_action_pressed("sprint") and _player.is_grounded():
		set_raised(false)
		return
	if not is_equal_approx(_mag, _want):
		_mag = lerpf(_mag, _want, 1.0 - exp(-zoom_speed * delta))
		if absf(_mag - _want) < 0.005:
			_mag = _want
		_apply_fov()
		if absf(_mag - _said) > 0.05:
			_said = _mag
			zoom_changed.emit()

	_held += delta
	if _held < settle:
		return
	var seen := _under_reticle()
	if seen != _target:
		_target = seen
		_dwell = 0.0
	if _target == null:
		return
	if _target.is_marked():
		return
	_dwell += delta
	if _dwell >= mark_time:
		_dwell = 0.0
		_target.net_mark.rpc(tag_time)
		UiSfx.play("tick")
		marked.emit(_target)


func _under_reticle() -> Kiwi:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _player == null:
		return null
	var eye := cam.global_position
	var ahead := -cam.global_transform.basis.z
	var best: Kiwi = null
	var near := INF
	var space := _player.get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group("kiwi"):
		var bird := node as Kiwi
		if bird == null or not is_instance_valid(bird) or bird.is_down():
			continue
		var at := bird.global_position + Vector3.UP * 0.3
		var away := at - eye
		var d := away.length()
		if d > mark_range or d < 0.5 or d >= near:
			continue
		if rad_to_deg(ahead.angle_to(away)) > mark_cone_deg:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, at, 1)
		if not space.intersect_ray(query).is_empty():
			continue
		near = d
		best = bird
	return best


func is_raised() -> bool:
	return _up


func amount() -> float:
	if _aim == null or not is_instance_valid(_aim):
		return 1.0 if _up else 0.0
	return _aim.aim_amount() if _up else 0.0


func magnification() -> float:
	return _mag


func marked_count() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("kiwi"):
		var bird := node as Kiwi
		if bird != null and is_instance_valid(bird) and bird.is_marked():
			n += 1
	return n


func dwell() -> float:
	return clampf(_dwell / maxf(mark_time, 0.01), 0.0, 1.0)


func target() -> Kiwi:
	return _target
