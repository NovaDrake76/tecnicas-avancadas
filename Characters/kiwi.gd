class_name Kiwi
extends CharacterBody3D

## a kiwi loafing around its own patch of ground, no navigation and no pursuit.
## it alternates random idle clips with short walks to a random point near where it was placed.

signal downed(kiwi: Kiwi)
signal alerted(kiwi: Kiwi)
signal awareness_changed(kiwi: Kiwi, value: float)
## what this ONE bird knows, for the hud's ring. the compound's own stage is Alarm's business.
signal tier_changed(kiwi: Kiwi, tier: int)

## HUNT and ATTACK belong to the laser kiwi; a plain kiwi never enters them, but the states live in
## one enum so every guard in here can name them. RUNNER is a bird carrying the alarm to the horn or
## to a friend, HORN is the moment it spends pulling the lever, FLEE is what is left once the whole
## compound already knows.
enum State { IDLE, WALK, DOWN, FLEE, LOOK, HUNT, ATTACK, SUSPECT, RUNNER, HORN, INVESTIGATE, CALL }

## how much this bird knows, which is a different question from what it is doing. it is READ OFF
## the state rather than kept beside it, so the two can never drift apart. the hud draws it, and
## the ladder is Wildlands': nothing, heard something, half saw you, knows there is an intruder
## but not where, is telling everyone, has you.
enum Alert { UNAWARE, CURIOUS, SUSPICIOUS, HUNTING, CALLING, ENGAGED }

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
## a noise never raises the alarm by itself. it turns the bird to face the sound, and the eyes
## take it from there. that keeps the alarm on exactly one sense and a missed bb still silent.
@export var hearing := true
@export var look_time := 3.0
## how far off a noise it will settle for. it turns, it does not walk over to investigate.
@export var look_turn_speed := 2.6

@export_group("Investigate")
## a thrown object is an event where a footstep is ambient: the bird WALKS OVER. it stops this short
## of the spot, never strays further than this from its post, looks about for this long, and goes home.
@export var stop_short := 1.5
@export var investigate_range := 20.0
@export var investigate_look := 3.0
@export var investigate_speed := 1.6

@export_group("Suspicion")
## clips that hold the head perfectly still. measured with probe_headsweep: IdleA and IdleC sweep
## the cone 0.0 degrees, IdleB 55.7 and IdleD 167.8.
@export var still_clips: Array[String] = ["IdleA", "IdleC"]
## the body has to come round at least as fast as the head goes back to centre, or the cone would
## swing off the target while the body was still catching up. the head returns over the clip blend,
## about 320 deg/s; 6 rad/s is 344.
@export var suspect_turn_speed := 6.0

@export_group("Stealth")
## how far a burst carries. a kiwi with a clear line to one going down inside this raises the alarm.
@export var witness_radius := 14.0
@export var flee_speed := 3.4
@export var flee_distance := 18.0
@export var flee_time := 6.0

@export_group("Alarm run")
## the alarm is a bird crossing the map on foot, and the player can shoot it on the way. it runs to
## the nearest horn, failing that to the nearest calm bird, failing that away, and a bird alone in a
## field still has a radio: after this long it raises the alarm anyway.
@export var lone_runner_time := 8.0
## how long it stands at the horn pulling the lever. the last window the player gets.
@export var horn_time := 1.2
@export var horn_reach := 1.4
@export var tell_reach := 2.5
## a runner shouts as it goes. every calm bird inside this hears about you and runs too, so the
## alarm is contagious along the runner's path and killing it early is worth more than killing it late.
@export var shout_radius := 12.0
@export var shout_interval := 0.6
## a runner that a wall has stopped for this long gives up on the errand and uses the radio instead.
@export var runner_stuck_time := 1.5
## how far it will go for a horn, and for a friend. a bird does not cross the whole map to tell
## someone; past these it is on its own and the radio is the answer.
@export var horn_search_radius := 70.0
@export var tell_search_radius := 40.0

@export_group("Report")
## a bird that learns something the COMPOUND does not know has to report it, and the report takes
## time. put it down inside this window and the garrison never hears: that is the answer to a
## compound that knew where you were the instant one bird's bar filled, even if you dropped that
## bird a fifth of a second later. it is MGSV's reflex window paid for with a real shot.
@export var call_time := 2.0
## from a garrison that is ALREADY searching the word gets out quicker, which is Wildlands' own
## rule; under a full alarm there is nothing left to report and the call is skipped outright.
@export var call_time_hot := 0.8

