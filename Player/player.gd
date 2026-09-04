extends CharacterBody3D

## something hit the player. the hud and the camera answer this; nothing in here decides what it means.
signal hurt(amount: float, from: Vector3)

## how far above and below a spawn marker to look for ground, and how far to stand clear of it.
const SPAWN_PROBE := 300.0
const SPAWN_CLEARANCE := 0.15

@export var movement: MovementConfig

@export_group("Look")
@export var mouse_sensitivity: float = 0.0022
@export var invert_look := false
@export var pitch_limit_deg: float = 89.0

@export_group("Crouch")
@export var stand_height := 1.8
@export var crouch_height := 1.0
@export var stand_eye := 1.65
@export var crouch_eye := 0.95
@export var crouch_lerp_speed := 12.0

@export_group("Lean")
## how far the head slides sideways, how far the view tips with it, and how fast it gets there.
@export var lean_reach := 0.45
@export var lean_roll_deg := 12.0
@export var lean_speed := 7.0
## how close the head is allowed to get to a wall it is leaning into.
@export var lean_clearance := 0.28

@export_group("Landing")
@export var fall_velocity_threshold := -7.5

@export_group("Health")
## health comes back on its own once nothing has hit you for a while. a fight you break off is a
## fight you recover from, which is what makes breaking line of sight the right answer to a laser.
## six seconds means genuinely disengaging, not ducking.
@export var regen_delay := 6.0
@export var regen_rate := 15.0
## regeneration stops here; the rest comes back at the armoury. a fight you break off leaves a mark
## that lasts the level, so the second fight is worse than the first and pushing on is a decision.
@export_range(0.0, 1.0) var regen_cap := 0.70

@onready var head: Node3D = $Head
@onready var camera: CameraEffects = $Head/Camera3D
@onready var _col: CollisionShape3D = $CollisionShape3D
@onready var _sm: StateMachine = $StateMachine
@onready var _ceiling_check: ShapeCast3D = get_node_or_null("HeadClearance")
@onready var _aim: AimScope = get_node_or_null("AimScope")
@onready var health: Health = $Health

var _jump_buffer := 0.0
var _crouch_t := 0.0
var _base_sensitivity := 0.0022
var _crouching := false
var _grounded := false
var _peak_fall_vy := 0.0
var _pitch := 0.0
var _lean := 0.0
var _since_hurt := 999.0


func _ready() -> void:
	add_to_group("player")
	_base_sensitivity = mouse_sensitivity
	_apply_settings()
	Settings.changed.connect(_apply_settings)
	if movement == null:
		movement = MovementConfig.new()
	## capturing an unfocused window warps the real cursor and drags focus over, so the mouse is taken
	## only once the window has it. a launch that lands unfocused captures on the first click or focus.
	if DisplayServer.window_is_focused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	## a unique capsule, otherwise resizing for crouch mutates the shared sub resource.
	_col.shape = _col.shape.duplicate()

	if _ceiling_check != null:
		_ceiling_check.add_exception(self)
		_ceiling_check.position.y = crouch_height - 0.28
		_ceiling_check.target_position = Vector3(0.0, stand_height - crouch_height, 0.0)

	_sm.setup(self)

	if health != null:
		health.died.connect(func() -> void: Sfx.play_2d(&"player_down"))


## the mouse is the player's only while nothing on screen owns it: not the pause menu (the tree is
## paused) and not a bench or a board (they join "holds_mouse" while open). alt-tabbing back with the
## bench up used to recapture the cursor over the sheet, which then had no pointer until escape.
func may_capture() -> bool:
	return not get_tree().paused and get_tree().get_first_node_in_group("holds_mouse") == null


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and may_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED 			and DisplayServer.window_is_focused() and may_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		## aiming narrows the fov, so the look slows by the same ratio or fine aim is impossible.
		var sens := mouse_sensitivity * (_aim.sensitivity_mult() if _aim != null else 1.0)
		rotate_y(-motion.relative.x * sens)
		var pitch: float = motion.relative.y if invert_look else -motion.relative.y
		var limit := deg_to_rad(pitch_limit_deg)
		_pitch = clampf(_pitch + pitch * sens, -limit, limit)
		_apply_head()


func _physics_process(delta: float) -> void:
	## order matters, cache the floor state and run crouch plus the jump buffer first,
	## then let the active state call solve_and_move exactly once.
	var was_grounded := _grounded
	_grounded = is_on_floor()

	## track the peak downward speed while airborne, then kick the camera on the landing edge.
	if not _grounded:
		_peak_fall_vy = minf(_peak_fall_vy, velocity.y)
	elif not was_grounded:
		_on_landed(_peak_fall_vy)
		_peak_fall_vy = 0.0

	_update_crouch(delta)
	_update_lean(delta)
	_update_jump_buffer(delta)
	_update_health(delta)
	_sm.physics_tick(delta)


