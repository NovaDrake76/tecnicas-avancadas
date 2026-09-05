extends Node3D

## hosts whatever level the run is on. the player, the hud and the world stay put across levels,
## only the level scene is swapped, so nothing has to be rebuilt between them.

const ARMORY_SCENE := "res://Levels/armory.tscn"
const PLAYER_SCENE := "res://Player/Player.tscn"

@onready var players: Node3D = $Players
@onready var level_holder: Node3D = $LevelHolder

var _level: Node


## the operative this machine drives. the same trap the reticle, the health bar and Run._gun_bound
## each paid for: a reference taken once and kept forever. quitting to the menu frees that player and
## spawns another, and a freed node compares equal to null, so every use below asks again rather than
## going on writing to a corpse. it surfaced when a mission first ENDED in the smoke probe, which
## frees the player mid-run on purpose.
func _player() -> Player:
	return Player.local(get_tree())


func _ready() -> void:
	Run.level_cleared.connect(_on_level_over)
	Run.level_failed.connect(_on_level_over)
	Alarm.reinforcements_due.connect(_on_reinforcements_due)
	Armory.deploy_requested.connect(_on_deploy)
	Run.restart_requested.connect(_on_restart)
	Net.local_player_ready.connect(_on_local_player)
	multiplayer.peer_connected.connect(_on_peer_joined)
	multiplayer.peer_disconnected.connect(_on_peer_left)

	## solo, this is the one player and nothing else happens. hosting, the host's own operative goes
	## in now and every machine that reports in gets one. joined, nothing is spawned here at all:
	## the host says who exists, including us, which is what keeps one list rather than two.
	if multiplayer.is_server():
		_make_player.rpc(multiplayer.get_unique_id())
		Run.start_run()
		Armory.reset()
		_enter_armory()
	else:
		Run.start_run()
		Armory.reset()
		## "I have the world open, tell me what is in it." a client that asked earlier would be
		## asking from the menu, where there is nowhere to put anything.
		##
		## it is asked again until it is answered, because both machines leave the menu on the SAME
		## call: the client can easily have main open a frame before the host does, and an rpc that
		## arrives at a path which does not exist yet is simply dropped. one ask would have made
		## joining work most of the time, which is the worst way for it to work.
		_ask_again()


func _ask_again() -> void:
	var tries := 0
	while tries < 40 and is_inside_tree() and not multiplayer.is_server() 			and players.get_child_count() == 0:
		_report_in.rpc_id(1)
		tries += 1
		await get_tree().create_timer(0.4).timeout


## one operative per peer, NAMED AFTER IT. the name is the whole handshake: a player node reads it
## and knows whose it is, so no message ever has to say. spawning is done by hand rather than with a
## MultiplayerSpawner because the two machines do not load this scene at the same moment -- a spawn
## sent while the other side is still in the menu goes nowhere, and this way the host only ever
## builds the list when somebody says they are ready to receive it.
@rpc("authority", "call_local", "reliable")
func _make_player(id: int) -> void:
	if players.has_node(str(id)):
		return
	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		push_error("main.gd: cannot load %s" % PLAYER_SCENE)
		return
	var who := packed.instantiate() as Player
	who.name = str(id)
	players.add_child(who)


@rpc("authority", "call_local", "reliable")
func _drop_player(id: int) -> void:
	if players.has_node(str(id)):
		players.get_node(str(id)).queue_free()


## a machine has main.tscn open and is ready to be told what is in it: every operative that already
## exists, its own, and which scene the mission is on. this is the only join handshake there is.
@rpc("any_peer", "call_remote", "reliable")
func _report_in() -> void:
	if not multiplayer.is_server():
		return
	var newcomer := multiplayer.get_remote_sender_id()
	for node in players.get_children():
		_make_player.rpc_id(newcomer, String(node.name).to_int())
	_make_player.rpc(newcomer)
	_send_world.rpc_id(newcomer, Run.state, Run.level_index)


