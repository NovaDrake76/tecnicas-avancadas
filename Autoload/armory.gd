extends Node


signal changed
signal refused(message: String)
signal bought(part: Part)
signal part_installed(part: Part)
signal deploy_requested(briefed: bool)

const SLOTS := 2
const START_POINTS := 500
const MAG_PATHS := {
	Ordnance.MagType.Shotgun: "res://Guns/resources/mag_shotgun.tres",
	Ordnance.MagType.Rifle: "res://Guns/resources/mag_rifle.tres",
	Ordnance.MagType.PistolHeavy: "res://Guns/resources/mag_heavy.tres",
	Ordnance.MagType.PistolMachine: "res://Guns/resources/mag_machine.tres",
	Ordnance.MagType.Marksman: "res://Guns/resources/mag_marksman.tres",
}

const CATALOG := [
	{"id": "spring_m100", "kind": Part.Kind.SPRING, "title": "M100 spring", "price": 0, "k": 300.0, "x": 0.1, "fits": ["KESTREL", "SHRIKE"]},
	{"id": "spring_m110", "kind": Part.Kind.SPRING, "title": "M110 spring", "price": 300, "k": 350.0, "x": 0.1, "fits": ["KESTREL", "SHRIKE"]},
	{"id": "spring_m120", "kind": Part.Kind.SPRING, "title": "M120 spring", "price": 550, "k": 400.0, "x": 0.1, "fits": ["KESTREL", "SHRIKE"]},
	{"id": "spring_p200", "kind": Part.Kind.SPRING, "title": "Stock recoil spring", "price": 0, "k": 200.0, "x": 0.095, "fits": ["HARRIER"]},
	{"id": "spring_p180", "kind": Part.Kind.SPRING, "title": "Stock recoil spring", "price": 0, "k": 180.0, "x": 0.095, "fits": ["MERLIN"]},
	{"id": "spring_p230", "kind": Part.Kind.SPRING, "title": "Heavy recoil spring", "price": 250, "k": 230.0, "x": 0.095, "fits": ["HARRIER", "MERLIN"]},
	{"id": "spring_m150", "kind": Part.Kind.SPRING, "title": "M150 spring", "price": 0, "k": 450.0, "x": 0.1, "fits": ["OSPREY"]},
	{"id": "spring_m170", "kind": Part.Kind.SPRING, "title": "M170 spring", "price": 500, "k": 520.0, "x": 0.1, "fits": ["OSPREY"]},
	{"id": "motor_std", "kind": Part.Kind.MOTOR, "title": "Stock motor", "price": 0, "rpm": 9000.0, "fits": ["KESTREL"]},
	{"id": "motor_torque", "kind": Part.Kind.MOTOR, "title": "High torque motor", "price": 350, "rpm": 12000.0, "fits": ["KESTREL"]},
	{"id": "motor_speed", "kind": Part.Kind.MOTOR, "title": "High speed motor", "price": 650, "rpm": 15000.0, "fits": ["KESTREL"]},
	{"id": "bb_020", "kind": Part.Kind.BB_LOT, "title": "0.20 g BBs", "price": 0, "mass": 0.00020},
	{"id": "bb_025", "kind": Part.Kind.BB_LOT, "title": "0.25 g BBs", "price": 150, "mass": 0.00025},
	{"id": "bb_028", "kind": Part.Kind.BB_LOT, "title": "0.28 g BBs", "price": 250, "mass": 0.00028},
	{"id": "bb_032", "kind": Part.Kind.BB_LOT, "title": "0.32 g BBs", "price": 400, "mass": 0.00032},
	{"id": "weapon_kestrel", "kind": Part.Kind.WEAPON, "title": "KESTREL", "price": 0, "model": "KESTREL"},
	{"id": "weapon_harrier", "kind": Part.Kind.WEAPON, "title": "HARRIER", "price": 0, "model": "HARRIER"},
	{"id": "weapon_shrike", "kind": Part.Kind.WEAPON, "title": "SHRIKE", "price": 900, "model": "SHRIKE"},
	{"id": "weapon_merlin", "kind": Part.Kind.WEAPON, "title": "MERLIN", "price": 700, "model": "MERLIN"},
	{"id": "weapon_osprey", "kind": Part.Kind.WEAPON, "title": "OSPREY", "price": 1500, "model": "OSPREY"},
	{"id": "mag_shotgun", "kind": Part.Kind.MAGAZINE, "title": "Shotgun shells", "price": 200, "mag_type": Ordnance.MagType.Shotgun},
	{"id": "mag_rifle", "kind": Part.Kind.MAGAZINE, "title": "Rifle magazine", "price": 200, "mag_type": Ordnance.MagType.Rifle},
	{"id": "mag_heavy", "kind": Part.Kind.MAGAZINE, "title": "Heavy pistol magazine", "price": 150, "mag_type": Ordnance.MagType.PistolHeavy},
	{"id": "mag_machine", "kind": Part.Kind.MAGAZINE, "title": "Machine pistol magazine", "price": 150, "mag_type": Ordnance.MagType.PistolMachine},
	{"id": "mag_marksman", "kind": Part.Kind.MAGAZINE, "title": "Marksman magazine", "price": 250, "mag_type": Ordnance.MagType.Marksman},
	{"id": "util_frag", "kind": Part.Kind.UTILITY, "title": "Frag grenade", "price": 250, "utility_id": "frag"},
]

