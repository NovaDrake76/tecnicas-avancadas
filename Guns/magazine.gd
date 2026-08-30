class_name Magazine
extends Resource

@export var mag_type: Ordnance.MagType = Ordnance.MagType.Rifle

@export_range(1, 200, 1, "or_greater") var capacity: int = 30:
	set(value):
		capacity = maxi(1, value)
		count = mini(count, capacity)

@export_range(0, 200, 1, "or_greater") var count: int = 30:
	set(value):
		count = clampi(value, 0, capacity)

const PLAUSIBLE_MIN_KG := 0.00005
const PLAUSIBLE_MAX_KG := 0.001

@export_range(0.00001, 0.001, 0.00001, "or_greater") var bb_mass_kg: float = 0.00025


func mass_grams() -> float:
	return bb_mass_kg * 1000.0


func is_plausible() -> bool:
	return bb_mass_kg >= PLAUSIBLE_MIN_KG and bb_mass_kg <= PLAUSIBLE_MAX_KG


func is_empty() -> bool:
	return count <= 0


func consume(amount: int = 1) -> bool:
	if count < amount:
		return false
	count -= amount
	return true


func refill() -> void:
	count = capacity


func type_label() -> String:
	return Ordnance.type_name(mag_type)


func describe() -> String:
	return "%s  %d/%d  %.2f g" % [type_label(), count, capacity, mass_grams()]
