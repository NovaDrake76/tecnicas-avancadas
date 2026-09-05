class_name MagazinePickup
extends Area3D

## a magazine lying in the world, or a box of several, taken with the interact key. it goes to the
## pouch, or straight into a weapon in hand that has no magazine at all. an incompatible one, or a
## full pouch, is refused with the reason.

signal contents_changed(mag: Magazine)

## what lies on the ground, per type: one magazine, or the carton several came in. the rifle's is the
## m4's own magazine split out of its mesh; the rest are from the psx pack, real centimetres.
const LOOKS := {
	Ordnance.MagType.Shotgun: {
		"single": "res://Models/Ammo/shotgun_ammo_1.glb", "box": "res://Models/Ammo/shotgun_ammo_2.glb"},
	Ordnance.MagType.Rifle: {
		"single": "res://Models/Ammo/rifle_mag.obj", "box": "res://Models/Ammo/ammo_box_mp_5.glb"},
	Ordnance.MagType.PistolHeavy: {
		"single": "res://Models/Ammo/pistol_mp_1_mag_loaded.glb", "box": "res://Models/Ammo/ammo_box_mp_1.glb"},
	Ordnance.MagType.PistolMachine: {
		"single": "res://Models/Ammo/pistol_mp_1_mag_extended_loaded.glb", "box": "res://Models/Ammo/ammo_box_mp_2.glb"},
	## the pack has no bolt-rifle magazine, so the marksman borrows the rifle's own and a carton.
	Ordnance.MagType.Marksman: {
		"single": "res://Models/Ammo/rifle_mag.obj", "box": "res://Models/Ammo/ammo_box_mp_5.glb"},
}

@export var magazine: Magazine
## how many magazines this pickup holds. a box is the same node with more than one.
@export var quantity := 1
@export var spin_speed: float = 1.2
@export var bob_height: float = 0.06
## a magazine is twelve centimetres. at true size it vanishes at ten metres; the ring says where, this
## says what.
@export var model_scale := 1.5

@onready var model: Node3D = $Model
@onready var interactable: Interactable = $Interactable

var _base_y := 0.0
var _clock := 0.0
var _shown := ""


func _ready() -> void:
	_base_y = model.position.y
	if magazine != null:
		magazine = magazine.duplicate()
	interactable.interacted.connect(_on_interacted)
	_refresh()


func _process(delta: float) -> void:
	_clock += delta
	model.rotate_y(spin_speed * delta)
	model.position.y = _base_y + sin(_clock * 2.0) * bob_height


func _on_interacted(_by: Node) -> void:
	var gun := get_tree().get_first_node_in_group("weapon") as Gun
	if gun != null:
		take(gun)


func take(gun: Gun) -> bool:
	if magazine == null or gun == null or quantity <= 0:
		return false

	var rack := gun.get_parent() as WeaponRack
	var taker: Gun = rack.weapon_for(magazine.mag_type) if rack != null else (gun if gun.accepts(magazine) else null)
	if taker == null:
		var message := "No weapon takes a %s magazine" % magazine.type_label()
		gun.magazine_rejected.emit(magazine, message)
		return false

	## a weapon in hand with nothing in it loads straight from the ground, the brief's "no magazine" case.
	if taker == gun and gun.magazine == null:
		if not gun.equip_magazine(magazine):
			return false
	else:
		var pouch := get_tree().get_first_node_in_group("pouch") as MagazinePouch
		if pouch == null or not pouch.add(magazine):
			return false

	quantity -= 1
	Sfx.play(&"pickup", global_position)
	contents_changed.emit(magazine)
	_refresh()
	if quantity <= 0:
		queue_free()
	return true


## which file this pickup shows right now. a box that is down to its last one is a magazine again.
func look_path() -> String:
	if magazine == null or not LOOKS.has(magazine.mag_type):
		return ""
	return LOOKS[magazine.mag_type]["box" if quantity > 1 else "single"]


func _refresh() -> void:
	if magazine == null:
		model.visible = false
		interactable.set_enabled(false)
		return

	model.visible = true
	interactable.set_enabled(true)
	_show(look_path())
	interactable.prompt = "Take %s  %d/%d  %.2f g%s" % [
		magazine.type_label(), magazine.count, magazine.capacity, magazine.mass_grams(),
		"  (%d left)" % quantity if quantity > 1 else ""]



## swap the model only when the file changes, and sit whatever comes in on its own centre: the pack's
## pistol magazines have their origin halfway up, the cartons have it at the base. measured, not assumed.
func _show(path: String) -> void:
	if path == _shown:
		return
	_shown = path
	for c in model.get_children():
		c.queue_free()
	if path == "" or not ResourceLoader.exists(path):
		return
	var res := load(path)
	var node: Node3D
	if res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		node = mi
	elif res is PackedScene:
		node = (res as PackedScene).instantiate() as Node3D
	if node == null:
		return
	model.add_child(node)
	var bounds := mesh_bounds(node)
	node.position = -bounds.get_center() * model_scale
	node.scale = Vector3.ONE * model_scale


## the merged bounds of every mesh under a node, in that node's space.
static func mesh_bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var rel := node.global_transform.affine_inverse() * mi.global_transform if node.is_inside_tree() else _relative(node, mi)
			var box := rel * mi.mesh.get_aabb()
			out = box if first else out.merge(box)
			first = false
		stack.append_array(n.get_children())
	return out


static func _relative(root: Node3D, leaf: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = leaf
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
