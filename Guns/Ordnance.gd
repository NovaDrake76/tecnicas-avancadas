class_name Ordnance
extends RefCounted

enum MagType {
	Shotgun,
	Rifle,
	Pistol1911,
	PistolGlock,
}


static func type_name(t: MagType) -> String:
	match t:
		MagType.Shotgun:
			return "Shotgun"
		MagType.Rifle:
			return "Rifle"
		MagType.Pistol1911:
			return "Pistol 1911"
		MagType.PistolGlock:
			return "Pistol Glock"
	return "Unknown"