@export_group("Bodies")
## how long a body has to sit in this bird's cone before it counts as FOUND. a glance while
## turning is not a discovery, and without this a body anywhere in the open is found instantly.
@export var body_notice := 0.6
@export var body_scan_interval := 0.3

@export_group("Voice")
## one recording, resampled. pitch_scale moves speed and pitch together, which is what turns a
## single clip into a flock instead of a row of clones.
@export var voice: AudioStream
## found on its own once godot has imported it, so a missing file never breaks the scene.
@export var voice_path := "res://Sounds/kiwi/voice.wav"
@export var call_interval := Vector2(6.0, 17.0)
## the three bands do not overlap, so you can tell what happened without looking.
@export var idle_pitch := Vector2(0.94, 1.06)
@export var alert_pitch := Vector2(1.08, 1.16)
@export var down_pitch := Vector2(0.84, 0.92)
@export var idle_db := -14.0
@export var alert_db := -5.0
@export var down_db := -10.0
## the short rising call of a bird that has half noticed something: the calm band, cut short.
@export var query_db := -12.0
@export var query_clip := 0.42
## the settling call some birds give when the compound stands down.
@export var calm_db := -12.0
## a runner keeps calling as it goes, so the thing carrying the alarm can be followed by ear.
@export var runner_call_interval := 1.8

@export_group("Clips")
@export var idle_clips: Array[String] = ["IdleA", "IdleB", "IdleC", "IdleD"]
@export var walk_clip := "walk"
@export var run_clip := "run"
## a hit kiwi is out rather than dead, so it lies down.
@export var down_clip := "Sleep"

@export_group("Model")
## the exporter writes vertex colours already gamma encoded, godot assumes linear.
## leave this on or the bird renders about a third too pale.
@export var vertex_colors_are_srgb := true

@export_group("Down")
## OFF by default: a downed kiwi stays lying where it fell, and that is what makes where you drop
## one a decision. a body another bird walks past is found, and a body dragged behind a crate is
## not. turn this on to go back to the bird popping and leaving nothing to find.
@export var vanish_on_down := false
## long enough for the slowest, lowest call to finish before the node carrying it is freed.
@export var despawn_delay := 1.6

@export_group("Down burst")
@export var burst_light := Color(0.55, 0.4, 0.2)
@export var burst_dark := Color(0.22, 0.15, 0.09)
@export var burst_count := 34
@export var burst_speed := 3.8

@export_group("Physics")
@export var gravity := 20.0
## the model faces +Z and godot's forward is -Z, so it is turned to match the body.
@export var model_yaw_deg := 180.0

@onready var model: Node3D = $Model
@onready var health: Health = $Health
@onready var vision: VisionCone = $Vision
@onready var throat: AudioStreamPlayer3D = $Voice

var _anim: AnimationPlayer
var _clips := {}
var _state := State.IDLE
var _timer := 0.0
var _home := Vector3.ZERO
## where it was placed. _home drifts with a flee; this is the post it walks back to when the
## compound stands down.
var _post := Vector3.ZERO
var _target := Vector3.ZERO
var _detected := false
var _call_timer := 0.0
var _runner_call := 0.0
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
## this body has already been discovered by somebody, so it is spent: it cannot raise the
## compound a second time however many birds walk past it afterwards.
var _found := false
var _dragged := false
var _handle: Area3D


func _ready() -> void:
	add_to_group("kiwi")
	_home = global_position
	_post = _home
	model.rotation.y = deg_to_rad(model_yaw_deg)

	_enable_vertex_colors()

	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim != null:
		_resolve_clips()

	if voice == null and ResourceLoader.exists(voice_path):
		voice = load(voice_path) as AudioStream
	throat.stream = voice
	## staggered, or every bird on the map calls on the very same tick.
	_call_timer = randf_range(0.5, call_interval.y)

	health.died.connect(_go_down)
	vision.spotted.connect(_on_spotted)
	vision.awareness_changed.connect(_on_awareness_changed)
	_begin_idle()


func _enable_vertex_colors() -> void:
	enable_vertex_colors(model, vertex_colors_are_srgb)


