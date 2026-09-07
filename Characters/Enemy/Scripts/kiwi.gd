class_name Kiwi
extends CharacterBody3D


signal downed(kiwi: Kiwi)
signal alerted(kiwi: Kiwi)
signal awareness_changed(kiwi: Kiwi, value: float)
signal tier_changed(kiwi: Kiwi, tier: int)

enum State { IDLE, WALK, DOWN, FLEE, LOOK, HUNT, ATTACK, SUSPECT, RUNNER, HORN, INVESTIGATE, CALL }

enum Alert { UNAWARE, CURIOUS, SUSPICIOUS, HUNTING, CALLING, ENGAGED }

enum Duty { WANDER, FIXED, ROUTE }

@export_group("Duty")
@export var duty: Duty = Duty.WANDER
## the route to walk, when duty is ROUTE.
@export var route: NodePath

@export_group("Wander")
## radius of the patch it stays inside, measured from wherever it was placed.
@export var wander_radius := 4.0
@export var walk_speed := 0.9
@export var turn_speed := 4.0
@export var arrive_distance := 0.3
## seconds spent standing between walks, picked at random inside this range.
@export var idle_time_range := Vector2(2.5, 7.0)
## chance of walking rather than idling again after each idle finishes.
@export_range(0.0, 1.0) var walk_chance := 0.55

@export_group("Hearing")
## a noise never raises the alarm by itself.
@export var hearing := true
@export var look_time := 3.0
## how far off a noise it will settle for.
@export var look_turn_speed := 2.6

@export_group("Investigate")
## a thrown object is an event where a footstep is ambient: the bird WALKS OVER.
@export var stop_short := 1.5
@export var investigate_range := 20.0
@export var investigate_look := 3.0
@export var investigate_speed := 1.6

@export_group("Suspicion")
## clips that hold the head perfectly still.
@export var still_clips: Array[String] = ["IdleA", "IdleC"]
## the body has to come round at least as fast as the head goes back to centre, or the cone would swing off the target w...
@export var suspect_turn_speed := 6.0

@export_group("Fight")
## a bird that has you moves at this: faster than a walk, slower than a sprint, so you cannot walk away from one, only lose it.
@export var hunt_speed := 7.0
## once it knows you are there it picks you out further than a calm bird would.
@export var hunt_sight := 32.0
## how long it searches where it last saw you before it gives up.
@export var search_time := 3.5
@export var stuck_time := 1.0
## an approaching bird stops this far from you and shoots from there.
@export var approach_stop := 6.0

@export_group("Peck")
## inside this a bird stops shooting and goes for you with the beak.
@export var peck_reach := 2.2
@export var peck_damage := 25.0
@export var peck_windup := 1.2
@export var peck_cooldown := 3.0
@export var peck_shove := 6.0

@export_group("Stealth")
## how far a burst carries.
@export var witness_radius := 14.0
@export var flee_speed := 7.5
@export var flee_distance := 18.0
@export var flee_time := 6.0

@export_group("Alarm run")
## the alarm is a bird crossing the map on foot, and the player can shoot it on the way.
@export var lone_runner_time := 8.0
## how long it stands at the horn pulling the lever.
@export var horn_time := 1.2
@export var horn_reach := 1.4
@export var tell_reach := 2.5
## a runner shouts as it goes.
@export var shout_radius := 12.0
@export var shout_interval := 0.6
## a runner that a wall has stopped for this long gives up on the errand and uses the radio instead.
@export var runner_stuck_time := 1.5
## how far it will go for a horn, and for a friend.
@export var horn_search_radius := 70.0
@export var tell_search_radius := 40.0

@export_group("Report")
## a bird that learns something the COMPOUND does not know has to report it, and the report takes time.
@export var call_time := 2.0
## from a garrison that is ALREADY searching the word gets out quicker, which is Wildlands' own rule; under a full alarm...
@export var call_time_hot := 0.8

@export_group("Bodies")
## how long a body has to sit in this bird's cone before it counts as FOUND.
@export var body_notice := 0.6
@export var body_scan_interval := 0.3

@export_group("Clips")
@export var idle_clips: Array[String] = ["IdleA", "IdleB", "IdleC", "IdleD"]
@export var walk_clip := "walk"
@export var run_clip := "run"
## a hit kiwi is out rather than dead, so it lies down.
@export var down_clip := "Sleep"

