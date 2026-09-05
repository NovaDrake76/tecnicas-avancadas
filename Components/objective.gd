class_name Objective
extends Node3D

## the thing a mission is actually about. drop one of these in a level, set its kind and its label,
## and Run picks it up from the group: the LEVEL declares what the mission is, not a table somewhere
## else, so adding an objective is placing a node and nothing more.
##
## a mission ends when every REQUIRED objective is done. taking out every kiwi is no longer the win
## condition; it is an ordinary optional objective on the missions that want it, and the birds go
## back to being the obstacle course rather than the point.

signal completed(objective: Objective)
signal progress_changed(value: float)
## a job started or stopped. the hud puts a ring round the crosshair on it, the same ring a reload
## uses, because 'an action is running, wait for it' is the same sentence in both cases.
signal working_changed(active: bool)
## the player walked away from a job that had already started. worth its own signal: without a word
## for it the progress just vanishes and the player is left guessing whether it counted.
signal abandoned()

enum Kind {
	## a named bird or a named group of them, never the whole field.
	ELIMINATE,
	## a case, a terminal, a set of papers. stand on it and hold.
	STEAL,
	## a charge placed on something, and then a fuse.
	SABOTAGE,
	## the way out. inert until everything else required is done.
	EXFIL,
}

@export var id: StringName = &"objective"
@export var kind: Kind = Kind.STEAL
## the line the hud shows while this is the live objective.
@export var label := "Objective"
## optional ones pay points and never hold the mission open.
@export var optional := false

@export_group("Work")
## how long the player has to stay on it. the risk is standing still in the one place the mission
## says you have to be; ELIMINATE and EXFIL ignore it.
@export var work_time := 3.0
## how far the player may drift before the work is abandoned and starts again from nothing.
@export var work_reach := 2.5
@export var prompt := "Take it"

@export_group("Sabotage")
## seconds between the charge going on and it going off. the fuse is the player's warning to be
## somewhere else, which is the only reason a charge is different from a switch.
@export var fuse := 12.0
@export var blast_radius := 6.0

@export_group("Eliminate")
## every node in this group has to answer is_down(). a group rather than node paths, so a level
## designer marks a bird by adding it to a group in the inspector.
@export var target_group: StringName = &"hvt"

@export_group("Exfil")
@export var reach := 3.0

@export_group("Look")
## what the objective IS, in the world. leave it null and the kind picks a sensible prop out of the
## pack: a toolbox for something to take, a fuel drum for something to blow up. it is an export so a
## level designer swaps in whatever the room actually calls for without touching this file, exactly
## the way Prop takes a model.
@export var model: PackedScene
## a small light on it, because a real prop among other real props is invisible: the whole reason the
## first pass drew a glowing box was that a crate in a camp full of crates says nothing. the prop
## carries the fiction and the light carries "this one".
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


## the same shape as a body's drag handle: an AREA on the interactable layer, so the interactor's
## ray finds it and a bb passes straight through. a StaticBody here would be shootable.
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
	## read once a tick and compared, the same way the kiwi publishes its alert tier: a signal fired
	## from each of the three places work can stop would eventually miss one.
	var now := is_working()
	if now != _was_working:
		_was_working = now
		working_changed.emit(now)


## a group that is EMPTY has not been cleared, it has not been authored. completing on an empty
## group would hand the player a free objective on any level where the birds were not marked.
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


## true when not one operative is standing close enough.
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
	## walking off abandons it. the whole point of work_time is that it pins a player to one spot,
	## and a timer that ran while they left would not do that. it is ANY of them standing on it:
	## whoever started the job can be relieved by the other one, which is a reason to bring a second
	## pair of hands.
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
	## the work ran on the machine of the player doing it, which is what keeps the ring smooth in
	## their hands. what it MEANT is the host's: it says the charge is set, or the case is taken, and
	## says it to everybody at once. two operatives working the same objective is not a race, it is
	## the same job finished once.
	_ask_finish.rpc_id(1)
	return
## the host is the only machine that decides an objective is done, and it says so to everybody,
## itself included. a client that finished the work asks; a host that finished it asks itself.
@rpc("any_peer", "call_local", "reliable")
func _ask_finish() -> void:
	if not multiplayer.is_server() or _done:
		return
	## the charge is asked for TWICE: once when the work finishes, which starts the fuse, and once
	## when the fuse runs out, which is what actually completes it. "has a fuse been started" cannot
	## be read off the countdown, because a spent fuse and an unlit one are the same number.
	if kind == Kind.SABOTAGE and not _charged:
		_net_fuse.rpc()
		return
	_net_done.rpc()


