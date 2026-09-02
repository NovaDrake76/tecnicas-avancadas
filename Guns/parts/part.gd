class_name Part
extends Resource

## one row of the armory catalogue: a spring, a motor, a lot of bbs, a weapon or a spare magazine.
## every row is bought and owned the same way, only what it does to a weapon differs, so one type with
## a kind beats five that would each need the same price and title.

enum Kind { SPRING, MOTOR, BB_LOT, WEAPON, MAGAZINE }

@export var id: String = ""
@export var title: String = ""
@export var kind: Kind = Kind.SPRING
@export var price: int = 0
## weapon models this part fits. empty means every weapon.
@export var fits: Array[String] = []

@export_group("Spring")
@export var spring_k: float = 300.0
@export var spring_x: float = 0.1

@export_group("Motor")
@export var rpm: float = 9000.0

@export_group("BBs")
@export var bb_mass_kg: float = 0.0002

@export_group("Weapon or magazine")
@export var weapon_model: String = ""
@export var mag_type: Ordnance.MagType = Ordnance.MagType.Rifle


func fits_weapon(model: String) -> bool:
	return fits.is_empty() or model in fits


## the spring's whole energy, the brief's physical model. the gun does the same sum; this is for the
## catalogue to show a number before anything is bought.
func energy() -> float:
	return 0.5 * spring_k * spring_x * spring_x


func detail() -> String:
	match kind:
		Kind.SPRING:
			return "k %.0f N/m  x %.0f mm  %.2f J" % [spring_k, spring_x * 1000.0, energy()]
		Kind.MOTOR:
			return "%.0f RPM" % rpm
		Kind.BB_LOT:
			return "%.2f g" % (bb_mass_kg * 1000.0)
		Kind.WEAPON:
			return weapon_model
		Kind.MAGAZINE:
			return "%s magazine" % Ordnance.type_name(mag_type)
	return ""


## puts the part on a weapon. the weapon keeps its own fields, so every formula it already has
## recomputes on the next shot without knowing a catalogue exists.
func apply(gun: Gun) -> void:
	match kind:
		Kind.SPRING:
			gun.spring_constant = spring_k
			gun.spring_compression = spring_x
		Kind.MOTOR:
			gun.motor_rpm = rpm
		Kind.BB_LOT:
			if gun.magazine != null:
				gun.magazine.bb_mass_kg = bb_mass_kg
