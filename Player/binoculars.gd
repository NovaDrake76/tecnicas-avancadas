class_name Binoculars
extends Node

## the recon verb: raise them, hold the reticle on a bird for a moment, and it is MARKED -- drawn on
## screen with what it is and how far away, through whatever is in the way, for as long as the tag
## lasts.
##
## the reference is the same shelf the rest of this game reads from, and they all landed in the same
## place. Wildlands and Breakpoint: binoculars magnify and TAG, and a tagged enemy stays on screen
## for the squad. MGSV: the binoculars mark a soldier, and marking is also how you learn he is a
## sniper rather than a rifleman. Far Cry: the camera tags, and tagged men show through walls. Arma
## and DayZ magnify and range and tag nothing, which is a simulator's answer rather than a game's.
## The common half is the interesting one: **magnification alone is not a mechanic**. Zoom tells the
## player something they could have learned by walking closer; the MARK is what turns looking into
## planning, because it survives them putting the binoculars down and moving.
##
## it fits this game better than it fits most. every bird here shares one model -- a plain sentry, a
## laser kiwi, a sniper and a mortar crew are the same mesh -- and until now the only way to tell a
## laser kiwi from a sentry at range was a faint green glow in its eyes. So the tag does not just say
## WHERE, it says WHAT, and that is a real answer to a real problem rather than an icon for its own
## sake. It is also the co-op verb this game did not have: a mark is shared, so "the one by the
## container" stops being a sentence two players have to get right out loud.
##
## the price is the standard one and it is genuine. Both hands are up, the weapon is off the screen,
## the view is a tunnel, movement is down to a walk, and none of the arcs that say who has noticed
## you are hidden -- a player glassing a compound is the most findable they will ever be. Nothing had
## to be invented to make that true.

signal raised_changed(up: bool)
signal zoom_changed()
signal marked(bird: Node3D)

## the zoom, as MAGNIFICATION rather than as a field of view, because that is the number a pair of
## binoculars is sold by and the number on screen. 2x to 8x covers a 7x50 pair, which is what a
## soldier actually carries; the bottom of the range exists because 8x is unusable for sweeping a
## treeline and the top because reading a compound is the whole job.
@export var zoom_min := 2.0
@export var zoom_max := 8.0
## one notch of the wheel, as a factor. geometric rather than a fixed number of degrees: a notch at
## 2x and a notch at 8x should feel like the same amount of zoom, and in degrees they are not.
@export var zoom_step := 1.15
## how fast the view settles on a new zoom. exponential, so it is the same at any frame rate.
@export var zoom_speed := 14.0
## how long the reticle has to stay on a bird before the tag takes. it is not a delay, it is the
## thing that makes marking a whole compound cost real seconds standing still.
@export var mark_time := 0.45
## how far a tag can be taken from. further than a kiwi can see you (45 m) on purpose: reading a
## compound from outside its own sight is the entire point of owning binoculars.
@export var mark_range := 140.0
## how far off the middle of the view a bird may be and still be the one being looked at. small,
## because "what am I pointing at" must never be a guess.
@export var mark_cone_deg := 3.0
## how long a tag lasts. long enough to plan a route on, short enough that a compound marked once is
## not marked for the rest of the mission.
@export var tag_time := 25.0
## raising them is not instant, so they are never a free look in the middle of a fight.
@export var settle := 0.25

var _player: Player
var _aim: AimScope
var _up := false
## what the wheel has asked for, and what the eye is actually at. the second chases the first, which
## is what makes the zoom continuous rather than a pair of steps.
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
	## the WHEEL is the zoom, and this is the brief's own rule rather than a liberty taken with it:
	## "garanta que o scroll nao altere o Hop-up enquanto o jogador estiver interagindo com outra
	## interface". A pair of binoculars on your face is that other interface. The event is eaten here
	## and the gun refuses it as well -- the refusal is the rule and eating it is hygiene, because a
	## rule that depends on which node the tree happens to visit first is not a rule.
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
	## anything that is a decision to stop looking and start doing puts them down. the press is
	## eaten so the first click is "put these away" rather than a shot fired through a lens.
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
			## they come up where they were last left, the way a lens keeps its setting.
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