## the model carries its colours as vertex data and ships no texture at all.
## StandardMaterial3D discards vertex colour unless this flag is on, which is why it rendered white.
## static, because anything that shows this model raw needs it: the loading screen learned that the
## hard way and rendered a white bird.
static func enable_vertex_colors(root: Node, srgb := true) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(i) as StandardMaterial3D
			var mat: StandardMaterial3D = source.duplicate() if source != null else StandardMaterial3D.new()

			## a textured model already has its colours, multiplying vertex colour in would darken it twice.
			if mat.albedo_texture != null:
				continue

			mat.vertex_color_use_as_albedo = true
			if "vertex_color_is_srgb" in mat:
				mat.vertex_color_is_srgb = srgb
			## the exporter also left a grey base factor that would tint every vertex colour down.
			mat.albedo_color = Color.WHITE
			mi.set_surface_override_material(i, mat)


## the exporter names every clip with its full rig path, so match on the part after the last separator.
## resolving by suffix also survives someone renaming the clips cleanly later.
func _resolve_clips() -> void:
	for full in _anim.get_animation_list():
		var short: String = full.get_slice("|", full.get_slice_count("|") - 1)
		_clips[short] = full
		var anim := _anim.get_animation(full)
		if anim != null and short != down_clip:
			anim.loop_mode = Animation.LOOP_LINEAR


func _play(clip: String, blend := 0.3) -> void:
	if _anim == null:
		return
	var full: String = _clips.get(clip, clip)
	if _anim.has_animation(full) and _anim.current_animation != full:
		_anim.play(full, blend)


func _physics_process(delta: float) -> void:
	## while the player is hauling it, the drag owns where it is: gravity and move_and_slide would
	## both fight the pull and the body would judder along the ground behind them.
	if _dragged:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if _state != State.DOWN:
		vision.poll(delta)
		_update_suspicion()
		_scan_for_bodies(delta)
	## a bird already shouting the alarm, or hunting, does not stop to chit chat.
	if _is_calm():
		## clamped rather than only counted down, so shortening the interval in the inspector
		## takes effect on the wait already running instead of on the one after it.
		_call_timer = minf(_call_timer, call_interval.y) - delta
		if _call_timer <= 0.0:
			_call_timer = randf_range(call_interval.x, call_interval.y)
			speak(idle_pitch, idle_db)

	match _state:
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
			## while it can still see, this follows; once it cannot, it holds the last place it did.
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
	if _move_to(_target, walk_speed, delta):
		_begin_idle()


func _step_flee(delta: float) -> void:
	_timer -= delta
	if _move_to(_target, flee_speed, delta) or _timer <= 0.0:
		_end_flee()


## returns true once it has arrived, so each state decides for itself what that means. the bird
## walks the navigation mesh when the level has one (main bakes it on load), so a runner inside a
## compound goes round the wall instead of into it; with no mesh under it, in the sky probes and the
## safe house, it takes the straight line it always took.
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


## seconds between path refreshes while the goal stays put. a moving goal refreshes when it has moved.
const PATH_REFRESH := 0.5
const WAYPOINT_REACH := 0.6

var _path := PackedVector3Array()
var _path_goal := Vector3.INF
var _path_age := 0.0
var _path_index := 0


## the next corner of the path to `point`, or `point` itself when there is no mesh worth following.
## a path is trusted only if it starts near the bird: a bird parked in the sky over a level would
## otherwise be handed the ground's path and walk the level's detours two hundred metres up.
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


## the yaw whose -Z points at the spot, turned into gradually so it never snaps.
func _turn_to(point: Vector3, speed: float, delta: float) -> void:
	var flat := point - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	var dir := flat.normalized()
	rotation.y = rotate_toward(rotation.y, atan2(-dir.x, -dir.z), speed * delta)


## the cone rides the HEAD, so a bird that has half noticed something must stop swinging it. this is
## the 'what is that?' state: it stops where it is, holds its head still and squares its body up to
## the spot. without it a bird could notice you and then have its own idle clip turn its head away
## and cancel the detection, which reads as the bird being broken rather than as the player being
## lucky. it costs the player the accident that used to save them: cover, crouch and distance are
## the ways out now, which are the three the design already promised.
func _update_suspicion() -> void:
	if _state == State.SUSPECT:
		if not vision.is_noticing():
			_begin_idle()
		return
	if not _can_notice() or not vision.is_noticing():
		return
	_begin_suspect()


