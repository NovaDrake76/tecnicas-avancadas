class_name Footsteps
extends SfxBank


@export var stride := 2.2
## a shorter, quieter step.
@export var crouch_stride := 1.5
@export var crouch_db := -9.0
## a crawl.
@export var crawl_stride := 1.0
@export var crawl_db := -15.0
@export var run_db := 2.0
@export var land_db := 3.0
@export var min_speed := 0.8

@export_group("How far it carries")
## a kiwi that hears this turns to face it.
@export var crawl_noise := 3.0
@export var crouch_noise := 5.0
@export var walk_noise := 14.0
@export var run_noise := 26.0
@export var land_noise := 22.0

var _body: CharacterBody3D
var _travelled := 0.0
var _airborne := false


func _ready() -> void:
	super()
	add_to_group("footsteps")
	_body = get_parent() as CharacterBody3D


func play_one(extra_db := 0.0) -> void:
	Sfx.play_2d("step_" + String(surface()), extra_db)


func surface() -> StringName:
	if _body == null or not is_inside_tree():
		return &"grass"
	var from := _body.global_position + Vector3.UP * 0.3
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.4, 1)
	query.exclude = [_body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return &"grass"
	return Sfx.surface_of(hit["collider"])


func advance(distance: float, crouched: bool, prone := false) -> bool:
	_travelled += distance
	var step := stride
	if prone:
		step = crawl_stride
	elif crouched:
		step = crouch_stride
	if _travelled < step:
		return false
	_travelled -= step
	return true


func carry(radius: float) -> void:
	if multiplayer.is_server():
		_heard(global_position, radius)
	else:
		_heard.rpc_id(1, global_position, radius)


@rpc("any_peer", "call_remote", "reliable")
func _heard(at: Vector3, radius: float) -> void:
	if not multiplayer.is_server():
		return
	for node in get_tree().get_nodes_in_group("kiwi"):
		var listener := node as Kiwi
		if listener != null:
			listener.hear(at, radius)


func _physics_process(delta: float) -> void:
	if _body == null:
		return

	if not _body.is_on_floor():
		_airborne = true
		return

	if _airborne:
		_airborne = false
		_travelled = 0.0
		play_one(land_db)
		carry(land_noise)
		return

	var speed := Vector2(_body.velocity.x, _body.velocity.z).length()
	if speed < min_speed:
		_travelled = 0.0
		return

	var crouched: bool = _body.has_method("is_crouching") and _body.is_crouching()
	var prone: bool = _body.has_method("is_prone") and _body.is_prone()
	if advance(speed * delta, crouched, prone):
		var loud := 0.0
		var reach := walk_noise
		if prone:
			loud = crawl_db
			reach = crawl_noise
		elif crouched:
			loud = crouch_db
			reach = crouch_noise
		elif _body.has_method("is_running") and _body.is_running():
			loud = run_db
			reach = run_noise
		play_one(loud)
		carry(reach)
