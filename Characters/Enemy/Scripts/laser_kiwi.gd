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
## a hunter keeps calling while it hunts, so a squad closing in can be counted by ear.
@export var hunt_call_interval := Vector2(3.5, 6.5)
@export var stuck_time := 1.0

@export_group("Armour")
## a plain kiwi goes down to one bb because that is the airsoft fiction: a hit puts a target out.
## "this one needs six" would have no fiction behind it. instead it wears plate you can see, and the
## answer is precision or energy. a body hit only counts if the bb ARRIVES with at least this much,
## which the stock kit manages inside about ten metres and a heavy bb on a stiff spring inside about
## twenty-five: the bench's impact bar is the number that decides fights now.
@export var armour_threshold := 0.6
## qualifying body hits before it goes down.
@export var plate_health := 3
## a bb that bounced still tells it where you are. plinking the plate is a mistake with a price,
## which is what makes the eyes worth aiming for.
@export var plate_alerts := true

@export_group("Burst")
@export var pulses := 4
@export var pulse_gap := 0.16
## a burst that connects is a real event on a player whose regeneration stops at seventy.
@export var pulse_damage := 9.0
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

var armour: KiwiArmour
var _plate := 0
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
var _suppressing := false
var _unseen_for := 0.0
var _role_goal := Vector3.INF
var _role_timer := 0.0
var _role_role := 0
var _role_arrived := false


func _ready() -> void:
	super()
	eyes.bind(find_child("Skeleton3D", true, false) as Skeleton3D)
	_plate = plate_health
	armour = KiwiArmour.new()
	add_child(armour)
	armour.bind(self, eyes)
	## the leader's trim is how the player tells the priority target from the rest
	Squad.leader_changed.connect(func(k: Node3D) -> void:
		if armour != null and is_instance_valid(armour):
			armour.set_leader(k == self))


func _physics_process(delta: float) -> void:
	_beam_ready = maxf(0.0, _beam_ready - delta)
	_since_burst += delta
	if _state == State.HUNT or _state == State.ATTACK:
		_hunt_call -= delta
		if _hunt_call <= 0.0:
			_hunt_call = randf_range(hunt_call_interval.x, hunt_call_interval.y)
			speak(alert_pitch, alert_db)
		_step_hunt(delta)
	super(delta)


## every alarm a plain kiwi answers by running, this one answers by hunting. the point handed in is
## where the trouble was: the player when it saw you, the body when it saw a neighbour go down, the
## spot a runner shouted about.
func _on_alarmed(from: Vector3) -> void:
	_begin_hunt(from)


## a hunter told about you while already hunting only learns the newer spot.
func told(at: Vector3) -> void:
	if is_hunting():
		_last_seen = at
		_search = search_time
		_stuck = 0.0
		return
	super(at)


## a hunter that can see the player right now is ENGAGED rather than merely hunting, and the ring
## says which.
func has_contact() -> bool:
	return _seen


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
	speak(alert_pitch, alert_db)
	## nothing is raised here. a hunter reaches this line either because its own radio call went
	## through, or because it was shouted at by a bird whose call went through; raising it again
	## on the way into the hunt would put the compound's knowledge back on the same tick as the
	## sighting, which is the whole thing being fixed.
	## the squad is who decides whether this bird gets to shoot or has to move.
	Squad.join(self)
	## the hud's ring keeps an arc on a bird that is hunting you, at its bearing, for as long as it is.
	awareness_changed.emit(self, 1.0)


