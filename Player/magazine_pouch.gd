class_name MagazinePouch
extends Node

## the spare magazines the player carries, any type, each with its own bb mass. the pouch owns the
## count; the weapon asks for one at the end of a reload and the hud shows how many are left.

signal changed
signal added(mag: Magazine)
signal refused(message: String)

## per type. a pouch that never fills makes the boxes in the world worth nothing.
@export var max_per_type := 4

var _mags: Array[Magazine] = []


func _ready() -> void:
	add_to_group("pouch")


func count(mag_type: Ordnance.MagType) -> int:
	var n := 0
	for m in _mags:
		if m.mag_type == mag_type:
			n += 1
	return n


func total() -> int:
	return _mags.size()


## rounds, not magazines: what every shooter puts after the slash. the pouch owns the number because
## the pouch owns the magazines, and a hud that added it up itself would be a second place to get it
## wrong when a half empty spare goes in.
func rounds(mag_type: Ordnance.MagType) -> int:
	var n := 0
	for m in _mags:
		if m.mag_type == mag_type:
			n += m.count
	return n


## a copy goes in, never the pickup's own resource, or two pickups sharing a .tres share a count.
func add(mag: Magazine) -> bool:
	if mag == null:
		return false
	if count(mag.mag_type) >= max_per_type:
		refused.emit("%s pouch full (%d)" % [mag.type_label(), max_per_type])
		return false
	var copy := mag.duplicate() as Magazine
	_mags.append(copy)
	added.emit(copy)
	changed.emit()
	return true


## the fullest spare of that type, removed from the pouch. null when there is none.
func take(mag_type: Ordnance.MagType) -> Magazine:
	var best: Magazine = null
	for m in _mags:
		if m.mag_type == mag_type and (best == null or m.count > best.count):
			best = m
	if best != null:
		_mags.erase(best)
		changed.emit()
	return best


## the armory refills everything from scratch. the field never calls this.
func clear() -> void:
	_mags.clear()
	changed.emit()


func describe(mag_type: Ordnance.MagType) -> String:
	return "x%d" % count(mag_type)