## the still clip stops the head, and turning the BODY to where the eyes last had it is what keeps
## the cone there while the head blends back to centre. it is also the tell the player can read: a
## bird that has stopped and squared up to you has noticed something.
func _begin_suspect() -> void:
	_state = State.SUSPECT
	speak(idle_pitch, query_db, query_clip)
	_suspect_at = vision.last_seen if vision.has_last_seen() \
		else global_position - global_transform.basis.z * 2.0
	if not still_clips.is_empty():
		_play(still_clips[randi() % still_clips.size()])


## something made a noise nearby. loud things carry further, which is the whole of the mechanic.
## a bird that is already peering at something is not turned by a footstep: the eyes are the sense
## that raises the alarm, so nothing may pull them off a target they have already half caught.
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


## something was THROWN nearby. unlike a footstep this is an event, and the bird walks over to look:
## to a point stop_short of it, no further than investigate_range from its post, then it looks about
## and walks home. it raises no alarm and touches no alarm stage, ever; but its eyes stay open on the
## way, so a player in its path is caught, and that is the risk that keeps the tool from being free.
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
		## back to the post at the same pace it left it: a sentry hurrying back, not strolling
		_returning = true
		_play(walk_clip)


func is_investigating() -> bool:
	return _state == State.INVESTIGATE


func is_suspicious() -> bool:
	return _state == State.SUSPECT


func _decide() -> void:
	if randf() < walk_chance:
		_begin_walk()
	else:
		_begin_idle()


func _begin_idle() -> void:
	_state = State.IDLE
	_timer = randf_range(idle_time_range.x, idle_time_range.y)
	if not idle_clips.is_empty():
		_play(idle_clips[randi() % idle_clips.size()])


func _begin_walk() -> void:
	## a uniform point in the disc, the square root is what stops them all clustering at the centre.
	var angle := randf() * TAU
	var radius := sqrt(randf()) * wander_radius
	_target = _home + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_state = State.WALK
	_play(walk_clip)


## the alarm goes up once per bird. after that it is already blown, so fleeing again costs nothing.
func _on_spotted(target: Node3D) -> void:
	_learn(target.global_position if target != null else global_position, true)


func _on_awareness_changed(value: float) -> void:
	awareness_changed.emit(self, value)


## what this bird does about trouble at a point: the player it saw, the neighbour it saw drop, the
## spot a runner shouted about. a plain kiwi carries the alarm; the laser kiwi overrides this to hunt.
func _on_alarmed(from: Vector3) -> void:
	_begin_alarm_run(from)


## the alarm travels on foot. the bird tells the compound to start looking, then runs to raise the
## full alarm: at the nearest horn, or to the nearest calm bird, or if it is alone, away, with the
## radio after a while. the player can stop every one of those by putting it down first, which is
## the whole point: the alarm is a physical thing crossing the map at 3.4 m/s. once the compound is
## already under full alarm there is nothing left to raise, so it simply runs for it.
func _begin_alarm_run(from: Vector3) -> void:
	_alarm_from = from
	## the compound was told by the CALL that got us here, or by whoever shouted at us. nothing is
	## raised on this line: a bird that starts running is not a bird that has reported.
	speak(alert_pitch, alert_db)
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
	_runner_call = runner_call_interval
	_runner_stuck = 0.0
	_state = State.RUNNER


func _step_runner(delta: float) -> void:
	_runner_call -= delta
	if _runner_call <= 0.0:
		_runner_call = runner_call_interval
		speak(alert_pitch, alert_db)
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
	## alone: run, and use the radio when the time is up
	_timer -= delta
	if _timer <= 0.0:
		Alarm.raise_alarm(global_position)
		_after_run()


## a runner that cannot get where it was going still gets the word out, just later.
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


## the errand is done: back to watching from wherever it ended up, still knowing it was seen.
func _after_run() -> void:
	_goal_horn = null
	_goal_bird = null
	vision.rearm()
	_home = global_position
	_begin_idle()


## every calm bird inside the shout hears about you and runs too.
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


## a bird that could still be told something: not down, not already carrying or answering the alarm.
func can_be_told() -> bool:
	return _can_notice() or _state == State.SUSPECT


## another bird told this one where the trouble is. it counts as being alerted and it answers the
## same way it would have answered seeing you, so the alarm spreads from bird to bird on foot.
func told(at: Vector3) -> void:
	if not can_be_told():
		return
	## no call: the bird that shouted is the one already reporting, and two birds reporting the
	## same sighting would make killing the messenger pointless the moment there were two of them.
	_learn(at, false)


