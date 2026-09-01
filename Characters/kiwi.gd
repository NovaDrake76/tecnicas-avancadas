class_name Kiwi
extends CharacterBody3D

## a kiwi loafing around its own patch of ground, no navigation and no pursuit.
## it alternates random idle clips with short walks to a random point near where it was placed.

signal downed(kiwi: Kiwi)
signal alerted(kiwi: Kiwi)
signal awareness_changed(kiwi: Kiwi, value: float)

enum State { IDLE, WALK, DOWN, FLEE, LOOK }

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

@export_group("Stealth")
## how far a burst carries. a kiwi with a clear line to one going down inside this raises the alarm.
@export var witness_radius := 14.0
@export var flee_speed := 3.4
@export var flee_distance := 18.0
@export var flee_time := 6.0

@export_group("Voice")
## one recording, resampled. pitch_scale moves speed and pitch together, which is what turns a
## single clip into a flock instead of a row of clones.
@export var voice: AudioStream
## found on its own once godot has imported it, so a missing file never breaks the scene.
@export var voice_path := "res://Sounds/kiwi.wav"
@export var call_interval := Vector2(6.0, 17.0)
## the three bands do not overlap, so you can tell what happened without looking.
@export var idle_pitch := Vector2(0.94, 1.06)
@export var alert_pitch := Vector2(1.08, 1.16)
@export var down_pitch := Vector2(0.84, 0.92)
@export var idle_db := -8.0
@export var alert_db := 1.0

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
## a hit kiwi pops and is gone. turn this off to leave it lying in the sleep pose instead.
@export var vanish_on_down := true
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
var _target := Vector3.ZERO
var _detected := false
var _call_timer := 0.0


func _ready() -> void:
	add_to_group("kiwi")
	_home = global_position
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


## the model carries its colours as vertex data and ships no texture at all.
## StandardMaterial3D discards vertex colour unless this flag is on, which is why it rendered white.
func _enable_vertex_colors() -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
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
				mat.vertex_color_is_srgb = vertex_colors_are_srgb
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
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if _state != State.DOWN:
		vision.poll(delta)
	## a bird already shouting the alarm does not stop to chit chat.
	if _state != State.DOWN and _state != State.FLEE:
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
		State.LOOK:
			velocity.x = move_toward(velocity.x, 0.0, walk_speed * 4.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, walk_speed * 4.0 * delta)
			_turn_to(_target, look_turn_speed, delta)
			_timer -= delta
			if _timer <= 0.0:
				_begin_idle()
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, walk_speed * 4.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, walk_speed * 4.0 * delta)
			_timer -= delta
			if _timer <= 0.0:
				_decide()
		State.WALK:
			_step_walk(delta)

	move_and_slide()


func _step_walk(delta: float) -> void:
	if _move_to(_target, walk_speed, delta):
		_begin_idle()


func _step_flee(delta: float) -> void:
	_timer -= delta
	if _move_to(_target, flee_speed, delta) or _timer <= 0.0:
		_end_flee()


## returns true once it has arrived, so each state decides for itself what that means.
func _move_to(point: Vector3, speed: float, delta: float) -> bool:
	var to_target := point - global_position
	to_target.y = 0.0
	if to_target.length() <= arrive_distance:
		return true

	_turn_to(point, turn_speed, delta)

	var forward := -global_transform.basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed

	StepClimb.try_step(self, forward, 4)
	return false


## the yaw whose -Z points at the spot, turned into gradually so it never snaps.
func _turn_to(point: Vector3, speed: float, delta: float) -> void:
	var flat := point - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	var dir := flat.normalized()
	rotation.y = rotate_toward(rotation.y, atan2(-dir.x, -dir.z), speed * delta)


## something made a noise nearby. loud things carry further, which is the whole of the mechanic.
func hear(at: Vector3, radius: float) -> void:
	if not hearing or _state == State.DOWN or _state == State.FLEE:
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
	if _state == State.DOWN:
		return
	if not _detected:
		_detected = true
		alerted.emit(self)
	_begin_flee(target.global_position if target != null else global_position)


func _on_awareness_changed(value: float) -> void:
	awareness_changed.emit(self, value)


func _begin_flee(away_from: Vector3) -> void:
	var dir := global_position - away_from
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = -global_transform.basis.z
	_target = global_position + dir.normalized() * flee_distance
	_timer = flee_time
	_state = State.FLEE
	_play(run_clip, 0.15)
	speak(alert_pitch, alert_db)


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
	if not _detected:
		_detected = true
		alerted.emit(self)
	_begin_flee(at)


func was_detected() -> bool:
	return _detected


## called by a BB that lands on us, an airsoft hit puts a target out rather than killing it.
func take_bb_hit(damage := 1.0, _at := Vector3.INF) -> void:
	if _state == State.DOWN:
		return
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

	speak(down_pitch, idle_db)
	_alert_witnesses()

	## the signal goes out while we are still here, so a listener can read our position.
	downed.emit(self)

	if not vanish_on_down:
		_play(down_clip, 0.15)
		return

	model.visible = false
	set_physics_process(false)
	## the node outlives the burst by a moment, the particles are parented to the world not to us.
	get_tree().create_timer(despawn_delay).timeout.connect(queue_free)


## the same clip every time, pulled to a different pitch so thirty birds are not one bird.
func speak(band: Vector2, db: float) -> void:
	if throat == null or throat.stream == null:
		return
	throat.pitch_scale = randf_range(band.x, band.y)
	throat.volume_db = db
	throat.play()


func is_down() -> bool:
	return _state == State.DOWN


func is_fleeing() -> bool:
	return _state == State.FLEE
