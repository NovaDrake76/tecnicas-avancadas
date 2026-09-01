class_name Interactable
extends Node

## a reusable look at it and press a key target.
## drop it under any body the interactor's ray can hit, it exposes a verb and a press callback.

signal interacted(by: Node)

@export var prompt: String = "Take"
@export var action: StringName = &"interact"
@export var enabled_default := true

var _enabled := true


func _ready() -> void:
	_enabled = enabled_default
	add_to_group("interactable")


func enabled() -> bool:
	return _enabled


func set_enabled(value: bool) -> void:
	_enabled = value


func prompt_text() -> String:
	return prompt


func prompt_action() -> StringName:
	return action


func interact(by: Node) -> void:
	if not _enabled:
		return
	interacted.emit(by)