## this bird found out FIRST HAND: it saw the player, a bb bounced off its own plate, it walked
## into a body. first hand means it is the one who has to get on the radio, and it can be put
## down before it finishes. told() is the second-hand half of the same pair.
func saw(at: Vector3) -> void:
	_learn(at, true)


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


## still alarmed, but back to watching, so walking into its face again sends it running again.
func _end_flee() -> void:
	vision.rearm()
	_home = global_position
	_begin_idle()


## an airsoft hit is quiet, so only a bird actually looking that way knows its neighbour dropped.
## turning up behind them is what makes a silent clear possible.
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


## something this bird now knows. needs_report says whether the COMPOUND knows it too: seeing the
## player, watching a neighbour drop and finding a body all have to go over the radio first, and
## the bird can be put down before it finishes. being shouted at does not, because the bird that
## shouted is the one on the radio. this is the whole of the two-layer design: what one bird knows
## and what the garrison knows are different facts, and the second one has to travel.
func _learn(from: Vector3, needs_report: bool) -> void:
	if _state == State.DOWN:
		return
	if not _detected:
		_detected = true
		alerted.emit(self)
	if needs_report and call_seconds() > 0.0:
		_begin_call(from)
		return
	_on_alarmed(from)


## it stops, squares up to the trouble and gets on the radio. it is standing still and calling,
## which is the loudest and most obvious thing a bird ever does, because the player has to be able
## to see the window in order to use it.
func _begin_call(from: Vector3) -> void:
	_alarm_from = from
	_timer = call_seconds()
	_state = State.CALL
	speak(alert_pitch, alert_db)
	Sfx.play(&"kiwi_radio", global_position + Vector3.UP * 0.3)
	if not still_clips.is_empty():
		_play(still_clips[randi() % still_clips.size()])


## the escalation clock shortens with the stage the garrison is already in.
func call_seconds() -> float:
	match Alarm.stage:
		Alarm.Stage.ALARM:
			return 0.0
		Alarm.Stage.SEARCHING:
			return call_time_hot
	return call_time


func is_calling() -> bool:
	return _state == State.CALL


## the word is out. only here does the compound learn anything, and only from a bird that lived
## long enough to finish saying it.
func _finish_call() -> void:
	Alarm.raise_search(_alarm_from)
	_on_alarmed(_alarm_from)


## a body lying in the open is a fact, not a glimpse, so it skips the awareness bar entirely. the
## compound is then told about the BODY and not about the player: the garrison converges on where
## the shooting was, which is where the player no longer is, and that gap is the reward for having
## moved. the sight test is the same ray as everything else, so a crate hides a body for free and
## the level's own cover is the whole vocabulary.
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
	_learn(found.global_position, true)


## spent: no number of birds walking past can raise the compound on the same body twice.
func mark_found() -> void:
	_found = true


func is_found() -> bool:
	return _found


## the player has it by the feet. the drag owns the position while this is true.
func set_dragged(value: bool) -> void:
	_dragged = value


func is_dragged() -> bool:
	return _dragged


## a plain bird never hunts, so it never has the player in front of it in the sense the tier
## means. the laser kiwi answers for itself.
func has_contact() -> bool:
	return false


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


## an int compared once a tick, so the signal cannot get out of step with the state it reads.
func _publish_tier() -> void:
	var tier := alert_tier()
	if tier == _tier_sent:
		return
	_tier_sent = tier
	tier_changed.emit(self, tier)


func was_detected() -> bool:
	return _detected


## the compound has calmed down and this bird forgets with it: eyes rearmed, the alarm it raised
## forgotten, and a walk back to its post. Alarm calls this on every bird at once, which is what
## makes being seen a setback the player can recover from rather than a mode the level is stuck in.
func stand_down() -> void:
	if _state == State.DOWN:
		return
	vision.rearm()
	_detected = false
	_body_seen = 0.0
	_home = _post
	_target = _post
	_state = State.WALK
	_play(walk_clip)
	## some of them, not all: thirty birds settling on the same tick is one noise
	if randf() < 0.35:
		speak(Vector2(0.9, 0.97), calm_db)


