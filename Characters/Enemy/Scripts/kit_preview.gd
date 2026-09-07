@tool
class_name KitPreview
extends Node3D


enum Kind { LASER, SNIPER, MORTAR, RUSHER }

## which kit to show in the EDITOR; in the game the bird builds its own and this node does nothing.
@export var kind: Kind = Kind.LASER

var _built := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	preview()


func preview() -> void:
	if _built:
		return
	var kiwi := get_parent() as Node3D
	if kiwi == null:
		return
	var skeleton := kiwi.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	_built = true
	match kind:
		Kind.MORTAR:
			MortarKiwi.build_mortar(kiwi, skeleton)
		Kind.RUSHER:
			RusherKiwi.build_kit(kiwi, skeleton)
		Kind.SNIPER:
			KiwiArmour.build_suit(kiwi, skeleton, KiwiArmour.Kind.SNIPER)
		_:
			KiwiArmour.build_suit(kiwi, skeleton, KiwiArmour.Kind.LASER)