@export_group("Model")
## the exporter writes vertex colours already gamma encoded, godot assumes linear.
@export var vertex_colors_are_srgb := true

@export_group("Physics")
@export var gravity := 20.0
## the model faces +Z and godot's forward is -Z, so it is turned to match the body.
@export var model_yaw_deg := 180.0

@onready var model: Node3D = $Model
@onready var health: Health = $Health
@onready var vision: VisionCone = $Vision
@onready var voice: KiwiVoice = $Voice
@onready var body: KiwiBody = $Body

const NET_INTERVAL := 0.05

var net_clip := ""
var _shown := ""
var _link: MultiplayerSynchronizer
var _anim: AnimationPlayer
var _clips := {}
var _state := State.IDLE
var _timer := 0.0
var _home := Vector3.ZERO
var _post := Vector3.ZERO
var _target := Vector3.ZERO
var _route: PatrolRoute
var _route_index := 0
var _route_dir := 1
var _detected := false
var _suspect_at := Vector3.ZERO
var _alarm_from := Vector3.ZERO
var _goal_horn: Node3D
var _goal_bird: Kiwi
var _shout_timer := 0.0
var _runner_stuck := 0.0
var _look_at := Vector3.ZERO
var _investigating_walk := false
var _returning := false
var _tier_sent := -1
var _body_seen := 0.0
var _body_scan := 0.0
var _player: Node3D
var _seen := false
var _last_seen := Vector3.ZERO
var _search := 0.0
var _stuck := 0.0
var _fight_time := 0.0
var _role_goal := Vector3.INF
var _role_timer := 0.0
var _role_role := 0
var _role_arrived := false
var _suppressed_until := 0.0
var _pecking := false
var _peck_timer := 0.0
var _peck_ready := 0.0
@onready var blaster: BirdGun = get_node_or_null("Blaster") as BirdGun


func _ready() -> void:
	add_to_group("kiwi")
	_home = global_position
	_post = _home
	_bind_route()
	model.rotation.y = deg_to_rad(model_yaw_deg)

	_enable_vertex_colors()

	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim != null:
		_resolve_clips()

	health.died.connect(_go_down)
	vision.spotted.connect(_on_spotted)
	vision.awareness_changed.connect(_on_awareness_changed)
	_begin_idle()

	if not multiplayer.is_server():
		set_physics_process(false)
	_link = Netlink.sync(self, [".:position", ".:rotation", ".:net_clip"], 1, NET_INTERVAL)


func _enable_vertex_colors() -> void:
	enable_vertex_colors(model, vertex_colors_are_srgb)


static func enable_vertex_colors(root: Node, srgb := true) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(i) as StandardMaterial3D
			var mat: StandardMaterial3D = source.duplicate() if source != null else StandardMaterial3D.new()

			## a textured model already has its colours; multiplying vertex colour in would darken it twice.
			if mat.albedo_texture != null:
				continue

			mat.vertex_color_use_as_albedo = true
			if "vertex_color_is_srgb" in mat:
				mat.vertex_color_is_srgb = srgb
			## the exporter left a grey base factor that would tint every vertex colour down.
			mat.albedo_color = Color.WHITE
			mi.set_surface_override_material(i, mat)


func _resolve_clips() -> void:
	for full in _anim.get_animation_list():
		var short: String = full.get_slice("|", full.get_slice_count("|") - 1)
		_clips[short] = full
		var anim := _anim.get_animation(full)
		if anim != null and short != down_clip:
			anim.loop_mode = Animation.LOOP_LINEAR


func _play(clip: String, blend := 0.3) -> void:
	net_clip = clip
	_show(clip, blend)


func _show(clip: String, blend := 0.3) -> void:
	if _anim == null:
		return
	var full: String = _clips.get(clip, clip)
	if _anim.has_animation(full) and _anim.current_animation != full:
		_anim.play(full, blend)


func _process(_delta: float) -> void:
	if multiplayer.is_server():
		return
	if net_clip != "" and net_clip != _shown:
		_shown = net_clip
		_show(net_clip)