## set the magnification outright, for anything that places the view rather than plays it.
func set_magnification(mag: float) -> void:
	_want = clampf(mag, zoom_min, zoom_max)
	_mag = _want
	_apply_fov()
	zoom_changed.emit()


## the field of view this magnification is, worked out from the one the player walks around with so
## the number on screen and the picture behind it can never be describing different lenses.
func _fov_for(mag: float) -> float:
	var wide := _aim.base_fov() if _aim != null and is_instance_valid(_aim) else 75.0
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(wide * 0.5)) / maxf(mag, 0.01)))


func _apply_fov() -> void:
	if _aim != null and is_instance_valid(_aim):
		_aim.raise_optic(_fov_for(_mag))


func _process(delta: float) -> void:
	if not _up:
		return
	## a mission that is OVER puts them away, and so does this operative going down. the test is
	## which states are FINISHED and not "is the run playing": the first version asked for PLAYING,
	## which is also false in the SAFE HOUSE, so pressing B on the range raised them and dropped them
	## in the same frame and the whole tool read as a screen that trembled and did nothing. the
	## armoury is a perfectly good place to look through a pair of binoculars, and it is the first
	## place anybody presses the key.
	var state := Run.state
	var over := state == Run.State.CLEARED or state == Run.State.FAILED or state == Run.State.FINISHED
	if over or _player == null or _player.is_down():
		set_raised(false)
		return
	## running with binoculars on your face is not a thing, and it is also the player's own way out
	## of them: the key that gets you moving puts them down.
	if Input.is_action_pressed("sprint") and _player.is_grounded():
		set_raised(false)
		return
	## the eye chases the wheel rather than jumping to it, which is the whole of "dynamic": a notch
	## is a nudge on a lens and not a second pair of binoculars.
	if not is_equal_approx(_mag, _want):
		_mag = lerpf(_mag, _want, 1.0 - exp(-zoom_speed * delta))
		if absf(_mag - _want) < 0.005:
			_mag = _want
		_apply_fov()
		## the footer reads the magnification off this rather than off the wheel, so what is printed
		## is the lens the player is actually looking through and not the one they asked for.
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
		## a mark is shared knowledge between the two operatives and nothing else: it does not hurt
		## anybody, does not move a bird and does not touch the alarm, so it needs no host to settle
		## it -- both machines can agree that this bird is tagged for this long and be right. that is
		## why it goes out as call_local rather than as an ask.
		_target.net_mark.rpc(tag_time)
		UiSfx.play("tick")
		marked.emit(_target)


## the bird the middle of the view is on: nearest first, inside the cone, inside range, and with
## nothing solid between the eye and it. the cone rather than a ray because a ray off a bird's neck
## by two pixels would be a tool that works only when it feels like it.
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


## ---------------------------------------------------------------- what the hud asks

func is_raised() -> bool:
	return _up


## 0 down, 1 fully up. the drawn optic fades in on this rather than on the flag, so the picture does
## not snap on before the camera has finished narrowing behind it.
func amount() -> float:
	if _aim == null or not is_instance_valid(_aim):
		return 1.0 if _up else 0.0
	return _aim.aim_amount() if _up else 0.0


## how many times nearer things look than they do walking about, as the eye is RIGHT NOW rather than
## as the wheel last asked: the stamp on the lens and the picture behind it are the same lens.
func magnification() -> float:
	return _mag


func marked_count() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("kiwi"):
		var bird := node as Kiwi
		if bird != null and is_instance_valid(bird) and bird.is_marked():
			n += 1
	return n


## for the probe: how far through the dwell the bird under the reticle is, 0 with nothing there.
func dwell() -> float:
	return clampf(_dwell / maxf(mark_time, 0.01), 0.0, 1.0)


func target() -> Kiwi:
	return _target
