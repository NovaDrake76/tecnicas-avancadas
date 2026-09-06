class_name Player
extends CharacterBody3D

## every operative in the level is one of these, and exactly one of them is THIS machine's. the game
## is always a host -- godot hands out an OfflineMultiplayerPeer when nothing is connected, so a solo
## run is a host with nobody else on it -- and a player node is owned by the peer whose id it is
## named after. that is the whole of the ownership model: the name IS the authority.
##
## the owner runs its own movement, aim, weapons and verbs; every other machine only receives where
## it ended up. that is client-side movement, which is the only way the game can feel right on the
## machine you are playing on, and cheating is not a threat in a two person co-op on one network.
##
## something hit the player. the hud and the camera answer this; nothing in here decides what it means.
signal hurt(amount: float, from: Vector3)

## how far above and below a spawn marker to look for ground, and how far to stand clear of it.
const SPAWN_PROBE := 300.0
const SPAWN_CLEARANCE := 0.15
## how far apart two operatives stand on the same insertion marker.
const RIGHT_OF_SPAWN := 1.6

## standing, crouched, flat. a LADDER rather than two booleans, because everything that reads it
## -- how far a bird can see you, how loud your boots are, how fast you move -- steps down as you
## get lower, and two booleans would let a player be both at once.
enum Stance { STAND, CROUCH, PRONE }

@export var movement: MovementConfig

@export_group("Look")
@export var mouse_sensitivity: float = 0.0022
@export var invert_look := false
@export var pitch_limit_deg: float = 89.0

@export_group("Stance")
@export var stand_height := 1.8
@export var crouch_height := 1.0
## flat on the ground. the capsule is short enough that almost anything in the prop pack clears it,
## which is the point: prone is what the level's own clutter becomes cover for.
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
var _stance_t := 0.0
var _base_sensitivity := 0.0022
var _stance := Stance.STAND
## set when the crouch key was what lifted the operative out of prone. crouch is a HOLD, so without
## this a tap is one frame of crouching and then standing bolt upright in the open, which in a
## stealth game is the worst possible answer to "get me up one step".
var _crouch_latch := false
## a jump press spent standing up is not also a jump. without it one press stands the operative up
## AND launches them, because the stance is raised before the jump buffer is read.
var _jump_spent := false
## the jump edge, read ONCE a tick and used by both the stance machine and the jump buffer, so a
## press spent standing up out of prone can never also arm a jump.
var _jump_hit := false
var _grounded := false
var _peak_fall_vy := 0.0
var _pitch := 0.0
var _lean := 0.0
var _since_hurt := 999.0
## the parts of a player that only the machine driving it may run: everything that reads the mouse
## or the keyboard, and the footsteps, whose noise is sent by the owner instead so the birds hear it
## once rather than once per machine.
## every group here is one the game looks up GLOBALLY -- the hud asks for "the weapon", the reticle
## for "the viewmodel", Run for "the pouch" -- and with two operatives in the tree those lookups
## would hand back whichever came first. a remote operative's copies leave the groups AND stop
## processing: they keep their meshes, which is what the other player sees, and nothing else.
const REMOTE_SILENT := ["aim_scope", "viewmodel", "interactor", "utility", "takedown", "binoculars",
	"body_drag", "footsteps", "weapon_rack", "weapon", "pouch", "revive", "pinger"]

## whether this node is the one this machine drives. everything that reads the mouse, the keyboard,
## the camera or the hud hangs off it.
var _local := true
var _down := false
var _avatar: Avatar
## the nodes that make up the operative's kit, collected once: the aim, the weapon, the verbs.
var _kit: Array[Node] = []