func _physics_process(delta: float) -> void:
	## while the player is hauling it the drag owns where it is; gravity and move_and_slide would fight the pull.
	if body.is_dragged():
		return
	if body.step_thrown(delta):
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if _state != State.DOWN:
		vision.poll(delta)
		_update_suspicion()
		_scan_for_bodies(delta)
	voice.tick(delta, _is_calm())

	if _step_peck(delta):
		_publish_tier()
		move_and_slide()
		return

	match _state:
		State.HUNT, State.ATTACK:
			_step_hunt(delta)
		State.DOWN:
			velocity.x = 0.0
			velocity.z = 0.0
		State.FLEE:
			_step_flee(delta)
		State.RUNNER:
			_step_runner(delta)
		State.HORN:
			velocity.x = move_toward(velocity.x, 0.0, walk_speed * 8.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, walk_speed * 8.0 * delta)
			_timer -= delta
			if _timer <= 0.0:
				_pull_horn()
		State.CALL:
			velocity.x = move_toward(velocity.x, 0.0, walk_speed * 8.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, walk_speed * 8.0 * delta)
			_turn_to(_alarm_from, suspect_turn_speed, delta)
			_timer -= delta
			if _timer <= 0.0:
				_finish_call()
		State.SUSPECT:
			velocity.x = move_toward(velocity.x, 0.0, walk_speed * 8.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, walk_speed * 8.0 * delta)
			if vision.has_last_seen():
				_suspect_at = vision.last_seen
			_turn_to(_suspect_at, suspect_turn_speed, delta)
		State.LOOK:
			velocity.x = move_toward(velocity.x, 0.0, walk_speed * 4.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, walk_speed * 4.0 * delta)
			_turn_to(_target, look_turn_speed, delta)
			_timer -= delta
			if _timer <= 0.0:
				_begin_idle()
		State.INVESTIGATE:
			_step_investigate(delta)
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, walk_speed * 4.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, walk_speed * 4.0 * delta)
			_timer -= delta
			if _timer <= 0.0:
				_decide()
		State.WALK:
			_step_walk(delta)

	_publish_tier()
	move_and_slide()


func _step_walk(delta: float) -> void:
	if not _move_to(_target, _patrol_speed(), delta):
		return
	if duty == Duty.ROUTE and _has_route():
		_post = _target
		_home = _target
	_begin_idle()


func _step_flee(delta: float) -> void:
	_timer -= delta
	if _move_to(_target, flee_speed, delta) or _timer <= 0.0:
		_end_flee()


func _move_to(point: Vector3, speed: float, delta: float) -> bool:
	var to_target := point - global_position
	to_target.y = 0.0
	if to_target.length() <= arrive_distance:
		_path = PackedVector3Array()
		return true

	_turn_to(_next_waypoint(point, delta), turn_speed, delta)

	var forward := -global_transform.basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed

	StepClimb.try_step(self, forward, 4)
	return false


const PATH_REFRESH := 0.5
const WAYPOINT_REACH := 0.6

var _path := PackedVector3Array()
var _path_goal := Vector3.INF
var _path_age := 0.0
var _path_index := 0


func _next_waypoint(point: Vector3, delta: float) -> Vector3:
	_path_age += delta
	if _path.is_empty() or _path_age > PATH_REFRESH or _path_goal.distance_to(point) > 1.0:
		_path_goal = point
		_path_age = 0.0
		_path_index = 0
		_path = PackedVector3Array()
		var map := get_world_3d().navigation_map
		if not NavigationServer3D.map_get_regions(map).is_empty():
			var found := NavigationServer3D.map_get_path(map, global_position, point, true)
			if found.size() >= 2 and found[0].distance_to(global_position) < 2.0:
				_path = found
	if _path.is_empty():
		return point
	while _path_index < _path.size() - 1 \
			and Vector2(_path[_path_index].x - global_position.x, _path[_path_index].z - global_position.z).length() < WAYPOINT_REACH:
		_path_index += 1
	return _path[_path_index]


func path_length() -> int:
	return _path.size()


func _turn_to(point: Vector3, speed: float, delta: float) -> void:
	var flat := point - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	var dir := flat.normalized()
	rotation.y = rotate_toward(rotation.y, atan2(-dir.x, -dir.z), speed * delta)


