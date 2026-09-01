class_name State
extends Node

## base class for a state in a node based StateMachine.
## host is the entity the machine drives, sm is the machine used to request transitions.

var sm: StateMachine
var host


func enter(_msg: Dictionary = {}) -> void:
	pass


func exit() -> void:
	pass


func physics_update(_delta: float) -> void:
	pass