func _ready() -> void:
	## a spawned player is named after the peer that owns it, so both machines agree on who is who
	## without a handshake. the fixed node in a tool scene keeps the default authority of 1.
	var owner_id := name.to_int()
	if owner_id > 0:
		set_multiplayer_authority(owner_id)
	_local = is_multiplayer_authority()
	## EVERY operative is in "player": that is the group the kiwis, the objectives and the kill plane
	## read, and they must see all of them. only the one this machine drives is in "local_player",
	## which is what the hud, the camera and the menus bind to.
	for node in find_children("*", "", true, false):
		for group in REMOTE_SILENT:
			if node.is_in_group(group):
				_kit.append(node)
				break

	add_to_group("player")
	if _local:
		add_to_group("local_player")
		## godot makes the FIRST camera in the tree current, and in a joined game the first one to
		## arrive is the teammate's -- which is then switched off for being theirs, leaving the
		## viewport with no camera at all and the screen a flat grey. the operative this machine
		## drives says outright that it is the one looking.
		if camera != null:
			camera.make_current()
	else:
		_go_remote()
	## everything that draws for the player binds on this rather than looking for a node that may
	## not have been spawned yet: in a joined game the operative arrives from the host a moment after
	## the hud has already asked for it.
	if _local:
		Net.announce_local.call_deferred(self)

	## what actually crosses the wire for an operative: where the body is, which way it is turned,
	## and where its head is and where that is looking. everything else another machine needs about
	## it -- the walk, the crouch, the lean, the aim line -- is worked out again from those four,
	## because a result is smaller and truer than the reasons for it. every frame, because this is
	## the one thing the other player is looking at.
	Netlink.sync(self, [".:position", ".:rotation", "Head:position", "Head:rotation"],
		get_multiplayer_authority())
	_base_sensitivity = mouse_sensitivity
	_apply_settings()
	Settings.changed.connect(_apply_settings)
	if movement == null:
		movement = MovementConfig.new()
	## capturing an unfocused window warps the real cursor and drags focus over, so the mouse is taken
	## only once the window has it. a launch that lands unfocused captures on the first click or focus.
	if _local and DisplayServer.window_is_focused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	## a unique capsule, otherwise resizing for crouch mutates the shared sub resource.
	_col.shape = _col.shape.duplicate()

	if _ceiling_check != null:
		_ceiling_check.add_exception(self)
		_ceiling_check.position.y = crouch_height - 0.28
		_ceiling_check.target_position = Vector3(0.0, stand_height - crouch_height, 0.0)

	_sm.setup(self)

	if health != null:
		health.died.connect(_on_died)


## everything that only makes sense for the operative this machine is driving: the camera, the mouse,
## the weapon in the corner of the screen, the verbs on the keys. a remote one keeps its body and its
## weapon (that is what the other player sees) and loses the rest.
func _go_remote() -> void:
	if camera != null:
		camera.current = false
	## disabling the viewmodel takes the weapon rack and all five guns with it, because they are its
	## children: a remote operative's rifle must not fire on MY trigger. they stay VISIBLE, which is
	## how you see what your teammate is carrying.
	for node in _kit:
		for group in REMOTE_SILENT:
			if node.is_in_group(group):
				node.remove_from_group(group)
		node.process_mode = Node.PROCESS_MODE_DISABLED
	if _sm != null:
		_sm.process_mode = Node.PROCESS_MODE_DISABLED
	## the viewmodel hangs where a first person camera wants it, which from the OUTSIDE is a rifle
	## floating past somebody's ear. it is parked at chest height instead: nothing here moves any
	## more, so where it is put is where it stays.
	## the rack sits inside the viewmodel and BOTH carry an offset, which together hold the weapon
	## most of a metre in front of the face: right for an eye that is inside the head, absurd for a
	## body being looked at. the pair is zeroed and the weapon put on the chest instead.
	var view := find_child("Viewmodel", true, false) as Node3D
	if view != null:
		view.position = Vector3.ZERO
		view.rotation = Vector3.ZERO
	var rack := get_node_or_null("Head/Camera3D/Viewmodel/Weapons") as Node3D
	if rack != null:
		rack.position = Vector3(0.20, -0.34, -0.26)
		rack.rotation = Vector3(0.0, deg_to_rad(-8.0), 0.0)
	_show_body()