## called by a BB that lands on us, an airsoft hit puts a target out rather than killing it. the
## energy is how hard it arrived; a plain kiwi does not care, one bb is one bb. -1 means nobody
## measured, which is what a scripted hit says.
func take_bb_hit(damage := 1.0, at := Vector3.INF, _energy := -1.0) -> void:
	if _state == State.DOWN:
		return
	Sfx.play(&"bb_body", at if at.is_finite() else global_position + Vector3.UP * 0.3)
	health.take_damage(damage)


func _go_down() -> void:
	if _state == State.DOWN:
		return
	_state = State.DOWN
	velocity = Vector3.ZERO
	## nothing may hit us twice, and the body stops blocking anything it was blocking.
	collision_layer = 0

	var world := get_tree().current_scene
	var at := global_position + Vector3.UP * 0.3
	BurstFx.spawn(world, at, burst_light, burst_count, burst_speed)
	BurstFx.spawn(world, at, burst_dark, int(burst_count * 0.6), burst_speed * 0.8)

	speak(down_pitch, down_db)
	_alert_witnesses()

	## the signal goes out while we are still here, so a listener can read our position.
	downed.emit(self)

	if not vanish_on_down:
		_play(down_clip, 0.15)
		_become_body()
		_publish_tier()
		return

	model.visible = false
	Sfx.play(&"kiwi_poof", at)
	set_physics_process(false)
	## the node outlives the burst by a moment, the particles are parented to the world not to us.
	get_tree().create_timer(despawn_delay).timeout.connect(queue_free)


## what is left on the ground: something a patrol can find, and something the player can haul out
## of a patrol's way. the handle is an AREA on the interactable layer, not a body, so a bb passes
## straight through it and a corpse can never come back as a second hit marker.
func _become_body() -> void:
	add_to_group("body")
	_handle = Area3D.new()
	_handle.collision_layer = 128
	_handle.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.75, 0.5, 0.75)
	shape.shape = box
	shape.position = Vector3(0.0, 0.25, 0.0)
	_handle.add_child(shape)
	add_child(_handle)
	var grab := Interactable.new()
	grab.prompt = "Drag the body"
	add_child(grab)
	grab.interacted.connect(_on_grab_pressed)


func _on_grab_pressed(_by: Node) -> void:
	for node in get_tree().get_nodes_in_group("body_drag"):
		var drag := node as BodyDrag
		if drag != null:
			drag.grab(self)
			return


## the same clip every time, pulled to a different pitch so thirty birds are not one bird.
func speak(band: Vector2, db: float, clip_after := 0.0) -> void:
	if throat == null or throat.stream == null:
		return
	throat.pitch_scale = randf_range(band.x, band.y)
	throat.volume_db = db
	throat.play()
	## a call cut short is a different word from the same throat: the query of a bird that has
	## stopped to look, against the full call of one that is sure
	if clip_after > 0.0:
		var started := throat.get_playback_position()
		get_tree().create_timer(clip_after).timeout.connect(func() -> void:
			if is_instance_valid(throat) and throat.playing and throat.get_playback_position() >= started + clip_after * 0.5:
				throat.stop())


func is_down() -> bool:
	return _state == State.DOWN


## not alarmed and not down. a bird peering at something is still one of these: it keeps its calm
## call, because the three voice bands are calm, alarm and going down, and suspicion is none of them.
func _is_calm() -> bool:
	return _can_notice() or _state == State.SUSPECT


## the states a bird can be pulled out of by its own eyes. it is already looking from SUSPECT, and
## everything else has either raised the alarm or is out of the fight. a bird walking to a noise
## is included on purpose: it can still catch you on the way, which is what makes the thrown
## magazine a gamble rather than a way to make birds blind.
func _can_notice() -> bool:
	return _state == State.IDLE or _state == State.WALK or _state == State.LOOK or _state == State.INVESTIGATE


## running, whether away from you or towards the horn. either way it is not standing there.
func is_fleeing() -> bool:
	return _state == State.FLEE or _state == State.RUNNER


func is_runner() -> bool:
	return _state == State.RUNNER or _state == State.HORN


## where a runner is headed, for the probes: the horn, the bird, or the point it is fleeing to.
func runner_goal() -> Vector3:
	if _goal_horn != null and is_instance_valid(_goal_horn):
		return _goal_horn.global_position
	if _goal_bird != null and is_instance_valid(_goal_bird):
		return _goal_bird.global_position
	return _target
