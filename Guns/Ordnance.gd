class_name Ordnance
extends RefCounted

enum MagType {
	Shotgun,
	Rifle,
	PistolHeavy,
	PistolMachine,
	## at the END on purpose: a magazine .tres stores the type as a NUMBER, so inserting earlier would turn every saved shotgun magazine into a rifle one.
	Marksman,
}


static func type_name(t: MagType) -> String:
	match t:
		MagType.Shotgun:
			return "Shotgun"
		MagType.Rifle:
			return "Rifle"
		MagType.PistolHeavy:
			return "Heavy Pistol"
		MagType.PistolMachine:
			return "Machine Pistol"
		MagType.Marksman:
			return "Marksman"
	return "Unknown"