func _update_suspicion() -> void:
	if _state == State.SUSPECT:
		if not vision.is_noticing():
			_begin_idle()
		return
	if not _can_notice() or not vision.is_noticing():
		return
	_begin_suspect()


func _begin_suspect() -> void:
	_state = State.SUSPECT
	voice.query()
	_suspect_at = vision.last_seen if vision.has_last_seen() \
		else global_position - global_transform.basis.z * 2.0
	if not still_clips.is_empty():
		_play(still_clips[randi() % still_clips.size()])


func hear(at: Vector3, radius: float) -> void:
	if not hearing or not _can_notice() or _state == State.SUSPECT:
		return
	if global_position.distance_to(at) > radius:
		return
	_target = at
	_timer = look_time
	if _state != State.LOOK:
		_state = State.LOOK
		if not idle_clips.is_empty():
			_play(idle_clips[randi() % idle_clips.size()])


func is_listening() -> bool:
	return _state == State.LOOK


func investigate(at: Vector3) -> void:
	if not hearing or not can_be_told():
		return
	var from_post := at - _post
	from_post.y = 0.0
	if from_post.length() > investigate_range:
		at = _post + from_post.normalized() * investigate_range
	var to := at - global_position
	to.y = 0.0
	if to.length() > stop_short:
		at = at - to.normalized() * stop_short
	_target = at
	_look_at = at + to.normalized() * stop_short if to.length() > 0.01 else at
	_timer = investigate_look
	_investigating_walk = true
	_returning = false
	_state = State.INVESTIGATE
	_play(walk_clip)


func _step_investigate(delta: float) -> void:
	if _investigating_walk:
		if _move_to(_target, investigate_speed, delta):
			_investigating_walk = false
			velocity.x = 0.0
			velocity.z = 0.0
			if not idle_clips.is_empty():
				_play(idle_clips[randi() % idle_clips.size()])
		return
	if _returning:
		if _move_to(_post, investigate_speed, delta):
			_returning = false
			_home = _post
			_begin_idle()
		return
	velocity.x = move_toward(velocity.x, 0.0, walk_speed * 4.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, walk_speed * 4.0 * delta)
	_turn_to(_look_at, look_turn_speed, delta)
	_timer -= delta
	if _timer <= 0.0:
		_returning = true
		_play(walk_clip)


func is_investigating() -> bool:
	return _state == State.INVESTIGATE


func is_suspicious() -> bool:
	return _state == State.SUSPECT


func _decide() -> void:
	match duty:
		Duty.FIXED:
			_begin_idle()
		Duty.ROUTE:
			if _has_route():
				_begin_walk()
			else:
				_begin_idle()
		_:
			if randf() < walk_chance:
				_begin_walk()
			else:
				_begin_idle()


func _begin_idle() -> void:
	_state = State.IDLE
	if duty == Duty.ROUTE and _has_route():
		_timer = _route.wait_time()
	else:
		_timer = randf_range(idle_time_range.x, idle_time_range.y)
	if not idle_clips.is_empty():
		_play(idle_clips[randi() % idle_clips.size()])


func _begin_walk() -> void:
	if duty == Duty.ROUTE and _has_route():
		var step: Array = _route.next_index(_route_index, _route_dir)
		_route_index = int(step[0])
		_route_dir = int(step[1])
		_target = _route.point_at(_route_index)
	else:
		var angle := randf() * TAU
		var radius := sqrt(randf()) * wander_radius
		_target = _home + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_state = State.WALK
	_play(walk_clip)


func _bind_route() -> void:
	if route.is_empty():
		return
	_route = get_node_or_null(route) as PatrolRoute
	if _route != null and _route.stops() > 0:
		_route_index = _route.nearest_index(global_position)


func set_patrol(node: PatrolRoute) -> void:
	_route = node
	duty = Duty.ROUTE if node != null else Duty.WANDER
	if node != null and node.stops() > 0:
		_route_index = node.nearest_index(global_position)
		_post = node.point_at(_route_index)
		_home = _post


func _has_route() -> bool:
	return _route != null and is_instance_valid(_route) and _route.stops() > 0


func _patrol_speed() -> float:
	if duty == Duty.ROUTE and _has_route() and _route.speed > 0.0:
		return _route.speed
	return walk_speed


func _on_spotted(target: Node3D) -> void:
	_learn(target.global_position if target != null else global_position, true)


