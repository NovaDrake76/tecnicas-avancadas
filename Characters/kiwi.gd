class_name Kiwi
extends CharacterBody3D

## a kiwi loafing around its own patch of ground, no navigation and no pursuit.
## it alternates random idle clips with short walks to a random point near where it was placed.

signal downed(kiwi: Kiwi)

enum State { IDLE, WALK, DOWN }

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

@export_group("Clips")
@export var idle_clips: Array[String] = ["IdleA", "IdleB", "IdleC", "IdleD"]
@export var walk_clip := "walk"
## a hit kiwi is out rather than dead, so it lies down.
@export var down_clip := "Sleep"

@export_group("Model")
## the exporter writes vertex colours already gamma encoded, godot assumes linear.
## leave this on or the bird renders about a third too pale.
@export var vertex_colors_are_srgb := true

@export_group("Down")
## a hit kiwi pops and is gone. turn this off to leave it lying in the sleep pose instead.
@export var vanish_on_down := true
@export var despawn_delay := 1.1

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

var _anim: AnimationPlayer
var _clips := {}
var _state := State.IDLE
var _timer := 0.0
var _home := Vector3.ZERO
var _target := Vector3.ZERO


func _ready() -> void:
	add_to_group("kiwi")
	_home = global_position
	model.rotation.y = deg_to_rad(model_yaw_deg)

	_enable_vertex_colors()

	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim != null:
		_resolve_clips()

	health.died.connect(_go_down)
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

	match _state:
		State.DOWN:
			velocity.x = 0.0
			velocity.z = 0.0
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
	var to_target := _target - global_position
	to_target.y = 0.0
	if to_target.length() <= arrive_distance:
		_begin_idle()
		return

	var dir := to_target.normalized()
	## the yaw whose -Z points along dir, turned into gradually so it does not snap.
	var desired := atan2(-dir.x, -dir.z)
	rotation.y = rotate_toward(rotation.y, desired, turn_speed * delta)

	var forward := -global_transform.basis.z
	velocity.x = forward.x * walk_speed
	velocity.z = forward.z * walk_speed

	StepClimb.try_step(self, forward, 4)


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

	## the signal goes out while we are still here, so a listener can read our position.
	downed.emit(self)

	if not vanish_on_down:
		_play(down_clip, 0.15)
		return

	model.visible = false
	set_physics_process(false)
	## the node outlives the burst by a moment, the particles are parented to the world not to us.
	get_tree().create_timer(despawn_delay).timeout.connect(queue_free)


func is_down() -> bool:
	return _state == State.DOWN
