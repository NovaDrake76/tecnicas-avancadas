class_name Objective
extends Node3D


signal completed(objective: Objective)
signal progress_changed(value: float)
signal working_changed(active: bool)
signal abandoned()

enum Kind {
	ELIMINATE,
	STEAL,
	SABOTAGE,
	EXFIL,
}

@export var id: StringName = &"objective"
@export var kind: Kind = Kind.STEAL
## the line the hud shows while this is the live objective.
@export var label := "Objective"
## optional ones pay points and never hold the mission open.
@export var optional := false

@export_group("Work")
## how long the player has to stay on it.
@export var work_time := 3.0
## how far the player may drift before the work is abandoned and starts again from nothing.
@export var work_reach := 2.5
@export var prompt := "Take it"

@export_group("Sabotage")
## seconds between the charge going on and it going off.
@export var fuse := 12.0
@export var blast_radius := 6.0

@export_group("Eliminate")
## every node in this group has to answer is_down().
@export var target_group: StringName = &"hvt"

@export_group("Exfil")
@export var reach := 3.0

@export_group("Look")
## what the objective IS, in the world.
@export var model: PackedScene
## a small light on it, because a real prop among other real props is invisible: the whole reason the first pass drew a...
@export var glow := Color(1.0, 0.85, 0.45)
@export var glow_range := 3.2

var _done := false
var _work := 0.0
var _working := false
var _fuse_left := -1.0
var _charged := false
var _handle: Area3D
var _interact: Interactable
var _marker: Node3D
var _lamp: OmniLight3D
var _was_working := false


func _ready() -> void:
	add_to_group("objective")
	if kind == Kind.STEAL or kind == Kind.SABOTAGE:
		_build_handle()
	_build_marker()


func _build_handle() -> void:
	_handle = Area3D.new()
	_handle.collision_layer = 128
	_handle.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.9, 0.9)
	shape.shape = box
	shape.position = Vector3(0.0, 0.45, 0.0)
	_handle.add_child(shape)
	add_child(_handle)
	_interact = Interactable.new()
	_interact.prompt = prompt
	add_child(_interact)
	_interact.interacted.connect(_on_interacted)


func _process(delta: float) -> void:
	if _done and _fuse_left < 0.0:
		return
	match kind:
		Kind.ELIMINATE:
			_poll_targets()
		Kind.STEAL, Kind.SABOTAGE:
			_step_work(delta)
		Kind.EXFIL:
			_step_exfil()
	var now := is_working()
	if now != _was_working:
		_was_working = now
		working_changed.emit(now)


func _poll_targets() -> void:
	var marked := get_tree().get_nodes_in_group(target_group)
	if marked.is_empty():
		return
	for node in marked:
		if not node.has_method("is_down") or not node.is_down():
			return
	_finish()


func _on_interacted(_by: Node) -> void:
	if _done or _working:
		return
	_working = true
	_work = 0.0
	Sfx.play_2d(&"objective_start")


func _nobody_at(within: float) -> bool:
	for who in Player.all(get_tree()):
		if who.global_position.distance_to(global_position) <= within:
			return false
	return true


func _step_work(delta: float) -> void:
	if _fuse_left >= 0.0:
		_fuse_left -= delta
		if _fuse_left <= 0.0:
			_fuse_left = -1.0
			_detonate()
		return
	if not _working:
		return
	if _nobody_at(work_reach):
		_working = false
		_work = 0.0
		progress_changed.emit(0.0)
		abandoned.emit()
		return
	_work += delta
	progress_changed.emit(progress())
	if _work < work_time:
		return
	_working = false
	_ask_finish.rpc_id(1)
	return
@rpc("any_peer", "call_local", "reliable")
func _ask_finish() -> void:
	if not multiplayer.is_server() or _done:
		return
	if kind == Kind.SABOTAGE and not _charged:
		_net_fuse.rpc()
		return
	_net_done.rpc()


@rpc("authority", "call_local", "reliable")
func _net_fuse() -> void:
	_charged = true
	_fuse_left = fuse
	Sfx.play(&"charge_set", global_position)


@rpc("authority", "call_local", "reliable")
func _net_done() -> void:
	if kind != Kind.SABOTAGE:
		Sfx.play(&"objective_done", global_position)
	_finish()


func _detonate() -> void:
	Sfx.hdr(global_position, 8.0, 40.0)
	Sfx.play(&"mortar_blast", global_position)
	BurstFx.spawn(get_tree().current_scene, global_position + Vector3.UP * 0.5,
		Color(1.0, 0.7, 0.3), 40, 6.0)
	if multiplayer.is_server():
		Alarm.raise_alarm(global_position)
		_ask_finish()


func _step_exfil() -> void:
	if not is_armed():
		return
	var here := Player.all(get_tree())
	if here.is_empty():
		return
	for who in here:
		if who.global_position.distance_to(global_position) > reach:
			return
	_finish()


func is_armed() -> bool:
	if kind != Kind.EXFIL:
		return true
	for node in get_tree().get_nodes_in_group("objective"):
		var other := node as Objective
		if other == null or other == self or other.optional or other.kind == Kind.EXFIL:
			continue
		if not other.is_done():
			return false
	return true


func progress() -> float:
	if kind == Kind.SABOTAGE and _fuse_left >= 0.0:
		return 1.0 - clampf(_fuse_left / maxf(fuse, 0.001), 0.0, 1.0)
	return clampf(_work / maxf(work_time, 0.001), 0.0, 1.0)


func is_working() -> bool:
	return _working or _fuse_left >= 0.0


func is_done() -> bool:
	return _done


func fuse_left() -> float:
	return _fuse_left


func force_complete() -> void:
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_working = false
	if _interact != null:
		_interact.set_enabled(false)
	if _marker != null and kind != Kind.EXFIL:
		_marker.visible = false
	if _lamp != null:
		_lamp.visible = false
	completed.emit(self)


const DEFAULT_MODELS := {
	Kind.STEAL: "res://Models/Props/Clutter/toolbox_mx_1.glb",
	Kind.SABOTAGE: "res://Models/Props/Barrels/metal_barrel_hr_1.glb",
}


func _build_marker() -> void:
	for child in get_children():
		if child is VisualInstance3D:
			return
	if kind == Kind.EXFIL:
		return
	var scene := model
	if scene == null and DEFAULT_MODELS.has(kind):
		var path: String = DEFAULT_MODELS[kind]
		if ResourceLoader.exists(path):
			scene = load(path) as PackedScene
	if scene == null:
		return
	var view := scene.instantiate() as Node3D
	add_child(view)
	_marker = view
	var lamp := OmniLight3D.new()
	lamp.light_color = glow
	lamp.omni_range = glow_range
	lamp.light_energy = 1.1
	lamp.position = Vector3(0.0, 0.55, 0.0)
	add_child(lamp)
	_lamp = lamp
