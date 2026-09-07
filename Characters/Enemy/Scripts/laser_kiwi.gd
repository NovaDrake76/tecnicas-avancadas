class_name LaserKiwi
extends Kiwi


enum Attack { NONE, BURST, CHARGE, BEAM, RECOVER }

@export_group("Hunt")
## it stands and shoots inside this, closes in outside it.
@export var attack_range := 18.0
## a hunter keeps calling while it hunts, so a squad closing in can be counted by ear.
@export var hunt_call_interval := Vector2(3.5, 6.5)

@export_group("Armour")
## a plain kiwi goes down to one bb because that is the airsoft fiction: a hit puts a target out.
@export var armour_threshold := 0.6
## qualifying body hits before it goes down.
@export var plate_health := 3
## a bb that bounced still tells it where you are.
@export var plate_alerts := true

@export_group("Burst")
@export var pulses := 4
@export var pulse_gap := 0.16
## a burst that connects is a real event on a player whose regeneration stops at seventy.
@export var pulse_damage := 9.0
@export var pulse_spread := 0.14
## how fast a bolt flies.
@export var bolt_speed := 38.0
## a burst is aimed where you will be when it arrives; off, it is aimed where you are, which a walk dodges.
@export var lead_shots := true
@export var burst_recover := 0.8

@export_group("Beam")
@export var charge_time := 1.1
@export var beam_time := 1.4
@export var beam_dps := 30.0
@export var beam_recover := 1.8
## how fast the beam can follow you, in metres per second at the target.
@export var beam_track := 10.0
@export_range(0.0, 1.0) var beam_chance := 0.4
@export var beam_cooldown := 6.0
@export var laser_range := 40.0

@onready var eyes: LaserEyes = $Eyes

var armour: KiwiArmour
var _plate := 0
var _attack := Attack.NONE
var _attack_timer := 0.0
var _pulses_left := 0
var _pulse_right := false
var _aim := Vector3.ZERO
var _beam_ready := 0.0
var _suppressing := false
var _unseen_for := 0.0


func _ready() -> void:
	super()
	eyes.bind(find_child("Skeleton3D", true, false) as Skeleton3D)
	_plate = plate_health
	armour = KiwiArmour.new()
	armour.kind = _armour_kind()
	add_child(armour)
	armour.bind(self, eyes)
	Squad.leader_changed.connect(func(k: Node3D) -> void:
		if armour != null and is_instance_valid(armour):
			armour.set_leader(k == self))


func _armour_kind() -> KiwiArmour.Kind:
	return KiwiArmour.Kind.LASER


func _physics_process(delta: float) -> void:
	_beam_ready = maxf(0.0, _beam_ready - delta)
	_since_burst += delta
	if _state == State.HUNT or _state == State.ATTACK:
		_hunt_call -= delta
		if _hunt_call <= 0.0:
			_hunt_call = randf_range(hunt_call_interval.x, hunt_call_interval.y)
			voice.alarm()
	super(delta)


func _on_alarmed(from: Vector3) -> void:
	_begin_hunt(from)


func told(at: Vector3) -> void:
	if is_hunting():
		_last_seen = at
		_search = search_time
		_stuck = 0.0
		return
	super(at)


func _begin_hunt(toward: Vector3) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = Player.nearest(get_tree(), global_position)
	if _player == null:
		_begin_idle()
		return
	_last_seen = toward
	_search = search_time
	_stuck = 0.0
	_attack = Attack.NONE
	_suppressing = false
	_role_goal = Vector3.INF
	_state = State.HUNT
	_hunt_call = randf_range(hunt_call_interval.x, hunt_call_interval.y)
	_play(run_clip, 0.15)
	voice.alarm()
	Squad.join(self)
	awareness_changed.emit(self, 1.0)


