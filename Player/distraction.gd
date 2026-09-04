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
	var mag := Noisemaker.new()
	var world := get_tree().current_scene
	world.add_child(mag)
	var forward := -cam.global_transform.basis.z
	mag.global_position = cam.global_position + forward * 0.5 - cam.global_transform.basis.y * 0.15
	mag.linear_velocity = forward * throw_speed + Vector3.UP * throw_lift + _player.velocity * 0.5
	mag.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-3.0, 3.0), randf_range(-6.0, 6.0))
	changed.emit(count, max_count)
	thrown.emit(mag)
	return mag
