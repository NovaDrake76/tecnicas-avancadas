class_name CreatureSteps
extends Node3D

## footsteps for anything that walks and is not the player: spaced by ground covered, so they keep
## pace at any speed, and played through the event table so the mix owns their level. a patrol you
## cannot see yet is one you can hear coming, which is the promise a stealth game makes with its
## ears. nothing here feeds the AI.

@export var event := &"kiwi_step"
@export var stride := 0.55
@export var run_stride := 0.8
@export var run_speed := 2.5
@export var min_speed := 0.3

var _body: CharacterBody3D
var _travelled := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D


func advance(distance: float, running: bool) -> bool:
	_travelled += distance
	var step := run_stride if running else stride
	if _travelled < step:
		return false
	_travelled -= step
	return true


func _physics_process(delta: float) -> void:
	if _body == null or not _body.is_on_floor():
		return
	var speed := Vector2(_body.velocity.x, _body.velocity.z).length()
	if speed < min_speed:
		_travelled = 0.0
		return
	var running := speed >= run_speed
	if advance(speed * delta, running):
		Sfx.play(event, global_position, 2.0 if running else 0.0)