func _step_hunt(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) \
			or (_player.has_method("is_alive") and not _player.is_alive()):
		_end_hunt()
		return
	## the compound calming down is what ends a hunt. one clock drives the whole encounter, and the
	## player has exactly one job under fire: break contact and keep it broken.
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
		## under a full alarm it never gives up: it works the last place anyone saw you, and when the
		## compound learns something new it goes there.
		_search = search_time
		## the compound's belief, WIDENED by how old it is: every hunter picks its own spot on the
		## ring, so a stale search fans out instead of three birds standing on one patch of grass.
		var believed := Alarm.search_point(get_instance_id())
		if Alarm.has_last_known and believed.distance_to(_last_seen) > 1.5:
			_last_seen = believed
			_stuck = 0.0

	## the search clock is the whole hunt while the compound is only searching. it runs through a
	## suppressing beam too, or a bird would light up your cover every six seconds for as long as the
	## cooldown let it and never actually give up. a beam already on is allowed to finish.
	var idle_phase := _attack == Attack.NONE or _attack == Attack.RECOVER
	if not _seen and Alarm.stage != Alarm.Stage.ALARM and _search <= 0.0 and idle_phase:
		_end_hunt()
		return

	if _state == State.ATTACK:
		_step_attack(delta, at, dist)
		return

	## in sight and in range: an attack, if the squad gives this bird the turn. otherwise a role,
	## which is movement: the birds without a turn are the ones the player sees running about.
	if _seen and dist <= attack_range:
		if Squad.request_fire(self):
			_begin_attack()
		else:
			_step_role(delta)
		return

	## genuinely out of sight, with a beam ready and a spot to light up: suppression. it takes a turn
	## like any other shot, so the cap on how many beams are on you at once holds whatever the squad
	## is doing; and it waits out a moment of lost sight, or a bird running to its flank would stop to
	## light up cover you are standing in plain view beside.
	if not _seen and _suppress_possible() and Squad.request_fire(self):
		_begin_suppress()
		return

	_role_goal = Vector3.INF
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


## no turn to shoot: FLANK goes to cover on your far side, HOLD to cover on this side, and a bird
## with nowhere authored to go takes a step to the side rather than standing in a row. a rattled
## squad scatters the same way. arriving does not earn a turn; it puts the bird somewhere new, and
## movement is the point.
func _step_role(delta: float) -> void:
	var duty := Squad.role_for(self)
	_role_timer -= delta
	if _role_goal == Vector3.INF or _role_timer <= 0.0 or _role_role != duty:
		_role_role = duty
		_role_timer = Squad.ROLE_INTERVAL
		_role_arrived = false
		_role_goal = Squad.claim_cover(self, _player.global_position, duty == Squad.Role.FLANK)
		if _role_goal == Vector3.INF and (duty != Squad.Role.HOLD or Squad.is_rattled()):
			_role_goal = Squad.tangent_point(self, _player.global_position)
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
	_attack_timer = 0.15
	## a still head: the eyes are where the beam leaves, and the looking-about clips would swing them.
	if not idle_clips.is_empty():
		_play(idle_clips[0], 0.2)


## a beam on the last place anyone saw you, not on you. it lights up the cover you are behind and
## hurts if you step into it, on the existing ray with no new damage path. this is what stops the
## player from sitting still behind a crate for the rest of the fight.
func _suppress_possible() -> bool:
	if Squad.role_for(self) != Squad.Role.SUPPRESS or _beam_ready > 0.0 or not Alarm.has_last_known:
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
			## the charge is the tell. break the line and the beam never comes. a suppressing beam
			## is aimed at a spot, not at you, so losing sight of you does not stop it.
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
				_aim = _aim.move_toward(at, beam_track * delta)
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
				## the turn is handed back so another bird can take it. a beat before asking again
				## is what lets them actually take turns rather than the same bird re-grabbing it.
				Squad.release_fire(self)
				_attack_timer = 0.25
				if not _seen or dist > attack_range + 3.0:
					_resume_hunt()


## one weapon at a time. a beam never starts while bolts from a burst are still in the air (the
## recovery after a burst outlasts a bolt's flight), and a burst never fires while a beam is charging
## or on, so the player is never reading two attacks off one bird.
func _choose_attack() -> void:
	## the squad may be lining up a sync: hold a beat and let it start the charge for both
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


## where the aim sits while the charge runs. the laser kiwi leaves it where it was when the charge
## began; the sniper follows you until the last moment.
func _aim_during_charge(_at: Vector3) -> void:
	pass


func aim_point() -> Vector3:
	return _aim


## the charge is done: what comes out. for a laser kiwi it is the beam, opened on the aim locked when
## the charge BEGAN (a beam that opened on your current position would make the charge a warning you
## could do nothing with). the sniper overrides this with a single shot.
func _fire_charged() -> void:
	_net_beam.rpc(true)
	_attack = Attack.BEAM
	_attack_timer = beam_time


## the light itself, on every machine. where it LANDS is worked out where the bird is thought about
## and sent, because the ray is cast against the host's world and the answer is the same everywhere.
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


