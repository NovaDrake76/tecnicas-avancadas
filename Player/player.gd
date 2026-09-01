extends CharacterBody3D

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

@export_group("Landing")
@export var fall_velocity_threshold := -7.5

@onready var head: Node3D = $Head
@onready var camera: CameraEffects = $Head/Camera3D
@onready var _col: CollisionShape3D = $CollisionShape3D
@onready var _sm: StateMachine = $StateMachine
@onready var _ceiling_check: ShapeCast3D = get_node_or_null("HeadClearance")
@onready var _aim: AimScope = get_node_or_null("AimScope")

var _jump_buffer := 0.0
var _crouch_t := 0.0
var _base_sensitivity := 0.0022
var _crouching := false
var _grounded := false
var _peak_fall_vy := 0.0


func _ready() -> void:
	add_to_group("player")
	_base_sensitivity = mouse_sensitivity
	_apply_settings()
	Settings.changed.connect(_apply_settings)
	if movement == null:
		movement = MovementConfig.new()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	## a unique capsule, otherwise resizing for crouch mutates the shared sub resource.
	_col.shape = _col.shape.duplicate()

	if _ceiling_check != null:
		_ceiling_check.add_exception(self)
		_ceiling_check.position.y = crouch_height - 0.28
		_ceiling_check.target_position = Vector3(0.0, stand_height - crouch_height, 0.0)

	_sm.setup(self)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		## aiming narrows the fov, so the look slows by the same ratio or fine aim is impossible.
		var sens := mouse_sensitivity * (_aim.sensitivity_mult() if _aim != null else 1.0)
		rotate_y(-motion.relative.x * sens)
		var pitch: float = motion.relative.y if invert_look else -motion.relative.y
		head.rotate_x(pitch * sens)
		var limit := deg_to_rad(pitch_limit_deg)
		head.rotation.x = clampf(head.rotation.x, -limit, limit)


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
	_update_jump_buffer(delta)
	_sm.physics_tick(delta)


func wish_dir() -> Vector3:
	var input2 := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var d := global_transform.basis * Vector3(input2.x, 0.0, input2.y)
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
	_crouching = want

	var target := 1.0 if _crouching else 0.0
	if is_equal_approx(_crouch_t, target):
		return
	_crouch_t = move_toward(_crouch_t, target, crouch_lerp_speed * delta)
	var h := lerpf(stand_height, crouch_height, _crouch_t)
	(_col.shape as CapsuleShape3D).height = h
	_col.position.y = h * 0.5
	head.position.y = lerpf(stand_eye, crouch_eye, _crouch_t)


## a short forgiveness window so an early jump press still fires on landing.
func _update_jump_buffer(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = movement.jump_buffer_time
	_jump_buffer = maxf(0.0, _jump_buffer - delta)


func _on_landed(impact_vy: float) -> void:
	if impact_vy >= fall_velocity_threshold:
		return
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
