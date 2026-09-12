class_name Player
extends CharacterBody3D

signal hurt(amount: float, from: Vector3)

const SPAWN_PROBE := 300.0
const SPAWN_LIFT := 1.0
const SPAWN_CLEARANCE := 0.15
const RIGHT_OF_SPAWN := 1.6

enum Stance { STAND, CROUCH, PRONE }

@export var movement: MovementConfig

@export_group("Look")
@export var mouse_sensitivity: float = 0.0022
@export var invert_look := false
@export var pitch_limit_deg: float = 89.0

@export_group("Stance")
@export var stand_height := 1.8
@export var crouch_height := 1.0
## flat on the ground.
@export var prone_height := 0.55
@export var stand_eye := 1.65
@export var crouch_eye := 0.95
@export var prone_eye := 0.35
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
## health comes back on its own once nothing has hit you for a while.
@export var regen_delay := 10.0
@export var regen_rate := 15.0
## regeneration stops here; the rest comes back at the armoury.
@export_range(0.0, 1.0) var regen_cap := 0.70

@onready var head: Node3D = $Head
@onready var camera: CameraEffects = $Head/Camera3D
@onready var _col: CollisionShape3D = $CollisionShape3D
@onready var _sm: StateMachine = $StateMachine
@onready var _ceiling_check: ShapeCast3D = get_node_or_null("HeadClearance")
@onready var _aim: AimScope = get_node_or_null("AimScope")
@onready var health: Health = $Health

var _jump_buffer := 0.0
var _stance_t := 0.0
var _base_sensitivity := 0.0022
var _stance := Stance.STAND
var _crouch_latch := false
var _jump_spent := false
var _jump_hit := false
var _grounded := false
var _peak_fall_vy := 0.0
var _pitch := 0.0
var _lean := 0.0
var _since_hurt := 999.0
var _since_shot_at := 999.0
var _suppression := 0.0
const REMOTE_SILENT := ["aim_scope", "viewmodel", "interactor", "utility", "takedown", "binoculars",
	"body_drag", "prop_carry", "footsteps", "weapon_rack", "weapon", "pouch", "revive", "pinger",
	"magazine_hand"]

var _local := true
var _down := false
var _avatar: Avatar
var _kit: Array[Node] = []


func _ready() -> void:
	var owner_id := name.to_int()
	if owner_id > 0:
		set_multiplayer_authority(owner_id)
	_local = is_multiplayer_authority()
	for node in find_children("*", "", true, false):
		for group in REMOTE_SILENT:
			if node.is_in_group(group):
				_kit.append(node)
				break

	add_to_group("player")
	if _local:
		add_to_group("local_player")
		if camera != null:
			camera.make_current()
	else:
		_go_remote()
	if _local:
		Net.announce_local.call_deferred(self)

	Netlink.sync(self, [".:position", ".:rotation", "Head:position", "Head:rotation"],
		get_multiplayer_authority())
	_base_sensitivity = mouse_sensitivity
	_apply_settings()
	Settings.changed.connect(_apply_settings)
	if movement == null:
		movement = MovementConfig.new()
	if _local and DisplayServer.window_is_focused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	## a unique capsule; resizing for crouch would otherwise mutate the shared sub resource.
	_col.shape = _col.shape.duplicate()

	if _ceiling_check != null:
		_ceiling_check.add_exception(self)
		_ceiling_check.position.y = crouch_height - 0.28
		_ceiling_check.target_position = Vector3(0.0, stand_height - crouch_height, 0.0)

	_sm.setup(self)

	if health != null:
		health.died.connect(_on_died)


func _go_remote() -> void:
	if camera != null:
		camera.current = false
	for node in _kit:
		for group in REMOTE_SILENT:
			if node.is_in_group(group):
				node.remove_from_group(group)
		node.process_mode = Node.PROCESS_MODE_DISABLED
	if _sm != null:
		_sm.process_mode = Node.PROCESS_MODE_DISABLED
	var view := find_child("Viewmodel", true, false) as Node3D
	if view != null:
		view.position = Vector3.ZERO
		view.rotation = Vector3.ZERO
	var rack := get_node_or_null("Head/Camera3D/Viewmodel/Weapons") as Node3D
	if rack != null:
		rack.position = Vector3(0.20, -0.34, -0.26)
		rack.rotation = Vector3(0.0, deg_to_rad(-8.0), 0.0)
	_show_body()


func _show_body() -> void:
	if _avatar != null:
		return
	_avatar = Avatar.new()
	_avatar.name = "Avatar"
	add_child(_avatar)
	_avatar.set_tag(Net.name_of(get_multiplayer_authority()))


