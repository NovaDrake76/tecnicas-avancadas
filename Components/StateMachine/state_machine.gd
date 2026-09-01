class_name StateMachine
extends Node

## reusable node based finite state machine, each child extending State is a state keyed by node name.
## host driven, the owner calls setup once then physics_tick from its own _physics_process.

signal transitioned(to: StringName)

@export var initial_state_name: StringName = &"Grounded"

var current: State
var host

var _states: Dictionary = {}


func setup(host_ref) -> void:
	host = host_ref
	for child in get_children():
		if child is State:
			_states[child.name] = child
			child.sm = self
			child.host = host_ref
	current = _states.get(initial_state_name)
	if current:
		current.enter()


func physics_tick(delta: float) -> void:
	if current:
		current.physics_update(delta)


func change_to(state_name: StringName, msg: Dictionary = {}) -> void:
	if not _states.has(state_name) or _states[state_name] == current:
		return
	if current:
		current.exit()
	current = _states[state_name]
	current.enter(msg)
	transitioned.emit(state_name)


## re-enters a state even when it is already current, for an event that must supersede what is running.
## change_to refuses a self transition, which is right for the ordinary case and wrong for this one.
func restart_to(state_name: StringName, msg: Dictionary = {}) -> void:
	if not _states.has(state_name):
		return
	if _states[state_name] != current:
		change_to(state_name, msg)
		return
	current.exit()
	current.enter(msg)
	transitioned.emit(state_name)
