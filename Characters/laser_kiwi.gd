class_name LaserKiwi
extends Kiwi

## a kiwi that does not run. once it has seen you it hunts you, and while it can see you it fires
## lasers out of its eyes: short bursts of bolts, or one long beam that has to be charged first.
## neither is a sure hit. a bolt is a projectile aimed where you were, so a step taken after it
## leaves is a miss; the beam starts where you stood when the charge began and sweeps after you at
## a speed a sprint beats. standing still is what gets you hit. it is still a kiwi: one bb puts it
## down, its neighbours witness that, and it counts towards the mission like any other.

enum Attack { NONE, BURST, CHARGE, BEAM, RECOVER }

@export_group("Hunt")
@export var hunt_speed := 3.6
## it stands and shoots inside this, closes in outside it.
@export var attack_range := 18.0
## once it knows you are there it picks you out further than a calm bird would.
@export var hunt_sight := 32.0
## how long it searches where it last saw you before it gives up and goes back to loafing.
@export var search_time := 3.5
@export var stuck_time := 1.0

@export_group("Burst")
@export var pulses := 4
@export var pulse_gap := 0.16
@export var pulse_damage := 7.0
@export var pulse_spread := 0.14
## how fast a bolt flies. at 10 m that is a quarter of a second to step aside; at 3 m it is nothing,
## which is what makes range the player's tool against a laser kiwi.
@export var bolt_speed := 38.0
@export var burst_recover := 1.2

@export_group("Beam")
@export var charge_time := 1.1
@export var beam_time := 1.4
@export var beam_dps := 30.0
@export var beam_recover := 1.8
## how fast the beam can follow you, in metres per second at the target. the player walks at 6.35
## and runs at 9, so a walk is caught and a sprint is not, and a sprint is the loud one.
@export var beam_track := 7.0
@export_range(0.0, 1.0) var beam_chance := 0.4
@export var beam_cooldown := 6.0
@export var laser_range := 40.0

@onready var eyes: LaserEyes = $Eyes

var _player: Node3D
var _last_seen := Vector3.ZERO
var _search := 0.0
var _stuck := 0.0
var _seen := false
var _attack := Attack.NONE
var _attack_timer := 0.0
var _pulses_left := 0
var _pulse_right := false
var _aim := Vector3.ZERO
var _beam_ready := 0.0


func _ready() -> void:
	super()
	eyes.bind(find_child("Skeleton3D", true, false) as Skeleton3D)


func _physics_process(delta: float) -> void:
	_beam_ready = maxf(0.0, _beam_ready - delta)
	if _state == State.HUNT or _state == State.ATTACK:
		_step_hunt(delta)
	super(delta)


## every alarm a plain kiwi answers by running, this one answers by hunting. the point handed in is
## where the trouble was: the player when it saw you, the body when it saw a neighbour go down.
func _begin_flee(away_from: Vector3) -> void:
	_begin_hunt(away_from)


func _begin_hunt(toward: Vector3) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		_begin_idle()
		return
	_last_seen = toward
	_search = search_time
	_stuck = 0.0
	_attack = Attack.NONE
	_state = State.HUNT
	_play(run_clip, 0.15)
	speak(alert_pitch, alert_db)
	## the hud's ring keeps an arc on a bird that is hunting you, at its bearing, for as long as it is.
	awareness_changed.emit(self, 1.0)


func _step_hunt(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) \
			or (_player.has_method("is_alive") and not _player.is_alive()):
		_end_hunt()
		return
	var at := VisionCone.sight_point(_player)
	var dist := global_position.distance_to(_player.global_position)
	_seen = dist <= hunt_sight and vision.sees_point(at, hunt_sight)
	if _seen:
		_last_seen = _player.global_position
		_search = search_time

	if _state == State.ATTACK:
		_step_attack(delta, at, dist)
		return

	if _seen and dist <= attack_range:
		_begin_attack()
		return

	var goal := _player.global_position if _seen else _last_seen
	var arrived := _move_to(goal, hunt_speed, delta)
	## the wish speed says nothing about a wall; what it actually moved last tick does.
	var moved := get_position_delta().length() / maxf(delta, 0.0001) > 0.3
	_stuck = 0.0 if moved or arrived else _stuck + delta
	if _seen:
		return
	if arrived or _stuck > stuck_time:
		velocity.x = 0.0
		velocity.z = 0.0
		if not idle_clips.is_empty():
			_play(idle_clips[0])
		rotation.y += delta * 1.1
		_search -= delta
		if _search <= 0.0:
			_end_hunt()


func _begin_attack() -> void:
	_state = State.ATTACK
	_attack = Attack.NONE
	_attack_timer = 0.15
	## a still head: the eyes are where the beam leaves, and the looking-about clips would swing them.
	if not idle_clips.is_empty():
		_play(idle_clips[0], 0.2)