func _step_hunt(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) \
			or (_player.has_method("is_alive") and not _player.is_alive()):
		_end_hunt()
		return
	if Alarm.stage == Alarm.Stage.CALM:
		_end_hunt()
		return
	var at := VisionCone.sight_point(_player)
	var dist := global_position.distance_to(_player.global_position)
	_seen = dist <= hunt_sight and vision.sees_point(at, hunt_sight)
	_unseen_for = 0.0 if _seen else _unseen_for + delta
	if _seen:
		_last_seen = _player.global_position
		_search = search_time
		Alarm.report_contact(_last_seen)
	elif Alarm.stage == Alarm.Stage.ALARM:
		_search = search_time
		var believed := Alarm.search_point(get_instance_id())
		if Alarm.has_last_known and believed.distance_to(_last_seen) > 1.5:
			_last_seen = believed
			_stuck = 0.0

	var idle_phase := _attack == Attack.NONE or _attack == Attack.RECOVER
	if not _seen and Alarm.stage != Alarm.Stage.ALARM and _search <= 0.0 and idle_phase:
		_end_hunt()
		return

	if _state == State.ATTACK:
		_step_attack(delta, at, dist)
		return

	if _seen and dist <= attack_range:
		if Squad.request_fire(self):
			_begin_attack()
		else:
			_step_role(delta)
		return

	if not _seen and _suppress_possible() and Squad.request_fire(self):
		_begin_suppress()
		return
	if not _seen and _is_suppressor() and _beam_ready <= 0.0 and Alarm.has_last_known and _unseen_for < 0.8:
		velocity.x = move_toward(velocity.x, 0.0, hunt_speed * 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, hunt_speed * 6.0 * delta)
		_turn_to(Alarm.last_known, turn_speed * 2.0, delta)
		return

	_role_goal = Vector3.INF
	var goal := _player.global_position if _seen else _last_seen
	var arrived := _move_to(goal, hunt_speed, delta)
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


func _step_role(delta: float) -> void:
	var job := Squad.role_for(self)
	_role_timer -= delta
	if _role_goal == Vector3.INF or _role_timer <= 0.0 or _role_role != job:
		_role_role = job
		_role_timer = Squad.ROLE_INTERVAL
		_role_arrived = false
		if job == Squad.Role.FLANK:
			_role_goal = Squad.flank_point(self, _player.global_position)
		elif job == Squad.Role.APPROACH:
			_role_goal = Vector3.INF
		else:
			_role_goal = Squad.claim_cover(self, _player.global_position, false)
		if _role_goal == Vector3.INF and job != Squad.Role.APPROACH and (job != Squad.Role.HOLD or Squad.is_rattled()):
			_role_goal = Squad.tangent_point(self, _player.global_position)
	var dist := global_position.distance_to(_player.global_position)
	if job == Squad.Role.APPROACH and Squad.player_quiet() > Squad.QUIET_TO_ADVANCE and not is_suppressed() and dist > approach_stop:
		_play(run_clip, 0.15)
		_move_to(_player.global_position, hunt_speed, delta)
		return
	if _role_goal == Vector3.INF or _role_arrived:
		velocity.x = move_toward(velocity.x, 0.0, hunt_speed * 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, hunt_speed * 6.0 * delta)
		_turn_to(_player.global_position, turn_speed * 2.0, delta)
		if not idle_clips.is_empty():
			_play(idle_clips[0], 0.2)
		return
	_play(run_clip, 0.15)
	if _move_to(_role_goal, hunt_speed, delta):
		_role_arrived = true
		return
	var moved := get_position_delta().length() / maxf(delta, 0.0001) > 0.3
	_stuck = 0.0 if moved else _stuck + delta
	if _stuck > stuck_time:
		_stuck = 0.0
		_role_goal = Squad.tangent_point(self, _player.global_position, -1 if randf() < 0.5 else 1)


func _begin_attack() -> void:
	_state = State.ATTACK
	_attack = Attack.NONE
	_suppressing = false
	## a still head: the eyes are where the beam leaves, and the looking-about clips would swing them.
	_attack_timer = 0.15
	if not idle_clips.is_empty():
		_play(idle_clips[0], 0.2)


func _is_suppressor() -> bool:
	return Squad.hunter_count() <= 1 or Squad.role_for(self) == Squad.Role.SUPPRESS


func _suppress_possible() -> bool:
	if not _is_suppressor() or _beam_ready > 0.0 or not Alarm.has_last_known:
		return false
	if _unseen_for < 0.8:
		return false
	var d := global_position.distance_to(Alarm.last_known)
	return d > 2.0 and d <= attack_range * 1.3


func _begin_suppress() -> void:
	_state = State.ATTACK
	_suppressing = true
	_aim = Alarm.last_known + Vector3.UP * 0.9
	_attack = Attack.CHARGE
	_attack_timer = charge_time
	_beam_ready = beam_cooldown
	_net_charge.rpc(charge_time)
	if not idle_clips.is_empty():
		_play(idle_clips[0], 0.2)