func _on_awareness_changed(value: float) -> void:
	awareness_changed.emit(self, value)


func _on_alarmed(from: Vector3) -> void:
	if Alarm.stage != Alarm.Stage.ALARM and _errand_available() and Alarm.claim_runner(self):
		_begin_alarm_run(from)
		return
	_begin_hunt(from)


func _errand_available() -> bool:
	return _nearest_horn() != null or _nearest_calm_bird() != null


func _begin_alarm_run(from: Vector3) -> void:
	_alarm_from = from
	voice.alarm()
	_play(run_clip, 0.15)
	if Alarm.stage == Alarm.Stage.ALARM:
		_begin_flee(from)
		return
	_goal_horn = _nearest_horn()
	_goal_bird = null if _goal_horn != null else _nearest_calm_bird()
	if _goal_horn == null and _goal_bird == null:
		_flee_target(from)
	_timer = lone_runner_time
	_shout_timer = 0.0
	voice.start_run()
	_runner_stuck = 0.0
	_state = State.RUNNER


func _step_runner(delta: float) -> void:
	voice.run_tick(delta)
	_shout_timer -= delta
	if _shout_timer <= 0.0:
		_shout_timer = shout_interval
		_shout()

	if _goal_horn != null and (not is_instance_valid(_goal_horn) or not _goal_horn.is_usable()):
		_goal_horn = _nearest_horn()
		if _goal_horn == null:
			_goal_bird = _nearest_calm_bird()
			if _goal_bird == null:
				_flee_target(_alarm_from)
	if _goal_bird != null and (not is_instance_valid(_goal_bird) or _goal_bird.is_down() or not _goal_bird.can_be_told()):
		_goal_bird = _nearest_calm_bird()
		if _goal_bird == null:
			_flee_target(_alarm_from)

	var goal := _target
	var reach := arrive_distance
	if _goal_horn != null:
		goal = _goal_horn.global_position
		reach = horn_reach
	elif _goal_bird != null:
		goal = _goal_bird.global_position
		reach = tell_reach

	var flat := goal - global_position
	flat.y = 0.0
	var arrived := flat.length() <= reach
	if not arrived:
		_move_to(goal, flee_speed, delta)
		var moved := get_position_delta().length() / maxf(delta, 0.0001) > 0.3
		_runner_stuck = 0.0 if moved else _runner_stuck + delta
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if _goal_horn != null:
		if arrived:
			_state = State.HORN
			_timer = horn_time
			if not idle_clips.is_empty():
				_play(idle_clips[0], 0.15)
		elif _runner_stuck > runner_stuck_time:
			_use_radio()
		return
	if _goal_bird != null:
		if arrived:
			_goal_bird.told(_alarm_from)
			Alarm.raise_alarm(global_position)
			_after_run()
		elif _runner_stuck > runner_stuck_time:
			_use_radio()
		return
	_timer -= delta
	if _timer <= 0.0:
		Alarm.raise_alarm(global_position)
		_after_run()


func _use_radio() -> void:
	Sfx.play(&"kiwi_radio", global_position + Vector3.UP * 0.4)
	_goal_horn = null
	_goal_bird = null
	_flee_target(_alarm_from)
	_timer = minf(_timer, lone_runner_time * 0.5)
	_runner_stuck = 0.0


func _pull_horn() -> void:
	if _goal_horn != null and is_instance_valid(_goal_horn) and _goal_horn.is_usable():
		_goal_horn.raise(self)
	else:
		Alarm.raise_alarm(global_position)
	_after_run()


func _after_run() -> void:
	_goal_horn = null
	_goal_bird = null
	Alarm.release_runner(self)
	_home = global_position
	if Alarm.is_hot():
		_begin_hunt(_alarm_from)
		return
	vision.rearm()
	_begin_idle()


func _shout() -> void:
	for node in get_tree().get_nodes_in_group("kiwi"):
		var other := node as Kiwi
		if other == null or other == self or other.is_down() or not other.can_be_told():
			continue
		if other.global_position.distance_to(global_position) <= shout_radius:
			other.told(_alarm_from)


func _nearest_horn() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("alarm_horn"):
		var horn := node as Node3D
		if horn == null or not horn.has_method("is_usable") or not horn.is_usable():
			continue
		var d := horn.global_position.distance_to(global_position)
		if d < best_d and d <= horn_search_radius:
			best_d = d
			best = horn
	return best


