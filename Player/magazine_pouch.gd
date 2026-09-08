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


func loaded(mag_type: Ordnance.MagType) -> int:
	var n := 0
	for m in _mags:
		if m.mag_type == mag_type and m.count > 0:
			n += 1
	return n


func magazines(mag_type: Ordnance.MagType) -> Array[Magazine]:
	var out: Array[Magazine] = []
	for m in _mags:
		if m.mag_type == mag_type:
			out.append(m)
	return out


func add(mag: Magazine) -> bool:
	if mag == null:
		return false
	if count(mag.mag_type) >= max_per_type:
		var spent := _first_empty(mag.mag_type)
		if spent == null:
			refused.emit("%s pouch full (%d)" % [mag.type_label(), max_per_type])
			return false
		_mags.erase(spent)
	var copy := mag.duplicate() as Magazine
	_mags.append(copy)
	added.emit(copy)
	changed.emit()
	return true


func take(mag_type: Ordnance.MagType) -> Magazine:
	for m in _mags:
		if m.mag_type == mag_type and m.count > 0:
			_mags.erase(m)
			changed.emit()
			return m
	return null


func stow(mag: Magazine) -> void:
	if mag == null:
		return
	_mags.append(mag)
	changed.emit()


func _first_empty(mag_type: Ordnance.MagType) -> Magazine:
	for m in _mags:
		if m.mag_type == mag_type and m.count <= 0:
			return m
	return null


func clear() -> void:
	_mags.clear()
	changed.emit()


func describe(mag_type: Ordnance.MagType) -> String:
	return "x%d" % loaded(mag_type)
