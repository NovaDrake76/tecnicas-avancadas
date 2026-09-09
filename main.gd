extends Node3D


const ARMORY_SCENE := "res://Levels/armory.tscn"
const PLAYER_SCENE := "res://Player/Player.tscn"
const WAVE_SCENES := ["res://Characters/Enemy/kiwi.tscn", "res://Characters/Enemy/kiwi.tscn",
	"res://Characters/Enemy/rusher_kiwi.tscn"]
const WAVE_MIN_DISTANCE := 20.0
const WAVE_FALLBACK_DISTANCE := 40.0

@onready var players: Node3D = $Players
@onready var level_holder: Node3D = $LevelHolder
@onready var briefing: Briefing = $Briefing

var _level: Node
var _waves := 0


func _player() -> Player:
	return Player.local(get_tree())


func _ready() -> void:
	Run.level_cleared.connect(_on_level_over)
	Run.level_failed.connect(_on_level_over)
	Alarm.reinforcements_due.connect(_on_reinforcements_due)
	Armory.deploy_requested.connect(_on_deploy)
	Run.restart_requested.connect(_on_restart)
	briefing.go_pressed.connect(_on_briefing_go)
	multiplayer.peer_disconnected.connect(_on_peer_left)

	if multiplayer.is_server():
		_make_player.rpc(multiplayer.get_unique_id())
		Run.start_run()
		Armory.reset()
		_enter_armory()
	else:
		Run.start_run()
		Armory.reset()
		_ask_again()


func _ask_again() -> void:
	var tries := 0
	while tries < 150 and is_inside_tree() and not multiplayer.is_server() \
			and Player.local(get_tree()) == null:
		_report_in.rpc_id(1)
		tries += 1
		await get_tree().create_timer(0.4).timeout


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


@rpc("any_peer", "call_remote", "reliable")
func _report_in() -> void:
	if not multiplayer.is_server():
		return
	var newcomer := multiplayer.get_remote_sender_id()
	for node in players.get_children():
		_make_player.rpc_id(newcomer, String(node.name).to_int())
	_make_player.rpc(newcomer)
	_send_world.rpc_id(newcomer, Run.state, Run.level_index)


func _on_peer_left(id: int) -> void:
	if multiplayer.is_server():
		_drop_player.rpc(id)


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


@rpc("authority", "call_local", "reliable")
func _go_armory() -> void:
	_enter_armory()


@rpc("authority", "call_local", "reliable")
func _go_level(index: int, briefed: bool) -> void:
	Run.level_index = index
	_waves = 0
	if PauseMenu.is_open():
		PauseMenu.close()
	var who := _player()
	if who != null:
		who.process_mode = Node.PROCESS_MODE_INHERIT
		Armory.apply_to_player(who)
	if briefed:
		briefing.arm(index)
		if who != null:
			who.process_mode = Node.PROCESS_MODE_DISABLED
	await Fade.cover()
	if briefed:
		briefing.present()
	_load_level()


@rpc("authority", "call_local", "reliable")
func _release_briefing() -> void:
	briefing.release()


func _on_briefing_go() -> void:
	if multiplayer.is_server():
		_release_briefing.rpc()


@rpc("authority", "call_remote", "reliable")
func _send_world(run_state: int, index: int) -> void:
	Run.level_index = index
	if run_state == Run.State.PLAYING:
		_go_level(index, false)
	else:
		_go_armory()


func _on_deploy(briefed: bool) -> void:
	if not multiplayer.is_server():
		return
	_go_level.rpc(Run.level_index, briefed and Run.has_briefing(Run.level_index))


func _on_restart(index: int) -> void:
	if not multiplayer.is_server():
		return
	_go_level.rpc(index, false)


func _load_level() -> void:
	if _level != null and is_instance_valid(_level):
		_level.queue_free()
		_level = null

	var packed := load(Run.level_path()) as PackedScene
	if packed == null:
		push_error("main.gd: cannot load %s" % Run.level_path())
		return

	_level = packed.instantiate()
	if briefing.is_open():
		_level.process_mode = Node.PROCESS_MODE_DISABLED
	level_holder.add_child(_level)

	## the kiwis register in _ready and the terrain has to exist before the player is placed, so both happen a frame before the run counts.
	_begin.call_deferred()


func _begin() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavBake.bake(_level, _level)
	if briefing.is_open():
		briefing.loaded()
		if not briefing.is_released():
			await briefing.dismissed
	if _level == null or not is_instance_valid(_level):
		return
	_level.process_mode = Node.PROCESS_MODE_INHERIT
	move_player_to_spawn()
	var here := _player()
	if here != null:
		here.process_mode = Node.PROCESS_MODE_INHERIT
		here.restore()
	Run.begin_level(_level)
	Fade.uncover()


func _on_reinforcements_due(at: Vector3) -> void:
	if _level == null or not is_instance_valid(_level) or Run.state != Run.State.PLAYING:
		return
	if not Alarm.gunship:
		_send_wave(at)
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


func _send_wave(at: Vector3) -> void:
	var from := _wave_origin(at)
	if from == Vector3.INF:
		return
	var side := at - from
	side.y = 0.0
	side = side.normalized().cross(Vector3.UP) if side.length_squared() > 0.01 else Vector3.RIGHT
	var spots: Array = []
	for i in WAVE_SCENES.size():
		spots.append(from + side * (float(i) - 1.0) * 2.5)
	_waves += 1
	_net_wave.rpc(_waves, spots, at)


@rpc("authority", "call_local", "reliable")
func _net_wave(wave: int, spots: Array, at: Vector3) -> void:
	if _level == null or not is_instance_valid(_level):
		return
	for i in mini(spots.size(), WAVE_SCENES.size()):
		var packed := load(WAVE_SCENES[i]) as PackedScene
		if packed == null:
			continue
		var bird := packed.instantiate() as Kiwi
		bird.name = "Wave%dBird%d" % [wave, i]
		bird.add_to_group("reinforcement")
		_level.add_child(bird)
		bird.global_position = spots[i]
		if multiplayer.is_server():
			Run.adopt(bird)
			bird.told(at)


func _wave_origin(at: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for node in get_tree().get_nodes_in_group("bird_spawn"):
		var marker := node as Node3D
		if marker == null:
			continue
		var d := marker.global_position.distance_to(at)
		if d >= WAVE_MIN_DISTANCE and d < best_d:
			best_d = d
			best = marker.global_position
	if best != Vector3.INF:
		return best
	var origin: Vector3 = (_level as Node3D).global_position if _level is Node3D else Vector3.ZERO
	var out := at - origin
	out.y = 0.0
	out = out.normalized() if out.length_squared() > 1.0 else Vector3.BACK
	for dir in [-out, out]:
		var grounded := _ground(at + dir * WAVE_FALLBACK_DISTANCE)
		if grounded != Vector3.INF:
			return grounded
	return Vector3.INF


func _ground(point: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 40.0, point + Vector3.DOWN * 40.0, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return hit["position"] + Vector3.UP * 0.05


func move_player_to_spawn() -> void:
	var who := _player()
	if who != null and who.has_method("respawn_from_void"):
		who.respawn_from_void()


func _on_level_over(_index: int, _summary: Dictionary) -> void:
	var who := _player()
	if who != null:
		who.process_mode = Node.PROCESS_MODE_DISABLED
	if not multiplayer.is_server():
		return
	if DisplayServer.get_name() == "headless":
		await get_tree().create_timer(Run.CLEAR_PAUSE).timeout
	else:
		await Run.results_dismissed
	await Fade.cover()
	_go_armory.rpc()
