class_name Interactor
extends Node

## sits on the player, casts a short ray out of the live camera each tick.
## emits focus on edges only so the hud is driven by events instead of polling.

signal focus_changed(text: String, action: StringName, target: Node)
signal focus_lost

@export var reach := 3.0

## world plus interactable, the world half is what makes walls occlude the ray.
const INTERACT_MASK := 0b10000001

var _player: CollisionObject3D
var _current: Interactable
var _last_sig := ""


func _ready() -> void:
	add_to_group("interactor")
	_player = owner as CollisionObject3D


func _physics_process(_delta: float) -> void:
	## a focused thing can free itself under the crosshair, and a freed reference compares equal to null.
	## _last_sig is the honest record of "we believe something is focused", so it separates the two cases.
	if not _last_sig.is_empty() and not is_instance_valid(_current):
		_current = null
		_last_sig = ""
		focus_lost.emit()
		return

	var next := _focus_candidate()
	if next == _current:
		if _current != null and _current.prompt_text() != _last_sig:
			_last_sig = _current.prompt_text()
			_emit_focus()
		return

	_current = next
	if _current == null:
		_last_sig = ""
		focus_lost.emit()
		return
	_last_sig = _current.prompt_text()
	_emit_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if is_instance_valid(_current) and _current.enabled():
			_current.interact(_player)
			get_viewport().set_input_as_handled()


func _emit_focus() -> void:
	focus_changed.emit(_current.prompt_text(), _current.prompt_action(), _current.get_parent())


## suppressed while the cursor is free, which covers every menu at once.
func _focus_candidate() -> Interactable:
	if DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE) \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return null

	var cam := get_viewport().get_camera_3d()
	if cam == null or _player == null:
		return null

	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * reach
	var query := PhysicsRayQueryParameters3D.create(from, to, INTERACT_MASK)
	query.collide_with_areas = true
	query.exclude = [_player.get_rid()]

	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var found := _find_interactable(hit.collider as Node)
	return found if found != null and found.enabled() else null


## climb a few ancestors from the hit body and return the first Interactable child found.
func _find_interactable(hit_node: Node) -> Interactable:
	var current := hit_node
	for _i in 3:
		if current == null:
			break
		for child in current.get_children():
			if child is Interactable:
				return child as Interactable
		current = current.get_parent()
	return null