func _on_peer_joined(_id: int) -> void:
	pass


func _on_peer_left(id: int) -> void:
	if multiplayer.is_server():
		_drop_player.rpc(id)


## the local operative exists: wire the one thing main owns about it, its death.
func _on_local_player(who: Node) -> void:
	var here := who as Player
	if here == null or here.health == null:
		return
	if not here.health.died.is_connected(_on_local_died):
		here.health.died.connect(_on_local_died)


## solo this is simply the end of the run. in a joined game it is the co-op rule: one operative down
## is not a failed mission, everybody down is.
func _on_local_died() -> void:
	Run.report_down(multiplayer.get_unique_id())


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
	var who := _player()
	if who == null:
		return
	who.process_mode = Node.PROCESS_MODE_INHERIT
	who.restore()
	Armory.apply_to_player(who)
	Run.enter_armory()
	Fade.uncover()


## ---------------------------------------------------------------- one world, one word for it
## every scene swap in the game goes through one of these two, and both are the HOST's to call. the
## client never decides where it is: a co-op mission where one machine was in the safe house and the
## other in the compound would not be one mission. `call_local` is what keeps the host on the same
## path as everybody else instead of a second one written beside it.
@rpc("authority", "call_local", "reliable")
func _go_armory() -> void:
	_enter_armory()


@rpc("authority", "call_local", "reliable")
func _go_level(index: int) -> void:
	Run.level_index = index
	if PauseMenu.is_open():
		PauseMenu.close()
	var who := _player()
	if who != null:
		## the report card freezes the player, and a restart from a pause is the one path where a
		## level ends without one, so nothing else would ever hand it back.
		who.process_mode = Node.PROCESS_MODE_INHERIT
		Armory.apply_to_player(who)
	await Fade.cover()
	_load_level()


## a machine that has just joined is somewhere else entirely: the host says which scene it should be
## looking at and which mission the run is on, and it catches up from there.
@rpc("authority", "call_remote", "reliable")
func _send_world(run_state: int, index: int) -> void:
	Run.level_index = index
	if run_state == Run.State.PLAYING:
		_go_level(index)
	else:
		_go_armory()


## the curtain comes down, the level swaps underneath, and _begin lifts it once the run is counting.
func _on_deploy() -> void:
	if not multiplayer.is_server():
		return
	_go_level.rpc(Run.level_index)


## the same mission again, from the top. it goes through the same curtain and the same _load_level
## as a deploy does, so there is one path that builds a level and a restart cannot drift away from
## it. the loadout is re-applied for the same reason it is on deploy: the magazines spent in the
## attempt being thrown away come back, because the attempt is being thrown away too.
func _on_restart(index: int) -> void:
	if not multiplayer.is_server():
		return
	_go_level.rpc(index)


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
	var here := _player()
	if here != null:
		here.restore()
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
	var who := _player()
	if who != null and who.has_method("respawn_from_void"):
		who.respawn_from_void()


## every clear, and every failure, goes back to the safe house; the board says what opened. the player is
## frozen under the report card and the run waits for them to press the key; headless, where nobody
## can, it waits the old fixed pause instead. then the curtain falls and the armory swaps in underneath.
func _on_level_over(_index: int, _summary: Dictionary) -> void:
	var who := _player()
	if who != null:
		who.process_mode = Node.PROCESS_MODE_DISABLED
	## the way home is the HOST's. every machine plays the card and every player can dismiss their
	## own, but one of them has to say when the safe house comes back or two operatives would be
	## reading their results in different rooms. a client that has dismissed simply waits.
	if not multiplayer.is_server():
		return
	if DisplayServer.get_name() == "headless":
		await get_tree().create_timer(Run.CLEAR_PAUSE).timeout
	else:
		await Run.results_dismissed
	await Fade.cover()
	_go_armory.rpc()
