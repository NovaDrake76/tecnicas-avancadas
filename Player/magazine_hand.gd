class_name MagazineHand
extends Node3D


const MODELS := {
	Ordnance.MagType.Rifle: "res://Models/Ammo/rifle_mag.obj",
	Ordnance.MagType.Marksman: "res://Models/Ammo/rifle_mag.obj",
	Ordnance.MagType.PistolHeavy: "res://Models/Ammo/pistol_mp_1_mag_loaded.glb",
	Ordnance.MagType.PistolMachine: "res://Models/Ammo/pistol_mp_1_mag_extended_loaded.glb",
	Ordnance.MagType.Shotgun: "res://Models/Ammo/shotgun_ammo_1.glb",
}

## where the magazine is held up, in camera space: left of the weapon, turned so the eye reads it.
@export var hand_offset := Vector3(-0.15, -0.10, -0.34)
@export var hand_tilt_deg := Vector3(-20.0, 30.0, 10.0)
## it rises from here, relative to the held spot, over rise_time.
@export var rise_from := Vector3(0.0, -0.22, 0.0)
@export var rise_time := 0.22

var _models := {}
var _shown: Node3D
var _t := 0.0
var _up := false
var _pass: ViewmodelPass


func _ready() -> void:
	add_to_group("magazine_hand")
	visible = false
	_bind.call_deferred()


func _bind() -> void:
	var player: Node = get_parent()
	while player != null and not (player is Player):
		player = player.get_parent()
	if player == null:
		return
	var passes := player.find_children("*", "ViewmodelPass", true, false)
	if not passes.is_empty():
		_pass = passes[0] as ViewmodelPass
	var rack := player.find_child("Weapons", true, false) as WeaponRack
	if rack == null:
		return
	for g in rack.all_weapons():
		g.check_started.connect(_on_check_started.bind(g))
		g.check_ended.connect(_on_check_ended)


func _on_check_started(gun: Gun) -> void:
	var model := _model_for(gun.accepted_mag)
	if model == null:
		return
	if _shown != null and _shown != model:
		_shown.visible = false
	_shown = model
	_shown.visible = true
	_up = true
	visible = true
	if _pass != null:
		_pass.take_over(self)


func _on_check_ended() -> void:
	_up = false


func is_up() -> bool:
	return _up and visible


func _process(delta: float) -> void:
	if not visible:
		return
	_t = move_toward(_t, 1.0 if _up else 0.0, delta / maxf(rise_time, 0.01))
	var eased := smoothstep(0.0, 1.0, _t)
	position = hand_offset + rise_from * (1.0 - eased)
	var tilt := Vector3(deg_to_rad(hand_tilt_deg.x), deg_to_rad(hand_tilt_deg.y), deg_to_rad(hand_tilt_deg.z))
	rotation = tilt + Vector3(0.0, 0.0, -0.5) * (1.0 - eased)
	if not _up and _t <= 0.0:
		visible = false
		if _pass != null:
			_pass.hand_back(self)


func _model_for(mag_type: Ordnance.MagType) -> Node3D:
	if _models.has(mag_type):
		return _models[mag_type]
	var path: String = MODELS.get(mag_type, "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res := load(path)
	var holder := Node3D.new()
	var bounds := AABB()
	if res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		holder.add_child(mi)
		bounds = (res as Mesh).get_aabb()
	elif res is PackedScene:
		var node := (res as PackedScene).instantiate() as Node3D
		if node == null:
			return null
		holder.add_child(node)
		for child in node.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				bounds = bounds.merge(mi.transform * mi.mesh.get_aabb()) if bounds.has_volume() else mi.transform * mi.mesh.get_aabb()
	else:
		return null
	holder.position = -bounds.get_center()
	var shell := Node3D.new()
	shell.add_child(holder)
	shell.visible = false
	add_child(shell)
	_models[mag_type] = shell
	return shell
