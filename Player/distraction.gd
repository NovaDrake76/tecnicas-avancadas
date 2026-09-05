class_name Distraction
extends Node

## the player's one non-lethal verb: throw a spent magazine to make a noise somewhere else. until
## this the only thing the player could do to a bird was put it down; now the birds' own hearing is a
## tool. the count is per level, refilled by the armoury with everything else, so it cannot be farmed
## mid-mission. G, because it is free and it is where every shooter puts a thrown item.

signal changed(count: int, max_count: int)
signal thrown(noisemaker: Node3D)

@export var max_count := 3
@export var cooldown := 0.8
@export var throw_speed := 11.0
@export var throw_lift := 2.5

var count := 0
var _cooldown := 0.0
var _player: CharacterBody3D


func _ready() -> void:
	add_to_group("distraction")
	_player = get_parent() as CharacterBody3D
	count = max_count


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("throw"):
		if throw():
			get_viewport().set_input_as_handled()


func refill() -> void:
	count = max_count
	changed.emit(count, max_count)


func can_throw() -> bool:
	return count > 0 and _cooldown <= 0.0 and _player != null


## from the camera, a little up, so it arcs over low cover the way a throw does.
func throw() -> Noisemaker:
	if not can_throw():
		return null
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	count -= 1
	_cooldown = cooldown
	Sfx.play_2d(&"throw")
	var forward := -cam.global_transform.basis.z
	var at := cam.global_position + forward * 0.5 - cam.global_transform.basis.y * 0.15
	var push := forward * throw_speed + Vector3.UP * throw_lift + _player.velocity * 0.5
	var spin := Vector3(randf_range(-6.0, 6.0), randf_range(-3.0, 3.0), randf_range(-6.0, 6.0))
	var mag := _lay(at, push, spin, true)
	## the same magazine, thrown the same way, on every machine: the arc is the tell, and a teammate
	## who could not see it fly would not know where the birds are about to be looking.
	if Net.is_online():
		_net_throw.rpc(at, push, spin)
	changed.emit(count, max_count)
	thrown.emit(mag)
	return mag


@rpc("any_peer", "call_remote", "reliable")
func _net_throw(at: Vector3, push: Vector3, spin: Vector3) -> void:
	_lay(at, push, spin, false)


func _lay(at: Vector3, push: Vector3, spin: Vector3, mine: bool) -> Noisemaker:
	var mag := Noisemaker.new()
	var world := get_tree().current_scene
	if world == null:
		return null
	mag.mine = mine
	world.add_child(mag)
	mag.global_position = at
	mag.linear_velocity = push
	mag.angular_velocity = spin
	return mag