## the charge is on and burning, on every machine: the fuse is a warning to be somewhere else, and a
## warning one player cannot see is not one.
@rpc("authority", "call_local", "reliable")
func _net_fuse() -> void:
	_charged = true
	_fuse_left = fuse
	Sfx.play(&"charge_set", global_position)


@rpc("authority", "call_local", "reliable")
func _net_done() -> void:
	## taking it is SILENT. the alarm has two sources and both are things the player did where a
	## bird could see or hear them; a mission that raised the compound by itself the moment the
	## objective was met would be the game undoing a clean infiltration on the player's behalf.
	if kind != Kind.SABOTAGE:
		Sfx.play(&"objective_done", global_position)
	_finish()


## a charge going off is not the game raising the alarm on itself: it is a loud thing the player
## chose to set, on a fuse they could watch, and being somewhere else when it goes is the play.
func _detonate() -> void:
	Sfx.hdr(global_position, 8.0, 40.0)
	Sfx.play(&"mortar_blast", global_position)
	BurstFx.spawn(get_tree().current_scene, global_position + Vector3.UP * 0.5,
		Color(1.0, 0.7, 0.3), 40, 6.0)
	## the blast is a loud thing the player CHOSE, on a fuse they could watch, so it is the one
	## objective that raises the compound. the alarm is the host's to raise and reaches the others
	## as a stage; the bang, the light and the ring are drawn wherever they are seen.
	if multiplayer.is_server():
		Alarm.raise_alarm(global_position)
		_ask_finish()


func _step_exfil() -> void:
	## the way out is not just inert until the rest is done, it is UNSHOWN: the hud asks is_armed()
	## before it draws anything, so nothing points at the end of a mission the player has not started
	## yet, and where the way out is stays unknown until that is worth knowing.
	if not is_armed():
		return
	## EVERYBODY has to be on it. a way out that opened for the first operative to reach it would
	## leave the second one in the compound, which is the one ending a co-op mission must not have.
	## with one player it is the same test it always was.
	var here := Player.all(get_tree())
	if here.is_empty():
		return
	for who in here:
		if who.global_position.distance_to(global_position) > reach:
			return
	_finish()


## the way out only counts once there is a reason to use it.
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


## for probes and for the sabotage charge, which finishes on its fuse rather than on a press.
func force_complete() -> void:
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_working = false
	if _interact != null:
		_interact.set_enabled(false)
	## a done objective stops glowing. the field should read at a glance, and a marker that still
	## shines after the job is the same lie as a quest arrow pointing at nothing.
	if _marker != null and kind != Kind.EXFIL:
		_marker.visible = false
	if _lamp != null:
		_lamp.visible = false
	completed.emit(self)


## something to LOOK at, built from the PACK rather than from primitives. an objective drawn as a
## glowing box is a placeholder telling the player "this is not really here"; a toolbox and a fuel
## drum are things that belong in a supply camp and a depot, and the small light on them is what says
## which one the mission means. anything placed as a child counts as the dressing and this is skipped,
## so a real set piece can take over later without touching the script.
const DEFAULT_MODELS := {
	Kind.STEAL: "res://Models/Props/Clutter/toolbox_mx_1.glb",
	Kind.SABOTAGE: "res://Models/Props/Barrels/metal_barrel_hr_1.glb",
}


func _build_marker() -> void:
	for child in get_children():
		if child is VisualInstance3D:
			return
	## the way out has no marker in the world at all. it used to be a green ring on the ground, and a
	## ring can only be read from somewhere it can be seen from: behind the container it was invisible
	## at the one moment it mattered, and among crates and barrels it read as a thing to walk up to and
	## press a key on. the hud draws it instead (HUD/waypoint.gd), as a direction and a distance that
	## survive a hill being in the way. a level designer who wants something standing there puts a
	## prop under the node, which skips this whole function.
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
	## the light rather than an emissive override, so the prop keeps its own material and reads as
	## the same object the rest of the camp is made of.
	var lamp := OmniLight3D.new()
	lamp.light_color = glow
	lamp.omni_range = glow_range
	lamp.light_energy = 1.1
	lamp.position = Vector3(0.0, 0.55, 0.0)
	add_child(lamp)
	_lamp = lamp