func is_local() -> bool:
	return _local


func is_down() -> bool:
	return _down


static func downed(tree: SceneTree) -> Array[Player]:
	var out: Array[Player] = []
	for node in tree.get_nodes_in_group("player"):
		var who := node as Player
		if who != null and is_instance_valid(who) and who.is_down():
			out.append(who)
	return out


func _on_died() -> void:
	Sfx.play_2d(&"player_down")
	_net_down.rpc()
	if _local:
		Run.report_down(multiplayer.get_unique_id())


@rpc("any_peer", "call_local", "reliable")
func _net_down() -> void:
	if _down:
		return
	_down = true
	velocity = Vector3.ZERO
	_freeze_kit(true)
	head.position.y = 0.4
	if _avatar != null:
		_avatar.lie(true)


@rpc("any_peer", "call_local", "reliable")
func net_revive(amount: float) -> void:
	if not _down:
		return
	if health != null:
		health.revive()
		health.current = clampf(amount, 1.0, health.max_health)
		health.health_changed.emit(health.current, health.max_health)
	_since_hurt = 0.0
	_stand_up()


@rpc("any_peer", "call_local", "reliable")
func _net_stand() -> void:
	_stand_up()


func _stand_up() -> void:
	if not _down:
		return
	_down = false
	_freeze_kit(false)
	head.position.y = stand_eye
	if _avatar != null:
		_avatar.lie(false)
	if _avatar != null:
		_avatar.lie(false)
	Sfx.play_2d(&"pickup")


func _freeze_kit(off: bool) -> void:
	var stop := off or not _local
	for node in _kit:
		if is_instance_valid(node):
			node.process_mode = Node.PROCESS_MODE_DISABLED if stop else Node.PROCESS_MODE_INHERIT
	if _sm != null:
		_sm.process_mode = Node.PROCESS_MODE_DISABLED if stop else Node.PROCESS_MODE_INHERIT


static func local(tree: SceneTree) -> Player:
	return tree.get_first_node_in_group("local_player") as Player


## one list per frame and per player count, shared by every caller: the birds asked for it sixteen times a tick.
static var _all_stamp := -1
static var _all_count := -1
static var _all_cache: Array[Player] = []


static func all(tree: SceneTree) -> Array[Player]:
	var stamp := Engine.get_physics_frames() * 100000 + Engine.get_process_frames()
	var count := tree.get_node_count_in_group("player")
	if stamp == _all_stamp and count == _all_count:
		return _all_cache
	var out: Array[Player] = []
	for node in tree.get_nodes_in_group("player"):
		var who := node as Player
		if who != null and is_instance_valid(who) and who.is_alive():
			out.append(who)
	_all_stamp = stamp
	_all_count = count
	_all_cache = out
	return out


static func nearest(tree: SceneTree, from: Vector3) -> Player:
	var best: Player = null
	var near := INF
	for who in all(tree):
		var d := who.global_position.distance_squared_to(from)
		if d < near:
			near = d
			best = who
	return best


func may_capture() -> bool:
	return not get_tree().paused and get_tree().get_first_node_in_group("holds_mouse") == null


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _local and may_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _local:
		return
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and DisplayServer.window_is_focused() and may_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sens := mouse_sensitivity * (_aim.sensitivity_mult() if _aim != null else 1.0)
		rotate_y(-motion.relative.x * sens)
		var pitch: float = motion.relative.y if invert_look else -motion.relative.y
		var limit := deg_to_rad(pitch_limit_deg)
		_pitch = clampf(_pitch + pitch * sens, -limit, limit)
		_apply_head()


func _physics_process(delta: float) -> void:
	if not _local or _down:
		return
	var was_grounded := _grounded
	_grounded = is_on_floor()

	if not _grounded:
		_peak_fall_vy = minf(_peak_fall_vy, velocity.y)
	elif not was_grounded:
		_on_landed(_peak_fall_vy)
		_peak_fall_vy = 0.0

	_update_stance(delta)
	_update_lean(delta)
	_update_jump_buffer(delta)
	_update_health(delta)
	_sm.physics_tick(delta)


func wish_dir() -> Vector3:
	var strafe := Input.get_axis("move_left", "move_right")
	var forward := Input.get_axis("move_forward", "move_back")
	if Input.is_action_pressed("lean_mode"):
		strafe = 0.0
	var d := global_transform.basis * Vector3(strafe, 0.0, forward)
	d.y = 0.0
	return d.normalized()


