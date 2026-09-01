class_name CameraEffects
extends Camera3D

## every view effect lands here, on the camera, as an offset on top of the head's aim.
## the head carries mouse pitch and crouch height, this node only ever adds to it.

@export_group("Toggles")
@export var enable_tilt := true
@export var enable_fall_kick := true
@export var enable_damage_kick := true
@export var enable_weapon_kick := true
@export var enable_screen_shake := true
@export var enable_headbob := true

@export_group("Run tilt")
@export var run_pitch := 0.1
@export var run_roll := 0.15
@export var max_pitch := 1.0
@export var max_roll := 2.5

@export_group("Fall kick")
@export var fall_time := 0.3

@export_group("Damage kick")
@export var damage_time := 0.3

@export_group("Weapon kick")
## slow while shots are still landing, fast once the trigger is released.
@export var weapon_recentre_firing := 1.3
@export var weapon_recentre_rest := 6.0
@export var weapon_firing_grace := 0.18
@export var weapon_settle_deg := 0.4
@export var weapon_kick_cap_deg := 10.0

@export_group("Headbob")
@export_range(0.0, 0.1, 0.001) var bob_pitch := 0.05
@export_range(0.0, 0.1, 0.001) var bob_roll := 0.025
@export_range(0.0, 0.04, 0.001) var bob_up := 0.005
@export_range(3.0, 8.0, 0.1) var bob_frequency := 6.0

const MIN_SCREEN_SHAKE := 0.0
const MAX_SCREEN_SHAKE := 0.27

var motion_scale := 1.0

var player: CharacterBody3D

var _fall_value := 0.0
var _fall_timer := 0.0
var _damage_pitch := 0.0
var _damage_roll := 0.0
var _damage_timer := 0.0
var _weapon_kick_angles := Vector3.ZERO
var _since_kick := 999.0
var _shake_tween: Tween
var _shake_amount := 0.0
var _shake_alpha := 1.0
var _hitstop_active := false
var _step_timer := 0.0


func _ready() -> void:
	add_to_group("camera_effects")
	_bind.call_deferred()


func _bind() -> void:
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	var rack := get_tree().get_first_node_in_group("weapon_rack") as WeaponRack
	if rack != null:
		for g in rack.weapons():
			g.fired.connect(_on_weapon_fired)
	else:
		var gun := get_tree().get_first_node_in_group("weapon") as Gun
		if gun != null:
			gun.fired.connect(_on_weapon_fired)


func _on_weapon_fired(_speed: float, _mass_kg: float) -> void:
	add_weapon_kick(0.6, 0.25, 0.25, weapon_kick_cap_deg, true)


func _process(delta: float) -> void:
	calculate_view_offset(delta)


func calculate_view_offset(delta: float) -> void:
	if player == null:
		return

	_fall_timer -= delta
	_damage_timer -= delta

	var velocity := player.velocity
	var speed := Vector2(velocity.x, velocity.z).length()

	if speed > 0.1 and player.is_on_floor():
		_step_timer += delta * (speed / bob_frequency)
		_step_timer = fmod(_step_timer, 1.0)
	else:
		_step_timer = 0.0
	var bob_sin := sin(_step_timer * TAU) * 0.5

	var angles := Vector3.ZERO
	var offset := Vector3.ZERO

	if enable_tilt:
		var forward := global_transform.basis.z
		var right := global_transform.basis.x
		angles.x += clampf(velocity.dot(forward) * deg_to_rad(run_pitch),
			deg_to_rad(-max_pitch), deg_to_rad(max_pitch))
		angles.z += clampf(velocity.dot(right) * deg_to_rad(run_roll),
			deg_to_rad(-max_roll), deg_to_rad(max_roll))

	if enable_fall_kick:
		angles.x -= maxf(0.0, _fall_timer / fall_time) * _fall_value

	if enable_damage_kick:
		var ratio := maxf(0.0, _damage_timer / damage_time)
		angles.x -= ratio * _damage_pitch
		angles.z += ratio * _damage_roll

	if enable_weapon_kick:
		## "am i firing" is answered by when the last kick arrived, not by a flag someone must clear.
		## so a swap, a death or an empty magazine mid burst all end the slow recentre for free.
		_since_kick += delta
		var rate: float = weapon_recentre_firing if _since_kick < weapon_firing_grace else weapon_recentre_rest
		_weapon_kick_angles = _weapon_kick_angles.lerp(Vector3.ZERO, clampf(rate * delta, 0.0, 1.0))
		_weapon_kick_angles = _weapon_kick_angles.move_toward(Vector3.ZERO, deg_to_rad(weapon_settle_deg) * delta)
		angles += _weapon_kick_angles

	if enable_headbob:
		angles.x -= bob_sin * deg_to_rad(bob_pitch) * speed
		angles.z += bob_sin * deg_to_rad(bob_roll) * speed
		offset.y += bob_sin * bob_up * speed

	## one multiply turns the whole layer down, so no contributor has to know the setting exists.
	position = offset * motion_scale
	rotation = angles * motion_scale