func _step_attack(delta: float, at: Vector3, dist: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, hunt_speed * 6.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, hunt_speed * 6.0 * delta)
	_turn_to(_aim if _suppressing else _player.global_position, turn_speed * 2.0, delta)
	_attack_timer -= delta
	if _suppressing:
		_search -= delta

	match _attack:
		Attack.NONE:
			if _attack_timer <= 0.0:
				if not _seen or dist > attack_range + 3.0 or not Squad.request_fire(self):
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
			_aim_during_charge(at)
			if not _seen and not _suppressing:
				eyes.charge_stop(true)
				eyes.set_glow(0.0)
				_resume_hunt()
				return
			if _attack_timer <= 0.0:
				eyes.charge_stop(false)
				_fire_charged()
		Attack.BEAM:
			if not _suppressing:
				var ahead := at
				if "velocity" in _player:
					var v: Vector3 = _player.velocity
					v.y = 0.0
					ahead = at + v * 0.12
				_aim = _aim.move_toward(ahead, beam_track * delta)
			var hit := _cast(eyes.between_eyes(), _aim)
			_net_beam_aim.rpc(hit["point"], hit["player"])
			if hit["player"]:
				_player.take_laser_hit(beam_dps * delta, global_position)
			if _attack_timer <= 0.0:
				_net_beam.rpc(false)
				eyes.set_glow(0.0)
				_attack = Attack.RECOVER
				_attack_timer = beam_recover
		Attack.RECOVER:
			if _attack_timer <= 0.0:
				_attack = Attack.NONE
				_suppressing = false
				Squad.release_fire(self)
				_attack_timer = 0.25
				if not _seen or dist > attack_range + 3.0:
					_resume_hunt()


func _choose_attack() -> void:
	if Squad.sync_hold(self):
		if _attack != Attack.CHARGE:
			_attack = Attack.NONE
			_attack_timer = 0.15
		return
	if _beam_ready <= 0.0 and randf() < beam_chance and _since_burst >= burst_recover:
		_start_charge()
	else:
		_attack = Attack.BURST
		_pulses_left = pulses
		_pulse_right = randf() < 0.5
		_attack_timer = 0.0
		_since_burst = 0.0


var _since_burst := 99.0
var _hunt_call := 0.0


func _aim_during_charge(_at: Vector3) -> void:
	pass


func aim_point() -> Vector3:
	return _aim


func _fire_charged() -> void:
	_net_beam.rpc(true)
	_attack = Attack.BEAM
	_attack_timer = beam_time


@rpc("authority", "call_local", "reliable")
func _net_beam(on: bool) -> void:
	if on:
		eyes.beam_start()
	else:
		eyes.beam_stop()


@rpc("authority", "call_local", "unreliable")
func _net_beam_aim(at: Vector3, on_player: bool) -> void:
	eyes.beam_aim(at, on_player)


func _start_charge() -> void:
	_attack = Attack.CHARGE
	_suppressing = false
	_attack_timer = charge_time
	_aim = VisionCone.sight_point(_player)
	_beam_ready = beam_cooldown
	_net_charge.rpc(charge_time)


@rpc("authority", "call_local", "reliable")
func _net_charge(seconds: float) -> void:
	eyes.charge_start(seconds)


func sync_charge() -> bool:
	if _state != State.ATTACK or _player == null or not _seen:
		return false
	if _attack == Attack.CHARGE or _attack == Attack.BEAM:
		return true
	if _attack == Attack.BURST:
		return false
	eyes.beam_stop()
	_start_charge()
	return true


func rattle() -> void:
	if not is_hunting():
		return
	_abort_attack()
	_resume_hunt()
	_role_goal = Vector3.INF
	_role_timer = 0.0


## a bird told mid-burst hands its turn back before it talks, or the squad counts a talker as a shooter.
func _begin_call(from: Vector3) -> void:
	if _state == State.ATTACK:
		_abort_attack()
		Squad.release_fire(self)
	super(from)


func _abort_attack() -> void:
	eyes.beam_stop()
	eyes.charge_stop(_attack == Attack.CHARGE)
	eyes.set_glow(0.0)
	_attack = Attack.NONE
	_suppressing = false


func _interrupt_for_peck() -> void:
	if _state == State.ATTACK:
		_abort_attack()
		Squad.release_fire(self)
		_state = State.HUNT


func beam_ready() -> bool:
	return _beam_ready <= 0.0