func wish_dir() -> Vector3:
	var strafe := Input.get_axis("move_left", "move_right")
	var forward := Input.get_axis("move_forward", "move_back")
	## in lean mode A and D are the lean, so the peek happens in place instead of stepping out.
	if Input.is_action_pressed("lean_mode"):
		strafe = 0.0
	var d := global_transform.basis * Vector3(strafe, 0.0, forward)
	d.y = 0.0
	return d.normalized()


func current_max_speed() -> float:
	var base := movement.ground_max_speed
	if _crouching:
		base = movement.crouch_max_speed
	elif Input.is_action_pressed("sprint"):
		base = movement.run_max_speed
	return base * (_aim.speed_mult() if _aim != null else 1.0)


func wants_jump() -> bool:
	return Input.is_action_pressed("jump") if movement.auto_bhop else _jump_buffer > 0.0


func is_grounded() -> bool:
	return _grounded


func is_crouching() -> bool:
	return _crouching


## a laser found you. the damage goes to the health component, the kick and the shake to the camera.
func take_laser_hit(amount: float, from: Vector3) -> void:
	if health == null or not health.is_alive():
		return
	health.take_damage(amount)
	_since_hurt = 0.0
	## the kick scales with the hit: a beam is many small hits a second and a full kick on each
	## would be a shaking camera rather than a struck one.
	var k := clampf(amount / 7.0, 0.12, 1.0)
	if camera != null:
		camera.add_damage_kick(2.2 * k, 1.6 * k, from)
		camera.add_screen_shake(0.35 * k, 0.22)
	## heard in the head, not in the world: the table caps it so a beam is not a drum roll
	Sfx.play_2d(&"player_hurt")
	hurt.emit(amount, from)


func is_alive() -> bool:
	return health == null or health.is_alive()


## a fresh start: full health, nothing hurting. main calls it on every level and on the way home.
func restore() -> void:
	_since_hurt = 999.0
	if health != null:
		health.revive()


func _update_health(delta: float) -> void:
	_since_hurt += delta
	if health != null and health.is_alive() and _since_hurt > regen_delay:
		var ceiling := health.max_health * regen_cap
		if health.current < ceiling:
			health.heal(minf(regen_rate * delta, ceiling - health.current))


## the one way in for anything that places the view instead of the mouse. writing head.rotation
## from outside would be overwritten the moment a lean moved the head.
func look_at_pitch(radians: float) -> void:
	var limit := deg_to_rad(pitch_limit_deg)
	_pitch = clampf(radians, -limit, limit)
	_apply_head()


## -1 fully left, +1 fully right, and every value between while the head is on its way.
func lean_amount() -> float:
	return _lean


## where the head sits relative to the body, in world axes. the kiwis add this to the point
## they test, so leaning out to see is also leaning out to be seen.
func lean_offset() -> Vector3:
	return global_transform.basis.x * head.position.x


func is_running() -> bool:
	if _aim != null and _aim.is_aiming():
		return false
	if not _grounded or _crouching or not Input.is_action_pressed("sprint"):
		return false
	return Vector2(velocity.x, velocity.z).length() > 0.2


## the source solver, one integration and one move_and_slide per tick.
## friction is skipped on the jump tick, which is what makes a bunny hop keep its speed.
func solve_and_move(delta: float, wish: Vector3, cur_max: float, want_jump: bool) -> void:
	var jumping := _grounded and want_jump
	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	var vert := velocity.y

	if _grounded and not jumping:
		var speed := hvel.length()
		if speed > 0.0:
			var control := maxf(speed, movement.stop_speed)
			var drop := control * movement.friction * delta
			hvel *= maxf(speed - drop, 0.0) / speed
		hvel = _accelerate(hvel, wish, cur_max, movement.ground_accelerate, delta)
	else:
		hvel = _air_accelerate(hvel, wish, cur_max, delta)

	if not _grounded or jumping:
		vert -= movement.gravity * delta
	if jumping:
		vert = movement.jump_impulse
		Sfx.play_2d(&"jump")
		_jump_buffer = 0.0

	## lift onto kerbs and stairs before the move, never after.
	## climbing after the collision costs a tick at a dead stop.
	StepClimb.try_step(self, wish)

	velocity = Vector3(hvel.x, vert, hvel.z)
	move_and_slide()