const STARTER_OWNED := ["spring_m100", "spring_p200", "spring_p180", "motor_std", "spring_m150", "bb_020", "weapon_kestrel", "weapon_harrier"]
const STARTER_MAGAZINES := {Ordnance.MagType.Rifle: 2, Ordnance.MagType.PistolHeavy: 2}
const STARTER_LOADOUT := ["KESTREL", "HARRIER"]

var points := 0
var owned := {}
var installed := {}
var bb_lot := {}
var magazines := {}
var utilities := {}
var loadout: Array[String] = []

var _parts := {}


func _ready() -> void:
	for row in CATALOG:
		var p := Part.new()
		p.id = row["id"]
		p.kind = row["kind"]
		p.title = row["title"]
		p.price = row["price"]
		var f: Array[String] = []
		for m in row.get("fits", []):
			f.append(m)
		p.fits = f
		p.spring_k = row.get("k", 300.0)
		p.spring_x = row.get("x", 0.1)
		p.rpm = row.get("rpm", 9000.0)
		p.bb_mass_kg = row.get("mass", 0.0002)
		p.weapon_model = row.get("model", "")
		p.mag_type = row.get("mag_type", Ordnance.MagType.Rifle)
		p.utility_id = row.get("utility_id", "")
		_parts[p.id] = p
	reset()
	Run.level_cleared.connect(_on_level_cleared)


func reset() -> void:
	points = START_POINTS
	owned.clear()
	for id in STARTER_OWNED:
		owned[id] = true
	installed = {
		"KESTREL": {"spring": "spring_m100", "motor": "motor_std"},
		"SHRIKE": {"spring": "spring_m100", "motor": ""},
		"HARRIER": {"spring": "spring_p200", "motor": ""},
		"MERLIN": {"spring": "spring_p180", "motor": ""},
		"OSPREY": {"spring": "spring_m150", "motor": ""},
	}
	bb_lot = {}
	for t in MAG_PATHS:
		bb_lot[t] = "bb_020"
	magazines = STARTER_MAGAZINES.duplicate()
	utilities.clear()
	loadout.assign(STARTER_LOADOUT)
	changed.emit()


func part(id: String) -> Part:
	return _parts.get(id) as Part


func parts_of(kind: Part.Kind, model := "") -> Array[Part]:
	var out: Array[Part] = []
	for id in _parts:
		var p: Part = _parts[id]
		if p.kind == kind and (model == "" or p.fits_weapon(model)):
			out.append(p)
	return out


func owns(id: String) -> bool:
	return owned.get(id, false)


func owned_weapons() -> Array[String]:
	var out: Array[String] = []
	for p in parts_of(Part.Kind.WEAPON):
		if owns(p.id):
			out.append(p.weapon_model)
	return out


func can_afford(id: String) -> bool:
	var p := part(id)
	return p != null and points >= p.price


