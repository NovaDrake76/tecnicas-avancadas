extends Node3D

## hosts whatever level the run is on. the player, the hud and the world stay put across levels,
## only the level scene is swapped, so nothing has to be rebuilt between them.

const ARMORY_SCENE := "res://Levels/armory.tscn"

@onready var player: CharacterBody3D = $Player
@onready var level_holder: Node3D = $LevelHolder

var _level: Node


func _ready() -> void:
	Run.level_cleared.connect(_on_level_over)
	Run.level_failed.connect(_on_level_over)
	player.health.died.connect(Run.fail_level)
	Alarm.reinforcements_due.connect(_on_reinforcements_due)
	Armory.deploy_requested.connect(_on_deploy)
	Run.start_run()
	Armory.reset()
	_enter_armory()


## the safe house sits in the level holder like a level, so the same player, hud and sky serve it.
## the run counts nothing while it is up; the bench's DEPLOY is what loads the next level.
func _enter_armory() -> void:
	if _level != null and is_instance_valid(_level):
		_level.queue_free()
		_level = null
	var packed := load(ARMORY_SCENE) as PackedScene
	if packed == null:
		push_error("main.gd: cannot load %s" % ARMORY_SCENE)
		return
	_level = packed.instantiate()
	level_holder.add_child(_level)
	_settle_armory.call_deferred()


func _settle_armory() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	move_player_to_spawn()
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.restore()
	Armory.apply_to_player(player)
	Run.enter_armory()
	Fade.uncover()


## the curtain comes down, the level swaps underneath, and _begin lifts it once the run is counting.
func _on_deploy() -> void:
	Armory.apply_to_player(player)
	await Fade.cover()
	_load_level()


func _load_level() -> void:
	if _level != null and is_instance_valid(_level):
		_level.queue_free()
		_level = null

	var packed := load(Run.level_path()) as PackedScene
	if packed == null:
		push_error("main.gd: cannot load %s" % Run.level_path())
		return

	_level = packed.instantiate()
	level_holder.add_child(_level)

	## the level's kiwis register themselves in _ready, and the terrain has to exist before the
	## player is placed on it, so both happen a frame before the run counts anything.
	_begin.call_deferred()


func _begin() -> void:
	## the terrain builds its collision in _ready and the old level frees itself at the end of the
	## frame. the physics server knows about neither until it has stepped, and a spawn placed
	## before that reads the ground of the level we just left, or no ground at all.
	await get_tree().physics_frame
	await get_tree().physics_frame
	## the props have built their collision by now, so this is the first moment the mesh can be right.
	## behind the curtain, before the run counts, before any kiwi has somewhere to go.
	NavBake.bake(_level, _level)
	move_player_to_spawn()
	player.restore()
	Run.begin_level(_level)
	Fade.uncover()


## the alarm's countdown ran out: the gunship comes in, from the level's HeliApproach marker if it
## has one, else from eighty metres out and thirty up on the far side of the trouble. it is a child of
## the level so it goes with it, and it is in no kiwi group: reinforcements never count towards the
## mission, or an alarm would make a mission longer the more trouble you were in, which is backwards.
func _on_reinforcements_due(at: Vector3) -> void:
	if _level == null or not is_instance_valid(_level) or Run.state != Run.State.PLAYING:
		return
	if get_tree().get_first_node_in_group("gunship") != null:
		return
	var from := Vector3.ZERO
	var marker := get_tree().get_first_node_in_group("heli_approach") as Node3D
	if marker != null:
		from = marker.global_position
	else:
		var origin: Vector3 = (_level as Node3D).global_position if _level is Node3D else Vector3.ZERO
		var out: Vector3 = at - origin
		out.y = 0.0
		out = out.normalized() if out.length_squared() > 1.0 else Vector3.BACK
		from = at + out * 80.0 + Vector3.UP * 30.0
	var ship := Gunship.new()
	_level.add_child(ship)
	ship.dispatch(from, at)


## the lookup lives on the player so KillPlane and this share one implementation.
func move_player_to_spawn() -> void:
	if player != null and player.has_method("respawn_from_void"):
		player.respawn_from_void()


## every clear, and every failure, goes back to the safe house; the board says what opened. the player is
## frozen under the report card and the run waits for them to press the key; headless, where nobody
## can, it waits the old fixed pause instead. then the curtain falls and the armory swaps in underneath.
func _on_level_over(_index: int, _summary: Dictionary) -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	if DisplayServer.get_name() == "headless":
		await get_tree().create_timer(Run.CLEAR_PAUSE).timeout
	else:
		await Run.results_dismissed
	await Fade.cover()
	_enter_armory()