## the step phase 0..1, the single source of truth for foot rhythm.
## the weapon bob reads this so the gun's figure eight stays in step with the head.
func get_bob_phase() -> float:
	return _step_timer


func add_fall_kick(fall_strength: float) -> void:
	_fall_value = deg_to_rad(fall_strength)
	_fall_timer = fall_time


func add_damage_kick(pitch: float, roll: float, source: Vector3) -> void:
	var direction := global_position.direction_to(source)
	_damage_pitch = deg_to_rad(pitch) * direction.dot(global_transform.basis.z)
	_damage_roll = deg_to_rad(roll) * direction.dot(global_transform.basis.x)
	_damage_timer = damage_time


## pitch is signed upward, yaw and roll are random inside plus or minus the value given.
## cap bounds the accumulated climb so a long burst plateaus instead of walking into the sky.
func add_weapon_kick(pitch: float, yaw: float, roll: float, cap := 0.0, sustained := true) -> void:
	_weapon_kick_angles.x += deg_to_rad(pitch)
	_weapon_kick_angles.y += deg_to_rad(randf_range(-yaw, yaw))
	_weapon_kick_angles.z += deg_to_rad(randf_range(-roll, roll))
	var limit := cap if cap > 0.0 else weapon_kick_cap_deg
	_weapon_kick_angles.x = minf(_weapon_kick_angles.x, deg_to_rad(limit))
	_since_kick = 0.0 if sustained else 999.0


## a weaker request must not stomp a bigger shake still playing.
func add_screen_shake(amount: float, seconds: float) -> void:
	if not enable_screen_shake:
		return
	if amount <= _shake_amount * (1.0 - _shake_alpha):
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_amount = amount
	_shake_alpha = 0.0
	_shake_tween = create_tween()
	_shake_tween.tween_method(update_screen_shake, 0.0, 1.0, seconds).set_ease(Tween.EASE_OUT)


func update_screen_shake(alpha: float) -> void:
	_shake_alpha = alpha
	var amt := remap(_shake_amount, 0.0, 1.0, MIN_SCREEN_SHAKE, MAX_SCREEN_SHAKE) * (1.0 - alpha) * motion_scale
	h_offset = randf_range(-amt, amt)
	v_offset = randf_range(-amt, amt)


## a brief time freeze on impact, one at a time so a low time_scale is never stranded.
func hitstop(seconds := 0.07, freeze_scale := 0.05) -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	Engine.time_scale = freeze_scale
	var timer := get_tree().create_timer(seconds * freeze_scale, true, false, true)
	timer.timeout.connect(func() -> void:
		Engine.time_scale = 1.0
		_hitstop_active = false)


static func shake_at(tree: SceneTree, at: Vector3, radius: float) -> void:
	var fx := tree.get_first_node_in_group("camera_effects") as CameraEffects
	if fx == null:
		return
	var dist := fx.global_position.distance_to(at)
	if dist > radius:
		return
	fx.add_screen_shake(1.0 - dist / radius, 0.35)