## the body other machines see. the operative driving it is inside it looking out, so it is only
## built where it can actually be looked at -- except when its owner goes down, and then it is the
## thing their teammate is running towards.
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


## every operative on the floor, waiting for a hand. the revive looks here.
static func downed(tree: SceneTree) -> Array[Player]:
	var out: Array[Player] = []
	for node in tree.get_nodes_in_group("player"):
		var who := node as Player
		if who != null and is_instance_valid(who) and who.is_down():
			out.append(who)
	return out


## health reached zero. solo this is the end of the run and always was. with a teammate it is not:
## an operative on the floor is alive, visible and out of the fight until somebody comes for them,
## and the mission only fails when nobody is left standing. Run decides which of those it is; this
## only puts the body down, and it does it on every machine because everybody has to see where.
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
	## the view drops to the grass. it is not a death screen: you are lying in the compound watching
	## a patrol walk past your teammate, which is the whole of what being down is for.
	head.position.y = 0.4
	if _avatar != null:
		_avatar.lie(true)


## somebody got a hand to you. back on your feet with enough health to move and not enough to be
## careless, which is what makes a revive a reprieve rather than a reset.
@rpc("any_peer", "call_local", "reliable")
func net_revive(amount: float) -> void:
	if not _down:
		return
	_down = false
	if health != null:
		## revive() fills it; the amount is what a hand up is actually worth, and it is set after so
		## the health_changed the bar listens to is the one carrying the real number.
		health.revive()
		health.current = clampf(amount, 1.0, health.max_health)
		health.health_changed.emit(health.current, health.max_health)
	_since_hurt = 0.0
	_freeze_kit(false)
	head.position.y = stand_eye
	if _avatar != null:
		_avatar.lie(false)
	Sfx.play_2d(&"pickup")


## the kit stops working while an operative is down, and comes back with them. it is the same list
## a remote operative never runs at all, minus the footsteps: a body on the floor takes no steps.
func _freeze_kit(off: bool) -> void:
	## a REMOTE operative's kit is off for good, and being picked up must not switch it back on: every
	## one of those nodes reads the keyboard, so an aim scope or a takedown running on somebody else's
	## body would answer MY keys and act on their position. only the machine driving it gets it back.
	var stop := off or not _local
	for node in _kit:
		if is_instance_valid(node):
			node.process_mode = Node.PROCESS_MODE_DISABLED if stop else Node.PROCESS_MODE_INHERIT
	if _sm != null:
		_sm.process_mode = Node.PROCESS_MODE_DISABLED if stop else Node.PROCESS_MODE_INHERIT


## the operative this machine drives. everything on screen -- the hud, the reticle, the health bar,
## the bench, the board -- binds to this one and never to "a player".
static func local(tree: SceneTree) -> Player:
	return tree.get_first_node_in_group("local_player") as Player


## every operative in the level, on any machine. this is what the kiwis, the objectives and the
## scoring read: a garrison that only ever looked at one of two intruders is not a garrison.
static func all(tree: SceneTree) -> Array[Player]:
	var out: Array[Player] = []
	for node in tree.get_nodes_in_group("player"):
		var who := node as Player
		if who != null and is_instance_valid(who) and who.is_alive():
			out.append(who)
	return out


## the closest one to a point, alive. null when everybody is down, which is a real answer: it is
## what tells a hunter there is nothing left to hunt.
static func nearest(tree: SceneTree, from: Vector3) -> Player:
	var best: Player = null
	var near := INF
	for who in all(tree):
		var d := who.global_position.distance_squared_to(from)
		if d < near:
			near = d
			best = who
	return best