func current_max_speed() -> float:
	var base := movement.ground_max_speed
	match _stance:
		Stance.CROUCH:
			base = movement.crouch_max_speed
		Stance.PRONE:
			base = movement.prone_max_speed
		_:
			if Input.is_action_pressed("sprint"):
				base = movement.run_max_speed
	return base * (_aim.speed_mult() if _aim != null else 1.0)


func wants_jump() -> bool:
	if _stance == Stance.PRONE:
		return false
	return Input.is_action_pressed("jump") if movement.auto_bhop else _jump_buffer > 0.0


func is_grounded() -> bool:
	return _grounded


func is_crouching() -> bool:
	return stance() == Stance.CROUCH


func is_prone() -> bool:
	return stance() == Stance.PRONE


func stance() -> int:
	if not _local and head != null:
		if head.position.y <= (prone_eye + crouch_eye) * 0.5:
			return Stance.PRONE
		if head.position.y <= (crouch_eye + stand_eye) * 0.5:
			return Stance.CROUCH
		return Stance.STAND
	return _stance


func note_shot_at(landed: bool) -> void:
	if not is_multiplayer_authority():
		_net_shot_at.rpc_id(get_multiplayer_authority(), landed)
		return
	_since_shot_at = 0.0
	_suppression = minf(_suppression + (0.45 if landed else 0.3), 1.0)


@rpc("any_peer", "call_remote", "reliable")
func _net_shot_at(landed: bool) -> void:
	if is_multiplayer_authority():
		note_shot_at(landed)


func take_peck(amount: float, from: Vector3, shove: Vector3) -> void:
	if not is_multiplayer_authority():
		_net_peck.rpc_id(get_multiplayer_authority(), amount, from, shove)
		return
	velocity += shove
	take_laser_hit(amount, from)


@rpc("any_peer", "call_remote", "reliable")
func _net_peck(amount: float, from: Vector3, shove: Vector3) -> void:
	if is_multiplayer_authority():
		take_peck(amount, from, shove)


func suppression() -> float:
	return _suppression


func take_laser_hit(amount: float, from: Vector3) -> void:
	if not is_multiplayer_authority():
		_net_hurt.rpc_id(get_multiplayer_authority(), amount, from)
		return
	if health == null or not health.is_alive():
		return
	health.take_damage(amount)
	_since_hurt = 0.0
	_since_shot_at = 0.0
	var k := clampf(amount / 7.0, 0.12, 1.0)
	if camera != null:
		camera.add_damage_kick(2.2 * k, 1.6 * k, from)
		camera.add_screen_shake(0.35 * k, 0.22)
	Sfx.play_2d(&"player_hurt")
	hurt.emit(amount, from)


@rpc("any_peer", "call_remote", "reliable")
func _net_hurt(amount: float, from: Vector3) -> void:
	if is_multiplayer_authority():
		take_laser_hit(amount, from)


func is_alive() -> bool:
	if _down:
		return false
	return health == null or health.is_alive()


func restore() -> void:
	_since_hurt = 999.0
	_since_shot_at = 999.0
	_suppression = 0.0
	if health != null:
		health.revive()
	if _down:
		_net_stand.rpc()


func _update_health(delta: float) -> void:
	_since_hurt += delta
	_since_shot_at += delta
	_suppression = maxf(0.0, _suppression - 0.4 * delta)
	## no healing under fire: being shot AT resets the clock, not only being hit.
	if health != null and health.is_alive() and minf(_since_hurt, _since_shot_at) > regen_delay:
		var ceiling := health.max_health * regen_cap
		if health.current < ceiling:
			health.heal(minf(regen_rate * delta, ceiling - health.current))


func look_at_pitch(radians: float) -> void:
	var limit := deg_to_rad(pitch_limit_deg)
	_pitch = clampf(radians, -limit, limit)
	_apply_head()


func lean_amount() -> float:
	return _lean


func lean_offset() -> Vector3:
	return global_transform.basis.x * head.position.x


func is_running() -> bool:
	if _aim != null and _aim.is_aiming():
		return false
	if not _grounded or _stance != Stance.STAND or not Input.is_action_pressed("sprint"):
		return false
	return Vector2(velocity.x, velocity.z).length() > 0.2


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

	## lift onto kerbs and stairs BEFORE the move; climbing after the collision costs a tick at a dead stop.
	StepClimb.try_step(self, wish)

	velocity = Vector3(hvel.x, vert, hvel.z)
	move_and_slide()