func buy(id: String) -> bool:
	var p := part(id)
	if p == null:
		return false
	if p.kind == Part.Kind.MAGAZINE:
		var pouch_cap := 4
		if int(magazines.get(p.mag_type, 0)) >= pouch_cap:
			refused.emit("The pouch holds %d %s magazines" % [pouch_cap, Ordnance.type_name(p.mag_type)])
			return false
	elif p.kind == Part.Kind.UTILITY:
		var belt_cap := int(UtilityBelt.row(p.utility_id).get("max", 0))
		if int(utilities.get(p.utility_id, 0)) >= belt_cap:
			refused.emit("The belt holds %d %s" % [belt_cap, p.title.to_lower() + "s"])
			return false
	elif owns(id):
		refused.emit("%s is already yours" % p.title)
		return false
	if points < p.price:
		refused.emit("%s costs $%d, you have $%d" % [p.title, p.price, points])
		return false
	points -= p.price
	if p.kind == Part.Kind.MAGAZINE:
		magazines[p.mag_type] = int(magazines.get(p.mag_type, 0)) + 1
	elif p.kind == Part.Kind.UTILITY:
		utilities[p.utility_id] = int(utilities.get(p.utility_id, 0)) + 1
	else:
		owned[id] = true
	bought.emit(p)
	changed.emit()
	return true


func install(model: String, id: String) -> bool:
	var p := part(id)
	if p == null or not owns(id) or not p.fits_weapon(model):
		refused.emit("%s does not fit the %s" % [p.title if p != null else id, model])
		return false
	if not installed.has(model):
		installed[model] = {"spring": "", "motor": ""}
	match p.kind:
		Part.Kind.SPRING:
			installed[model]["spring"] = id
		Part.Kind.MOTOR:
			installed[model]["motor"] = id
		_:
			return false
	part_installed.emit(p)
	changed.emit()
	return true


func choose_bb(mag_type: Ordnance.MagType, id: String) -> bool:
	var p := part(id)
	if p == null or p.kind != Part.Kind.BB_LOT or not owns(id):
		refused.emit("You do not have those BBs")
		return false
	bb_lot[mag_type] = id
	part_installed.emit(p)
	changed.emit()
	return true


func set_slot(slot: int, model: String) -> bool:
	if slot < 0 or slot >= SLOTS or not model in owned_weapons():
		refused.emit("You do not own the %s" % model)
		return false
	for i in loadout.size():
		if i != slot and loadout[i] == model:
			refused.emit("The %s is already in the other slot" % model)
			return false
	while loadout.size() < SLOTS:
		loadout.append("")
	loadout[slot] = model
	changed.emit()
	return true


func installed_part(model: String, key: String) -> Part:
	if not installed.has(model):
		return null
	return part(String(installed[model].get(key, "")))


func bb_for(mag_type: Ordnance.MagType) -> Part:
	return part(String(bb_lot.get(mag_type, "bb_020")))


func make_magazine(mag_type: Ordnance.MagType) -> Magazine:
	var base := load(MAG_PATHS[mag_type]) as Magazine
	if base == null:
		return null
	var mag := base.duplicate() as Magazine
	var lot := bb_for(mag_type)
	if lot != null:
		mag.bb_mass_kg = lot.bb_mass_kg
	mag.refill()
	return mag


func apply_to_player(player: Node) -> void:
	if player == null:
		return
	var rack := _find(player, "weapon_rack") as WeaponRack
	var pouch := _find(player, "pouch") as MagazinePouch
	if rack == null:
		return
	var carried: Array[int] = []
	var all := rack.all_weapons()
	for model in loadout:
		for i in all.size():
			if all[i].weapon_model == model:
				carried.append(i)
	for g in all:
		var spring := installed_part(g.weapon_model, "spring")
		if spring != null:
			spring.apply(g)
		var motor := installed_part(g.weapon_model, "motor")
		if motor != null:
			motor.apply(g)
		var fresh := make_magazine(g.accepted_mag)
		if fresh != null:
			g.magazine = fresh
	rack.set_carried(carried)
	if pouch != null:
		pouch.clear()
		for g in rack.weapons():
			for _i in int(magazines.get(g.accepted_mag, 0)):
				pouch.add(make_magazine(g.accepted_mag))
	for g in rack.weapons():
		g.emit_state()
	var belt := _find(player, "utility")
	if belt != null and belt.has_method("refill"):
		belt.refill(utilities)
	changed.emit()


func deploy(briefed := false) -> void:
	deploy_requested.emit(briefed)


func _on_level_cleared(_index: int, summary: Dictionary) -> void:
	points += int(summary.get("gained", summary.get("level_score", 0)))
	changed.emit()


func _find(root: Node, group: String) -> Node:
	for n in get_tree().get_nodes_in_group(group):
		if root.is_ancestor_of(n) or n == root:
			return n
	return null