## the squad told this bird and another to charge together. whatever it was doing is dropped and
## the charge starts on this tick, so both pairs of eyes fill at once.
func sync_charge() -> bool:
	if _state != State.ATTACK or _player == null or not _seen:
		return false
	if _attack == Attack.CHARGE or _attack == Attack.BEAM:
		return true
	## a burst half fired is finished first; bolts in the air and a beam charging would read as two
	## attacks at once
	if _attack == Attack.BURST:
		return false
	eyes.beam_stop()
	_start_charge()
	return true


## the leader went down. whatever this bird was doing stops, and it dives for a new spot.
func rattle() -> void:
	if not is_hunting():
		return
	_abort_attack()
	_resume_hunt()
	_role_goal = Vector3.INF
	_role_timer = 0.0


func _abort_attack() -> void:
	eyes.beam_stop()
	eyes.charge_stop(_attack == Attack.CHARGE)
	eyes.set_glow(0.0)
	_attack = Attack.NONE
	_suppressing = false


func beam_ready() -> bool:
	return _beam_ready <= 0.0


func is_suppressing() -> bool:
	return _state == State.ATTACK and _suppressing


func role() -> int:
	return Squad.role_for(self)


## one bolt from one eye, the eyes alternating, launched at where the player is right now with a
## little scatter so a burst walks rather than stacks. it is a projectile: whether it lands is
## decided when it arrives, by where the player is then.
func _fire_pulse() -> void:
	## never over a beam: the two do not share the eyes
	if _attack == Attack.CHARGE or _attack == Attack.BEAM or eyes.is_beaming():
		return
	_since_burst = 0.0
	var from := eyes.eye_position(_pulse_right)
	_pulse_right = not _pulse_right
	## a rattled squad shoots wide
	var spread := pulse_spread * (2.0 if Squad.is_rattled() else 1.0)
	var to := VisionCone.sight_point(_player) + Vector3(
		randf_range(-spread, spread),
		randf_range(-spread, spread),
		randf_range(-spread, spread))
	## the bolt is thought about here and DRAWN everywhere. a joined player who was being shot at by
	## a bird whose fire they could not see would be taking damage from nothing at all, which is the
	## one thing a game may never do. only the host's copy carries damage: the others are the light.
	_net_bolt.rpc(from, to)


@rpc("authority", "call_local", "reliable")
func _net_bolt(from: Vector3, to: Vector3) -> void:
	eyes.zap()
	LaserBolt.launch(get_parent(), from, to, bolt_speed, laser_range,
		pulse_damage if multiplayer.is_server() else 0.0, self, eyes)


## the world and the player stop a laser, other kiwis do not. whatever it hits, the light ends there,
## which is what lets a wall between you and it show you the wall being scorched instead of you.
func _cast(from: Vector3, toward: Vector3) -> Dictionary:
	var dir := toward - from
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	dir = dir.normalized()
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * laser_range, 3)
	query.exclude = [get_rid()]
	## a bird pressed against a wall has its eyes inside it. a ray that starts inside a body reports
	## nothing by default and the beam came out the far side, into a player the wall was hiding.
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


## the hunt is over: back to watching, still alarmed, and the hud drops the arc.
func _end_hunt() -> void:
	eyes.beam_stop()
	eyes.charge_stop(false)
	eyes.set_glow(0.0)
	_attack = Attack.NONE
	_suppressing = false
	Squad.leave(self)
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


## a body hit is measured. too slow and it bounces, sparks, and tells the bird where you are; hard
## enough and it costs a point of plate, and the last point puts the bird down. an unmeasured hit
## (-1) is a scripted one, and a script that puts a bird down means it: it goes straight through,
## so every probe and tool that clears a level by hand still can.
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


## a bb on the eyes. one precise shot, at any range, with any kit: the skill line, and the reason the
## armour is not simply a wall.
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


## the compound calmed down: the hunt ends properly, effects and arc included, then it walks home.
func stand_down() -> void:
	if _state == State.DOWN:
		return
	if is_hunting():
		_end_hunt()
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


## for the tools: put it straight into an attack so the effects can be photographed. a bird that is
## shooting means a compound that is at least searching, or the calm would end the attack at once.
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
