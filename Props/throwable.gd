class_name Throwable
extends RigidBody3D


## how long it lives if nothing else disposes of it.
@export var lifetime := 12.0

var mine := true

var _landed := false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = true
	_build()
	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(_expire)


func _build() -> void:
	pass


func _expire() -> void:
	queue_free()


func _show_model(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var mesh := load(path) as Mesh
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = -mesh.get_aabb().get_center()
	add_child(mi)


func has_landed() -> bool:
	return _landed