func is_suppressing() -> bool:
	return _state == State.ATTACK and _suppressing


func role() -> int:
	return Squad.role_for(self)


func _fire_pulse() -> void:
	if _attack == Attack.CHARGE or _attack == Attack.BEAM or eyes.is_beaming():
		return
	_since_burst = 0.0
	var from := eyes.eye_position(_pulse_right)
	_pulse_right = not _pulse_right
	var spread := pulse_spread * (2.0 if Squad.is_rattled() or is_suppressed() else 1.0)
	var at := VisionCone.sight_point(_player)
	var flight := from.distance_to(at) / maxf(bolt_speed, 0.01)
	var lead := Vector3.ZERO
	if lead_shots and "velocity" in _player:
		lead = (_player.velocity as Vector3) * flight
		lead.y = 0.0
	var to := at + lead + Vector3(
		randf_range(-spread, spread),
		randf_range(-spread, spread),
		randf_range(-spread, spread))
	_net_bolt.rpc(from, to)


@rpc("authority", "call_local", "reliable")
func _net_bolt(from: Vector3, to: Vector3) -> void:
	eyes.zap()
	LaserBolt.launch(get_parent(), from, to, bolt_speed, laser_range,
		pulse_damage if multiplayer.is_server() else 0.0, self, eyes)


func _cast(from: Vector3, toward: Vector3) -> Dictionary:
	var dir := toward - from
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	dir = dir.normalized()
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * laser_range, 3)
	query.exclude = [get_rid()]
	## a bird pressed against a wall has its eyes inside it, and a ray that starts inside a body reports nothing; the beam came out the far side into a hidden player.
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"point": from + dir * laser_range, "player": false}
	return {"point": hit["position"], "player": hit["collider"] == _player}


func _resume_hunt() -> void:
	_attack = Attack.NONE
	_suppressing = false
	Squad.release_fire(self)
	_state = State.HUNT
	_stuck = 0.0
	_play(run_clip, 0.15)


func _end_hunt() -> void:
	eyes.beam_stop()
	eyes.charge_stop(false)
	eyes.set_glow(0.0)
	_attack = Attack.NONE
	_suppressing = false
	super()


func hear(at: Vector3, radius: float) -> void:
	if _state == State.HUNT or _state == State.ATTACK:
		if not _seen and _state != State.DOWN and global_position.distance_to(at) <= radius:
			_last_seen = at
			_search = search_time
			_stuck = 0.0
		return
	super(at, radius)


func take_bb_hit(damage := 1.0, at := Vector3.INF, energy := -1.0) -> void:
	if _state == State.DOWN:
		return
	if energy < 0.0:
		if armour != null:
			armour.shed()
		super(damage, at, energy)
		return
	if energy < armour_threshold:
		if armour != null:
			armour.bounce(at)
		if plate_alerts:
			var shooter := Player.nearest(get_tree(), at)
			saw(shooter.global_position if shooter != null else at)
		return
	_plate -= 1
	if _plate > 0:
		if armour != null:
			armour.dent(at)
		if plate_alerts:
			var shooter := Player.nearest(get_tree(), at)
			saw(shooter.global_position if shooter != null else at)
		return
	if armour != null:
		armour.shed()
	super(damage, at, energy)


func take_weak_hit(at: Vector3) -> void:
	if _state == State.DOWN:
		return
	Sfx.play(&"bb_glass", at if at.is_finite() else global_position + Vector3.UP * 0.4)
	if armour != null:
		armour.shed()
	_plate = 0
	health.take_damage(health.max_health + 1.0)


func plate_left() -> int:
	return _plate


func _go_down() -> void:
	if _state == State.DOWN:
		return
	eyes.shut_down()
	if armour != null:
		armour.hide_all()
	Squad.leave(self, true)
	awareness_changed.emit(self, 0.0)
	super()


func stand_down() -> void:
	if _state == State.DOWN:
		return
	if is_hunting():
		_end_hunt()
	super()



func is_attacking() -> bool:
	return _state == State.ATTACK


func attack_phase() -> Attack:
	return _attack


func can_see_target() -> bool:
	return _seen


func demo_pulse(target: Node3D) -> void:
	_player = target
	_fire_pulse()


func demo_attack(kind: String, target: Node3D) -> void:
	_player = target
	_last_seen = target.global_position
	Alarm.raise_search(_last_seen)
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


func kind_name() -> String:
	return "LASER"