func _nearest_calm_bird() -> Kiwi:
	var best: Kiwi = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("kiwi"):
		var other := node as Kiwi
		if other == null or other == self or other.is_down() or not other.can_be_told():
			continue
		var d := other.global_position.distance_to(global_position)
		if d < best_d and d <= tell_search_radius:
			best_d = d
			best = other
	return best


func can_be_told() -> bool:
	return _can_notice() or _state == State.SUSPECT


func told(at: Vector3) -> void:
	if not can_be_told():
		return
	_learn(at, false)


func saw(at: Vector3) -> void:
	_learn(at, true)


func _begin_hunt(toward: Vector3) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = Player.nearest(get_tree(), global_position)
	if _player == null:
		_begin_idle()
		return
	_last_seen = toward
	_search = search_time
	_stuck = 0.0
	_fight_time = 0.0
	_role_goal = Vector3.INF
	_state = State.HUNT
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
	if not _seen and Alarm.stage != Alarm.Stage.ALARM and _search <= 0.0:
		_end_hunt()
		return

	## a bird fighting under a mere SEARCH gets on its radio after a while: the full alarm's third source.
	_fight_time += delta
	if Alarm.stage == Alarm.Stage.SEARCHING and _fight_time > lone_runner_time:
		_fight_time = 0.0
		Sfx.play(&"kiwi_radio", global_position + Vector3.UP * 0.4)
		Alarm.raise_alarm(global_position)

	if blaster != null:
		blaster.tick(delta, _player, _seen and dist <= blaster.reach and not is_suppressed())

	if _seen:
		_step_role(delta)
		return
	_role_goal = Vector3.INF
	var arrived := _move_to(_last_seen, hunt_speed, delta)
	var moved := get_position_delta().length() / maxf(delta, 0.0001) > 0.3
	_stuck = 0.0 if moved or arrived else _stuck + delta
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
		_role_goal = _role_target(job)
	var dist := global_position.distance_to(_player.global_position)
	var advancing := job == Squad.Role.APPROACH and Squad.player_quiet() > Squad.QUIET_TO_ADVANCE and not is_suppressed()
	if advancing and dist > approach_stop:
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


func _role_target(job: int) -> Vector3:
	match job:
		Squad.Role.FLANK:
			var goal := Squad.flank_point(self, _player.global_position)
			return goal if goal != Vector3.INF else Squad.tangent_point(self, _player.global_position)
		Squad.Role.APPROACH:
			return Vector3.INF
	var cover := Squad.claim_cover(self, _player.global_position, false)
	if cover == Vector3.INF and Squad.is_rattled():
		cover = Squad.tangent_point(self, _player.global_position)
	return cover


func _end_hunt() -> void:
	Squad.leave(self)
	vision.rearm()
	_home = global_position
	_seen = false
	awareness_changed.emit(self, 0.0)
	_begin_idle()


func is_hunting() -> bool:
	return _state == State.HUNT or _state == State.ATTACK


func can_see_target() -> bool:
	return _seen


func hunt_target() -> Node3D:
	return _player


func _step_peck(delta: float) -> bool:
	_peck_ready = maxf(0.0, _peck_ready - delta)
	if _pecking:
		velocity.x = move_toward(velocity.x, 0.0, hunt_speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, hunt_speed * 8.0 * delta)
		var prey := Player.nearest(get_tree(), global_position)
		if prey != null:
			_turn_to(prey.global_position, turn_speed * 3.0, delta)
		_peck_timer -= delta
		if _peck_timer <= 0.0:
			_pecking = false
			_peck_ready = peck_cooldown
			if prey != null and multiplayer.is_server() and prey.has_method("take_peck") \
					and global_position.distance_to(prey.global_position) <= peck_reach * 1.25:
				var dir := prey.global_position - global_position
				dir.y = 0.0
				prey.take_peck(peck_damage, global_position, dir.normalized() * peck_shove + Vector3.UP * 2.5)
				Sfx.play(&"takedown", prey.global_position + Vector3.UP * 0.8)
		return true
	if not is_hunting() or _peck_ready > 0.0 or not multiplayer.is_server():
		return false
	var near := Player.nearest(get_tree(), global_position)
	if near == null or (near.has_method("is_alive") and not near.is_alive()):
		return false
	if global_position.distance_to(near.global_position) > peck_reach:
		return false
	_pecking = true
	_peck_timer = peck_windup
	_interrupt_for_peck()
	voice.alarm()
	Sfx.play(&"takedown_swing", global_position + Vector3.UP * 0.4, 0.0, 1.0, true)
	if not idle_clips.is_empty():
		_play(idle_clips[0], 0.1)
	return true


