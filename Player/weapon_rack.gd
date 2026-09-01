@tool
class_name WeaponRack
extends Node3D

## the weapons the player carries, one active at a time. the active one is the only member of the
## "weapon" group, the only one visible, the only one processing input. everything that used to find
## "the gun" by group keeps working and re-binds on weapon_changed when the player switches.

signal weapon_changed(gun: Gun)

@export var active := 0:
	set(value):
		active = value
		if is_inside_tree():
			_apply()

var _gun: Gun


func _ready() -> void:
	add_to_group("weapon_rack")
	if not Engine.is_editor_hint():
		for g in weapons():
			g.remove_from_group("weapon")
	_apply()


func weapons() -> Array[Gun]:
	var out: Array[Gun] = []
	for child in get_children():
		if child is Gun:
			out.append(child)
	return out


func current() -> Gun:
	return _gun


## the one on show right now, in the editor as much as in the game. the pose tool aims at this.
func shown() -> Gun:
	var guns := weapons()
	if guns.is_empty():
		return null
	return guns[wrapi(active, 0, guns.size())]


func count() -> int:
	return weapons().size()


func select(index: int) -> void:
	var guns := weapons()
	if guns.is_empty():
		return
	index = wrapi(index, 0, guns.size())
	if index == active and _gun != null:
		return
	active = index


func next() -> void:
	select(active + 1)


func previous() -> void:
	select(active - 1)


## which carried weapon takes this magazine type, if any. for the rejection message.
func weapon_for(mag_type: Ordnance.MagType) -> Gun:
	for g in weapons():
		if g.accepted_mag == mag_type:
			return g
	return null


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("weapon_next"):
		next()
	elif event.is_action_pressed("weapon_prev"):
		previous()
	else:
		for i in 4:
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				select(i)
				return


func _apply() -> void:
	var guns := weapons()
	if guns.is_empty():
		_gun = null
		return
	## a local, never the property: writing active here would re-enter its own setter forever.
	var index := wrapi(active, 0, guns.size())
	var editor := Engine.is_editor_hint()
	for i in guns.size():
		var g := guns[i]
		var on := i == index
		g.visible = on
		if editor:
			continue
		## a holstered weapon neither fires nor listens. process_mode off covers input, physics and
		## the auto fire loop in one switch.
		g.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		if on:
			g.add_to_group("weapon")
		else:
			g.remove_from_group("weapon")
	if editor:
		return
	var was := _gun
	_gun = guns[index]
	if was != _gun:
		weapon_changed.emit(_gun)
		_gun.emit_state()