## ground acceleration, only the component along wish counts so turning never adds speed.
func _accelerate(hvel: Vector3, dir: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	var current := hvel.dot(dir)
	var add := wish_speed - current
	if add <= 0.0:
		return hvel
	var amount := accel * wish_speed * delta
	if amount > add:
		amount = add
	return hvel + dir * amount


## air acceleration capped at air_speed_cap, this tiny cap is what makes air strafing work.
## do not scale the cap with the rest of the speeds or strafing stops paying out.
func _air_accelerate(hvel: Vector3, dir: Vector3, wish_speed: float, delta: float) -> Vector3:
	var cap := minf(wish_speed, movement.air_speed_cap)
	var current := hvel.dot(dir)
	var add := cap - current
	if add <= 0.0:
		return hvel
	var amount := movement.air_accelerate * wish_speed * delta
	if amount > add:
		amount = add
	return hvel + dir * amount


func _update_crouch(delta: float) -> void:
	var want := Input.is_action_pressed("crouch")
	## refuse to stand up while something is directly overhead.
	if not want and _crouching and _ceiling_check != null and _ceiling_check.is_colliding():
		want = true
	if want != _crouching:
		Sfx.play_2d(&"crouch")
	_crouching = want

	var target := 1.0 if _crouching else 0.0
	if is_equal_approx(_crouch_t, target):
		return
	_crouch_t = move_toward(_crouch_t, target, crouch_lerp_speed * delta)
	var h := lerpf(stand_height, crouch_height, _crouch_t)
	(_col.shape as CapsuleShape3D).height = h
	_col.position.y = h * 0.5
	head.position.y = lerpf(stand_eye, crouch_eye, _crouch_t)


## the body never moves: only the head slides out and the view tips with it, so the capsule
## stays in cover while the eyes clear it. lean has no keys of its own -- ALT turns the two
## strafe keys into it, so nothing had to be taken off the keyboard to make room, and the key
## you already use to step left is the one that leans left. holding both is a lean of zero,
## which is what get_axis already says.
func _update_lean(delta: float) -> void:
	var want := 0.0
	if Input.is_action_pressed("lean_mode"):
		want = Input.get_axis("move_left", "move_right")
	if not is_zero_approx(want):
		want = signf(want) * minf(absf(want), _lean_room(signf(want)))
	if is_equal_approx(_lean, want):
		return
	_lean = move_toward(_lean, want, lean_speed * delta)
	_apply_head()


## how much of a full lean fits before the wall on that side. measured from where the head
## would be with no lean at all: casting from the head as it stands would re-measure from a
## position the last tick already moved, and the eye would creep into the wall a bit per tick.
func _lean_room(dir: float) -> float:
	var from := global_position + Vector3.UP * head.position.y
	var to := from + global_transform.basis.x * dir * (lean_reach + lean_clearance)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 1.0
	var room := from.distance_to(hit["position"] as Vector3) - lean_clearance
	return clampf(room / maxf(lean_reach, 0.01), 0.0, 1.0)


## pitch and lean are written together, outright. rotate_x on a head the lean has already
## rolled turns about a tilted axis, so the aim would drift sideways a little per mouse move.
func _apply_head() -> void:
	head.position.x = _lean * lean_reach
	head.rotation = Vector3(_pitch, 0.0, -_lean * deg_to_rad(lean_roll_deg))


## a short forgiveness window so an early jump press still fires on landing.
func _update_jump_buffer(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = movement.jump_buffer_time
	_jump_buffer = maxf(0.0, _jump_buffer - delta)


func _on_landed(impact_vy: float) -> void:
	if impact_vy >= fall_velocity_threshold:
		return
	Sfx.play_2d(&"land_hard")
	if camera != null:
		camera.add_fall_kick(clampf(absf(impact_vy) * 0.5, 1.0, 6.0))


## the exported value is the tuned base. the settings multiplier rides on top of it, so it can
## be re-applied on every change without compounding.
func _apply_settings() -> void:
	mouse_sensitivity = _base_sensitivity * Settings.look_scale
	invert_look = Settings.invert_look


## called by KillPlane when we fall out of the world, and by main.gd on load.
func respawn_from_void() -> void:
	velocity = Vector3.ZERO
	var spawn := get_tree().get_first_node_in_group("player_spawn") as Node3D
	if spawn == null:
		push_warning("player.gd: no node in group 'player_spawn'; keeping current position.")
		return
	global_position = ground_under(spawn.global_position)
	rotation.y = spawn.global_rotation.y


## the marker says where, the terrain says how high. every level grows its hills from its own
## seed, so a y typed into one marker is only ever correct for the level it was typed in.
func ground_under(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * SPAWN_PROBE, point - Vector3.UP * SPAWN_PROBE, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		push_warning("player.gd: no ground under the spawn marker at %v; using it as given." % point)
		return point
	return (hit["position"] as Vector3) + Vector3.UP * SPAWN_CLEARANCE