func _interrupt_for_peck() -> void:
	pass


func is_pecking() -> bool:
	return _pecking


func suppress(seconds: float) -> void:
	_suppressed_until = maxf(_suppressed_until, _now() + seconds)


func is_suppressed() -> bool:
	return _suppressed_until > _now()


func _flee_target(from: Vector3) -> void:
	var dir := global_position - from
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = -global_transform.basis.z
	_target = global_position + dir.normalized() * flee_distance


func _begin_flee(away_from: Vector3) -> void:
	_flee_target(away_from)
	_timer = flee_time
	_state = State.FLEE
	_play(run_clip, 0.15)


func _end_flee() -> void:
	vision.rearm()
	_home = global_position
	_begin_idle()


func _alert_witnesses() -> void:
	var at := global_position + Vector3.UP * 0.3
	for node in get_tree().get_nodes_in_group("kiwi"):
		var other := node as Kiwi
		if other == null or other == self or other.is_down():
			continue
		other.witness(at)


func witness(at: Vector3) -> void:
	if _state == State.DOWN or not vision.sees_point(at, witness_radius):
		return
	_learn(at, true)


func _learn(from: Vector3, needs_report: bool) -> void:
	if _state == State.DOWN:
		return
	## a bird already on the radio or in the fight knows: its own cone filling late must not restart the call mid-burst.
	if _state == State.CALL or is_hunting():
		return
	if not _detected:
		_detected = true
		alerted.emit(self)
	if needs_report and call_seconds() > 0.0:
		_begin_call(from)
		return
	_on_alarmed(from)


func _begin_call(from: Vector3) -> void:
	_alarm_from = from
	_timer = call_seconds()
	_state = State.CALL
	voice.alarm()
	Sfx.play(&"kiwi_radio", global_position + Vector3.UP * 0.3)
	if not still_clips.is_empty():
		_play(still_clips[randi() % still_clips.size()])


func call_seconds() -> float:
	match Alarm.stage:
		Alarm.Stage.ALARM:
			return 0.0
		Alarm.Stage.SEARCHING:
			return call_time_hot
	return call_time


func is_calling() -> bool:
	return _state == State.CALL


func _finish_call() -> void:
	Alarm.raise_search(_alarm_from)
	_on_alarmed(_alarm_from)


func _scan_for_bodies(delta: float) -> void:
	if not _can_notice():
		_body_seen = 0.0
		return
	_body_scan -= delta
	if _body_scan > 0.0:
		return
	_body_scan = body_scan_interval
	var found: Kiwi = null
	for node in get_tree().get_nodes_in_group("body"):
		var other := node as Kiwi
		if other == null or other == self or other.is_found():
			continue
		var at := other.global_position + Vector3.UP * 0.25
		if vision.sees_point(at, witness_radius):
			found = other
			break
	if found == null:
		_body_seen = 0.0
		return
	_body_seen += body_scan_interval
	if _body_seen < body_notice:
		return
	_body_seen = 0.0
	found.mark_found()
	Alarm.note_body_found()
	_learn(found.global_position, true)


func mark_found() -> void:
	body.mark_found()


func is_found() -> bool:
	return body.is_found()


@rpc("any_peer", "call_local", "reliable")
func toss(launch: Vector3, spin: float) -> void:
	body.toss(launch, spin)


func is_thrown() -> bool:
	return body.is_thrown()


@rpc("any_peer", "call_local", "reliable")
func net_carried(by: int) -> void:
	body.set_dragged(by > 0)
	if _link != null:
		_link.set_multiplayer_authority(by if by > 0 else 1)


func set_dragged(value: bool) -> void:
	body.set_dragged(value)


func is_dragged() -> bool:
	return body.is_dragged()