## the mouse is the player's only while nothing on screen owns it: not the pause menu (the tree is
## paused) and not a bench or a board (they join "holds_mouse" while open). alt-tabbing back with the
## bench up used to recapture the cursor over the sheet, which then had no pointer until escape.
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
		## aiming narrows the fov, so the look slows by the same ratio or fine aim is impossible.
		var sens := mouse_sensitivity * (_aim.sensitivity_mult() if _aim != null else 1.0)
		rotate_y(-motion.relative.x * sens)
		var pitch: float = motion.relative.y if invert_look else -motion.relative.y
		var limit := deg_to_rad(pitch_limit_deg)
		_pitch = clampf(_pitch + pitch * sens, -limit, limit)
		_apply_head()


func _physics_process(delta: float) -> void:
	## a body somebody else is driving is not simulated here: its transform arrives over the wire and
	## anything this ran would fight it. the pieces that still have to happen for a remote operative
	## -- its footstep noise, its shots, its takedowns -- are sent by the machine that owns it.
	if not _local or _down:
		return
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

	_update_stance(delta)
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
	match _stance:
		Stance.CROUCH:
			base = movement.crouch_max_speed
		Stance.PRONE:
			base = movement.prone_max_speed
		_:
			if Input.is_action_pressed("sprint"):
				base = movement.run_max_speed
	## carrying a body costs nothing. it briefly cost 45 percent, which made every corpse a haul and
	## quietly discouraged the tidiest thing a player can do; a kiwi is a small bird, and the price of
	## moving one is the seconds at either end.
	return base * (_aim.speed_mult() if _aim != null else 1.0)


func wants_jump() -> bool:
	## flat on the ground there is nothing to jump with. the press is not thrown away: it is what
	## stands you back up, in _update_stance.
	if _stance == Stance.PRONE:
		return false
	return Input.is_action_pressed("jump") if movement.auto_bhop else _jump_buffer > 0.0


func is_grounded() -> bool:
	return _grounded


func is_crouching() -> bool:
	return stance() == Stance.CROUCH


func is_prone() -> bool:
	return stance() == Stance.PRONE


## 0 standing, 1 crouched, 2 prone. everything that cares -- the cones, the boots, the reticle --
## asks this one question.
##
## a REMOTE operative's answer is read off its head, and that is a fix as much as an addition. the
## head's height is already on the wire, because the aim line comes off it; a second message saying
## the same thing is a second thing that can disagree with the first. until now `is_crouching` on a
## teammate's puppet was simply false forever, so the birds tested a crouching client at standing
## height and standing range, and the client had no way of knowing why they kept being seen.
func stance() -> int:
	if not _local and head != null:
		if head.position.y <= (prone_eye + crouch_eye) * 0.5:
			return Stance.PRONE
		if head.position.y <= (crouch_eye + stand_eye) * 0.5:
			return Stance.CROUCH
		return Stance.STAND
	return _stance


## a laser found you. the damage goes to the health component, the kick and the shake to the camera.
##
## the birds think on the host, so a beam that found a CLIENT found the host's puppet of them: the
## damage has to be sent to the machine that owns that operative, or a joined player would be
## immortal and would never know why. the host is still the one that decided; this only carries it.
func take_laser_hit(amount: float, from: Vector3) -> void:
	if not is_multiplayer_authority():
		_net_hurt.rpc_id(get_multiplayer_authority(), amount, from)
		return
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


@rpc("any_peer", "call_remote", "reliable")
func _net_hurt(amount: float, from: Vector3) -> void:
	if is_multiplayer_authority():
		take_laser_hit(amount, from)


## alive AND on their feet. an operative on the floor is out of the fight: the birds stop looking for
## them, the objectives stop counting them, and the mission asks whether ANYBODY is still standing.
func is_alive() -> bool:
	if _down:
		return false
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
	if not _grounded or _stance != Stance.STAND or not Input.is_action_pressed("sprint"):
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