func _step_attack(delta: float, at: Vector3, dist: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, hunt_speed * 6.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, hunt_speed * 6.0 * delta)
	_turn_to(_player.global_position, turn_speed * 2.0, delta)
	_attack_timer -= delta

	match _attack:
		Attack.NONE:
			if _attack_timer <= 0.0:
				if not _seen or dist > attack_range + 3.0:
					_resume_hunt()
				else:
					_choose_attack()
		Attack.BURST:
			if _attack_timer <= 0.0:
				if _pulses_left > 0:
					_fire_pulse()
					_pulses_left -= 1
					_attack_timer = pulse_gap
				else:
					_attack = Attack.RECOVER
					_attack_timer = burst_recover
		Attack.CHARGE:
			eyes.set_glow(1.0 - _attack_timer / charge_time)
			## the charge is the tell. break the line and the beam never comes.
			if not _seen:
				eyes.charge_stop(true)
				eyes.set_glow(0.0)
				_resume_hunt()
				return
			if _attack_timer <= 0.0:
				eyes.charge_stop(false)
				eyes.beam_start()
				## the aim is where you stood when the charge BEGAN, set in _choose_attack. a beam that opened
				## on your current position would make the charge a warning you could do nothing with.
				_attack = Attack.BEAM
				_attack_timer = beam_time
		Attack.BEAM:
			_aim = _aim.move_toward(at, beam_track * delta)
			var hit := _cast(eyes.between_eyes(), _aim)
			eyes.beam_aim(hit["point"], hit["player"])
			if hit["player"]:
				_player.take_laser_hit(beam_dps * delta, global_position)
			if _attack_timer <= 0.0:
				eyes.beam_stop()
				eyes.set_glow(0.0)
				_attack = Attack.RECOVER
				_attack_timer = beam_recover
		Attack.RECOVER:
			if _attack_timer <= 0.0:
				_attack = Attack.NONE
				if not _seen or dist > attack_range + 3.0:
					_resume_hunt()


func _choose_attack() -> void:
	if _beam_ready <= 0.0 and randf() < beam_chance:
		_attack = Attack.CHARGE
		_attack_timer = charge_time
		_aim = VisionCone.sight_point(_player)
		_beam_ready = beam_cooldown
		eyes.charge_start(charge_time)
	else:
		_attack = Attack.BURST
		_pulses_left = pulses
		_pulse_right = randf() < 0.5
		_attack_timer = 0.0


## one bolt from one eye, the eyes alternating, launched at where the player is right now with a
## little scatter so a burst walks rather than stacks. it is a projectile: whether it lands is
## decided when it arrives, by where the player is then.
func _fire_pulse() -> void:
	var from := eyes.eye_position(_pulse_right)
	_pulse_right = not _pulse_right
	var to := VisionCone.sight_point(_player) + Vector3(
		randf_range(-pulse_spread, pulse_spread),
		randf_range(-pulse_spread, pulse_spread),
		randf_range(-pulse_spread, pulse_spread))
	eyes.zap()
	LaserBolt.launch(get_parent(), from, to, bolt_speed, laser_range, pulse_damage, self, eyes)


## the world and the player stop a laser, other kiwis do not. whatever it hits, the light ends there,
## which is what lets a wall between you and it show you the wall being scorched instead of you.
func _cast(from: Vector3, toward: Vector3) -> Dictionary:
	var dir := toward - from
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	dir = dir.normalized()
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * laser_range, 3)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"point": from + dir * laser_range, "player": false}
	return {"point": hit["position"], "player": hit["collider"] == _player}


func _resume_hunt() -> void:
	_attack = Attack.NONE
	_state = State.HUNT
	_stuck = 0.0
	_play(run_clip, 0.15)


## the hunt is over: back to watching, still alarmed, and the hud drops the arc.
func _end_hunt() -> void:
	eyes.beam_stop()
	eyes.charge_stop(false)
	eyes.set_glow(0.0)
	_attack = Attack.NONE
	vision.rearm()
	_home = global_position
	awareness_changed.emit(self, 0.0)
	_begin_idle()


## a noise while it is searching for you sends it there. while it can see you it needs no help.
func hear(at: Vector3, radius: float) -> void:
	if _state == State.HUNT or _state == State.ATTACK:
		if not _seen and _state != State.DOWN and global_position.distance_to(at) <= radius:
			_last_seen = at
			_search = search_time
			_stuck = 0.0
		return
	super(at, radius)


func _go_down() -> void:
	if _state == State.DOWN:
		return
	eyes.shut_down()
	awareness_changed.emit(self, 0.0)
	super()


func is_hunting() -> bool:
	return _state == State.HUNT or _state == State.ATTACK


func is_attacking() -> bool:
	return _state == State.ATTACK


func attack_phase() -> Attack:
	return _attack


func can_see_target() -> bool:
	return _seen


## for the probes: exactly one bolt at the target, nothing else changes.
func demo_pulse(target: Node3D) -> void:
	_player = target
	_fire_pulse()


## for the tools: put it straight into an attack so the effects can be photographed.
func demo_attack(kind: String, target: Node3D) -> void:
	_player = target
	_last_seen = target.global_position
	_seen = true
	_state = State.ATTACK
	if not idle_clips.is_empty():
		_play(idle_clips[0])
	match kind:
		"charge":
			_attack = Attack.CHARGE
			_attack_timer = charge_time
			eyes.charge_start(charge_time)
		"beam":
			_attack = Attack.BEAM
			_attack_timer = beam_time
			_aim = VisionCone.sight_point(target)
			eyes.set_glow(1.0)
			eyes.beam_start()
		_:
			_attack = Attack.BURST
			_pulses_left = 999
			_attack_timer = 0.0