func has_contact() -> bool:
	return _seen


func alert_tier() -> int:
	match _state:
		State.LOOK, State.INVESTIGATE:
			return Alert.CURIOUS
		State.SUSPECT:
			return Alert.SUSPICIOUS
		State.CALL:
			return Alert.CALLING
		State.ATTACK:
			return Alert.ENGAGED
		State.HUNT:
			return Alert.ENGAGED if has_contact() else Alert.HUNTING
		State.RUNNER, State.HORN, State.FLEE:
			return Alert.HUNTING
	return Alert.UNAWARE


func _publish_tier() -> void:
	var tier := alert_tier()
	if tier == _tier_sent:
		return
	_tier_sent = tier
	tier_changed.emit(self, tier)


func was_detected() -> bool:
	return _detected


func stand_down() -> void:
	if _state == State.DOWN:
		return
	if is_hunting():
		Squad.leave(self)
	Alarm.release_runner(self)
	_seen = false
	_pecking = false
	vision.rearm()
	_detected = false
	_body_seen = 0.0
	if duty == Duty.ROUTE and _has_route():
		_route_index = _route.nearest_index(global_position)
		_post = _route.point_at(_route_index)
	_home = _post
	_target = _post
	_state = State.WALK
	_play(walk_clip)
	if randf() < 0.35:
		voice.settle()


func take_bb_hit(damage := 1.0, at := Vector3.INF, _energy := -1.0) -> void:
	if _state == State.DOWN:
		return
	Sfx.play(&"bb_body", at if at.is_finite() else global_position + Vector3.UP * 0.3)
	if not multiplayer.is_server():
		_ask_hit.rpc_id(1, damage, at if at.is_finite() else global_position, _energy)
		return
	health.take_damage(damage)


@rpc("any_peer", "call_remote", "reliable")
func _ask_hit(damage: float, at: Vector3, energy: float) -> void:
	if not multiplayer.is_server():
		return
	take_bb_hit(damage, at, energy)


func _go_down() -> void:
	if _state == State.DOWN:
		return
	if multiplayer.is_server():
		_net_down.rpc()
	else:
		_fall()


@rpc("authority", "call_local", "reliable")
func _net_down() -> void:
	_fall()


func _fall() -> void:
	if _state == State.DOWN:
		return
	if is_hunting():
		Squad.leave(self, true)
	_pecking = false
	_state = State.DOWN
	velocity = Vector3.ZERO
	Alarm.release_runner(self)
	## nothing may hit us twice, and the body stops blocking anything it was blocking.
	collision_layer = 0
	var at := global_position + Vector3.UP * 0.3
	voice.dying()
	if multiplayer.is_server():
		_alert_witnesses()
		## emitted while we are still here, so a listener can read our position.
		downed.emit(self)
	if not body.vanish_on_down:
		_play(down_clip, 0.15)
	body.collapse(at)
	if not body.vanish_on_down:
		_publish_tier()


func speak(band: Vector2, db: float, clip_after := 0.0) -> void:
	voice.speak(band, db, clip_after)


var _marked_until := -1.0

@rpc("any_peer", "call_local", "reliable")
func net_mark(seconds: float) -> void:
	_marked_until = maxf(_marked_until, _now() + maxf(seconds, 0.0))


func is_marked() -> bool:
	return _marked_until > _now() and not is_down()


func mark_left() -> float:
	return maxf(_marked_until - _now(), 0.0) if is_marked() else 0.0


func clear_mark() -> void:
	_marked_until = -1.0


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func kind_name() -> String:
	return "SENTRY"


func is_down() -> bool:
	return _state == State.DOWN


func _is_calm() -> bool:
	return _can_notice() or _state == State.SUSPECT


func _can_notice() -> bool:
	return _state == State.IDLE or _state == State.WALK or _state == State.LOOK or _state == State.INVESTIGATE


func is_fleeing() -> bool:
	return _state == State.FLEE or _state == State.RUNNER


func is_runner() -> bool:
	return _state == State.RUNNER or _state == State.HORN


func runner_goal() -> Vector3:
	if _goal_horn != null and is_instance_valid(_goal_horn):
		return _goal_horn.global_position
	if _goal_bird != null and is_instance_valid(_goal_bird):
		return _goal_bird.global_position
	return _target
