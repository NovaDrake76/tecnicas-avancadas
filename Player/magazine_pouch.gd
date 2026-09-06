class_name MagazinePouch
extends Node


signal changed
signal added(mag: Magazine)
signal refused(message: String)

## per type.
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


func rounds(mag_type: Ordnance.MagType) -> int:
	var n := 0
	for m in _mags:
		if m.mag_type == mag_type:
			n += m.count
	return n


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


func take(mag_type: Ordnance.MagType) -> Magazine:
	var best: Magazine = null
	for m in _mags:
		if m.mag_type == mag_type and (best == null or m.count > best.count):
			best = m
	if best != null:
		_mags.erase(best)
		changed.emit()
	return best


func clear() -> void:
	_mags.clear()
	changed.emit()


func describe(mag_type: Ordnance.MagType) -> String:
	return "x%d" % count(mag_type)