## crouch is HELD and prone is a TOGGLE, which is not an inconsistency: crouching is something you
## do for a few seconds behind a crate, and prone is something you do for the length of a crawl
## across open ground. holding a key down for that is not a control, it is a punishment, and every
## game that has both binds them this way.
func _update_stance(delta: float) -> void:
	## the engine's own edge, deliberately. this was briefly worked out here from last tick's state
	## instead, on a theory about `is_action_just_pressed` firing twice per rendered frame -- the
	## theory was never demonstrated, it fixed none of the prone symptoms, and the co-op probe
	## caught what it DID cost: a press that begins and ends between two physics ticks is invisible
	## to remembered state and is not invisible to the engine's flag. Keeping the engine's answer
	## is both the smaller change and the more forgiving one. The jump edge is still read once and
	## shared with the buffer below, which is the only part of that attempt worth keeping.
	_jump_hit = Input.is_action_just_pressed("jump")

	var want := _stance
	if Input.is_action_just_pressed("prone"):
		want = Stance.STAND if _stance == Stance.PRONE else Stance.PRONE
		_crouch_latch = false
	elif _stance == Stance.PRONE:
		## from flat, crouch gets you up ONE step and jump gets you all the way up. neither should
		## have to be pressed twice, and a player who wants to move NOW presses jump.
		if Input.is_action_just_pressed("crouch"):
			want = Stance.CROUCH
			_crouch_latch = true
		elif _jump_hit:
			want = Stance.STAND
			_jump_spent = true
	else:
		## the latch is what makes that step up STICK. it is given up the moment the player says
		## anything else about their stance -- another press of crouch, a jump, a sprint -- and the
		## key is a plain hold again from there, so a second tap of crouch takes them from crouched
		## to standing and the two keys read as one ladder: Z down, Ctrl up a step, Space up.
		if _crouch_latch and (Input.is_action_just_pressed("crouch") or _jump_hit
				or Input.is_action_pressed("sprint")):
			_crouch_latch = false
		want = Stance.CROUCH if Input.is_action_pressed("crouch") or _crouch_latch else Stance.STAND

	## refuse to rise into something. the cast is pointed at whatever the rise actually IS: prone to
	## crouch is not the same gap as crouch to standing, and one cast configured for the taller of
	## the two would refuse a crawl out from under a truck it fits under perfectly well.
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


## the capsule at any point on the ladder. it is piecewise on purpose: standing to prone passes
## THROUGH the crouch, which is what the body would actually do.
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
	## the cast has to START CLEAR OF THE FLOOR, and this is the whole of the prone bug. the
	## convention is that the sphere's top touches the height you are at now, which is fine from a
	## 1.0 m crouch: a 0.28 sphere centred at 0.72 spans 0.44 to 1.0. From a 0.55 m prone it centres
	## at 0.27 and spans -0.01 to 0.55 -- through the ground. A ShapeCast3D that begins already
	## overlapping something reports a hit before it has moved an inch, so EVERY way out of prone
	## was refused: Z did not stand you up, crouch did not lift you, jump did nothing. Clamped so
	## the sphere always begins just above the floor, which leaves the crouch case untouched.
	var radius := 0.28
	var ball := _ceiling_check.shape as SphereShape3D
	if ball != null:
		radius = ball.radius
	_ceiling_check.position.y = maxf(now - radius, radius + 0.05)
	_ceiling_check.target_position = Vector3(0.0, to - now, 0.0)
	_ceiling_check.force_shapecast_update()
	return not _ceiling_check.is_colliding()


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
	## the same edge the stance machine already read, so one press is one buffered jump.
	if _jump_hit:
		## the press that got the operative off the floor is not also a leap out of cover.
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
	## every machine puts its OWN operative on the marker, so two of them would arrive inside each
	## other and shove one another off it. they stand a step apart instead, in a fixed order taken
	## from the peer id, so both machines agree on who is on which side without asking.
	var apart := Vector3.ZERO
	if Net.is_online():
		var ids := Net.peers.keys()
		ids.sort()
		var index := maxi(ids.find(get_multiplayer_authority()), 0)
		apart = Vector3(RIGHT_OF_SPAWN * float(index), 0.0, 0.0).rotated(
			Vector3.UP, spawn.global_rotation.y)
	global_position = ground_under(spawn.global_position + apart)
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
