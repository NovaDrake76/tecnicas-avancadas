@tool
class_name WeaponRack
extends Node3D


signal weapon_changed(gun: Gun)

@export var active := 0:
	set(value):
		active = value
		if is_inside_tree():
			_apply()

var _gun: Gun
var _carried: Array[int] = []


func _ready() -> void:
	add_to_group("weapon_rack")
	if not Engine.is_editor_hint():
		for g in weapons():
			g.remove_from_group("weapon")
	_apply()


func all_weapons() -> Array[Gun]:
	var out: Array[Gun] = []
	for child in get_children():
		if child is Gun:
			out.append(child)
	return out


func weapons() -> Array[Gun]:
	var all := all_weapons()
	if _carried.is_empty() or Engine.is_editor_hint():
		return all
	var out: Array[Gun] = []
	for i in _carried:
		if i >= 0 and i < all.size():
			out.append(all[i])
	return out


func set_carried(indices: Array[int]) -> void:
	_carried = indices.duplicate()
	active = 0
	if not is_inside_tree():
		return
	_apply()
	if _gun != null:
		weapon_changed.emit(_gun)
		_gun.emit_state()


func carried() -> Array[int]:
	return _carried.duplicate()


func current() -> Gun:
	return _gun


func shown() -> Gun:
	var guns := weapons()
	if guns.is_empty():
		return null
	return guns[wrapi(active, 0, guns.size())]


func count() -> int:
	return weapons().size()


func display(index: int) -> void:
	var guns := all_weapons()
	for i in guns.size():
		guns[i].visible = i == index
		if is_inside_tree():
			for pass_node in get_tree().get_nodes_in_group("viewmodel_pass"):
				(pass_node as ViewmodelPass).hand_back(guns[i])


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
		for i in all_weapons().size():
			if InputMap.has_action("weapon_%d" % (i + 1)) and event.is_action_pressed("weapon_%d" % (i + 1)):
				if i < weapons().size():
					select(i)
				return


func _apply() -> void:
	var guns := weapons()
	if guns.is_empty():
		_gun = null
		return
	var index := wrapi(active, 0, guns.size())
	var editor := Engine.is_editor_hint()
	var chosen := guns[index]
	for g in all_weapons():
		var on := g == chosen
		g.visible = on
		if editor:
			continue
		var pass_node := get_tree().get_first_node_in_group("viewmodel_pass") as ViewmodelPass
		if pass_node != null:
			if on:
				pass_node.take_over(g)
			else:
				pass_node.hand_back(g)
		## process_mode off covers input, physics and the auto-fire loop in one switch.
		g.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		if on:
			g.add_to_group("weapon")
		else:
			g.remove_from_group("weapon")
	if editor:
		return
	var was := _gun
	_gun = chosen
	if was != null and was != _gun and is_instance_valid(was):
		was.cancel_reload()
	if was != _gun:
		if was != null:
			Sfx.play_2d(&"weapon_draw")
		weapon_changed.emit(_gun)
		_gun.emit_state()