func _accelerate(hvel: Vector3, dir: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	var current := hvel.dot(dir)
	var add := wish_speed - current
	if add <= 0.0:
		return hvel
	var amount := accel * wish_speed * delta
	if amount > add:
		amount = add
	return hvel + dir * amount


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


func _update_stance(delta: float) -> void:
	_jump_hit = Input.is_action_just_pressed("jump")

	var want := _stance
	if Input.is_action_just_pressed("prone"):
		want = Stance.STAND if _stance == Stance.PRONE else Stance.PRONE
		_crouch_latch = false
	elif _stance == Stance.PRONE:
		if Input.is_action_just_pressed("crouch"):
			want = Stance.CROUCH
			_crouch_latch = true
		elif _jump_hit:
			want = Stance.STAND
			_jump_spent = true
	else:
		if _crouch_latch and (Input.is_action_just_pressed("crouch") or _jump_hit
				or Input.is_action_pressed("sprint")):
			_crouch_latch = false
		want = Stance.CROUCH if Input.is_action_pressed("crouch") or _crouch_latch else Stance.STAND

	if want < _stance and not _room_to_rise(want):
		want = _stance
	if want != _stance:
		Sfx.play_2d(&"crouch")
		_stance = want

	var target := float(_stance)
	if is_equal_approx(_stance_t, target):
		return
	_stance_t = move_toward(_stance_t, target, crouch_lerp_speed * delta)
	var h := height_at(_stance_t)
	(_col.shape as CapsuleShape3D).height = h
	_col.position.y = h * 0.5
	head.position.y = eye_at(_stance_t)


func height_at(t: float) -> float:
	if t <= 1.0:
		return lerpf(stand_height, crouch_height, t)
	return lerpf(crouch_height, prone_height, t - 1.0)


func eye_at(t: float) -> float:
	if t <= 1.0:
		return lerpf(stand_eye, crouch_eye, t)
	return lerpf(crouch_eye, prone_eye, t - 1.0)


func _room_to_rise(want: int) -> bool:
	if _ceiling_check == null:
		return true
	var now := height_at(_stance_t)
	var to := height_at(float(want))
	if to <= now + 0.01:
		return true
	var radius := 0.28
	var ball := _ceiling_check.shape as SphereShape3D
	if ball != null:
		radius = ball.radius
	_ceiling_check.position.y = maxf(now - radius, radius + 0.05)
	_ceiling_check.target_position = Vector3(0.0, to - now, 0.0)
	_ceiling_check.force_shapecast_update()
	return not _ceiling_check.is_colliding()


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


func _apply_head() -> void:
	head.position.x = _lean * lean_reach
	head.rotation = Vector3(_pitch, 0.0, -_lean * deg_to_rad(lean_roll_deg))


func _update_jump_buffer(delta: float) -> void:
	if _jump_hit:
		if _jump_spent:
			_jump_spent = false
		else:
			_jump_buffer = movement.jump_buffer_time
	_jump_buffer = maxf(0.0, _jump_buffer - delta)


func _on_landed(impact_vy: float) -> void:
	if impact_vy >= fall_velocity_threshold:
		return
	Sfx.play_2d(&"land_hard")
	if camera != null:
		camera.add_fall_kick(clampf(absf(impact_vy) * 0.5, 1.0, 6.0))


func _apply_settings() -> void:
	mouse_sensitivity = _base_sensitivity * Settings.look_scale
	invert_look = Settings.invert_look


func respawn_from_void() -> void:
	velocity = Vector3.ZERO
	var spawn := get_tree().get_first_node_in_group("player_spawn") as Node3D
	if spawn == null:
		push_warning("player.gd: no node in group 'player_spawn'; keeping current position.")
		return
	var apart := Vector3.ZERO
	if Net.is_online():
		var ids := Net.peers.keys()
		ids.sort()
		var index := maxi(ids.find(get_multiplayer_authority()), 0)
		apart = Vector3(RIGHT_OF_SPAWN * float(index), 0.0, 0.0).rotated(
			Vector3.UP, spawn.global_rotation.y)
	global_position = ground_under(spawn.global_position + apart)
	rotation.y = spawn.global_rotation.y


## the ground UNDER the marker: the ray starts a little above it and goes down, never from high up, or a roof over the marker is the ground.
func ground_under(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * SPAWN_LIFT, point - Vector3.UP * SPAWN_PROBE, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		push_warning("player.gd: no ground under the spawn marker at %v; using it as given." % point)
		return point
	return (hit["position"] as Vector3) + Vector3.UP * SPAWN_CLEARANCE
