class_name MagazinePickup
extends Area3D

## a magazine lying in the world, aimed at and taken with the interact key.
## taking it swaps rather than deletes, this pickup keeps whatever came off the gun.

signal contents_changed(mag: Magazine)

const TYPE_COLORS := {
	Ordnance.MagType.Shotgun: Color(0.88, 0.36, 0.24),
	Ordnance.MagType.Rifle: Color(0.28, 0.62, 0.95),
	Ordnance.MagType.Pistol1911: Color(0.95, 0.78, 0.28),
	Ordnance.MagType.PistolGlock: Color(0.5, 0.85, 0.42),
}

@export var magazine: Magazine
@export var spin_speed: float = 1.2
@export var bob_height: float = 0.06

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var interactable: Interactable = $Interactable

var _base_y := 0.0
var _clock := 0.0


func _ready() -> void:
	_base_y = mesh.position.y
	if magazine != null:
		magazine = magazine.duplicate()
	interactable.interacted.connect(_on_interacted)
	_refresh()


func _process(delta: float) -> void:
	_clock += delta
	mesh.rotate_y(spin_speed * delta)
	mesh.position.y = _base_y + sin(_clock * 2.0) * bob_height


func _on_interacted(_by: Node) -> void:
	var gun := get_tree().get_first_node_in_group("weapon") as Gun
	if gun != null:
		take(gun)


func take(gun: Gun) -> bool:
	if magazine == null or gun == null:
		return false

	var previous := gun.magazine
	if not gun.equip_magazine(magazine):
		return false

	magazine = previous
	contents_changed.emit(magazine)
	_refresh()

	if magazine == null:
		queue_free()
	return true


func _refresh() -> void:
	if magazine == null:
		mesh.visible = false
		interactable.set_enabled(false)
		return

	mesh.visible = true
	interactable.set_enabled(true)
	interactable.prompt = "Take %s  %d/%d  %.2f g" % [
		magazine.type_label(), magazine.count, magazine.capacity, magazine.mass_grams()]

	var material := StandardMaterial3D.new()
	material.albedo_color = TYPE_COLORS.get(magazine.mag_type, Color.WHITE)
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.35
	mesh.material_override = material
