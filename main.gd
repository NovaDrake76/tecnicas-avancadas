extends Node3D

## hosts whatever level the run is on. the player, the hud and the world stay put across levels,
## only the level scene is swapped, so nothing has to be rebuilt between them.

@onready var player: CharacterBody3D = $Player
@onready var level_holder: Node3D = $LevelHolder

var _level: Node


func _ready() -> void:
	Run.level_cleared.connect(_on_level_cleared)
	Run.start_run()
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
	move_player_to_spawn()
	Run.begin_level(_level)


## the lookup lives on the player so KillPlane and this share one implementation.
func move_player_to_spawn() -> void:
	if player != null and player.has_method("respawn_from_void"):
		player.respawn_from_void()


func _on_level_cleared(_index: int, summary: Dictionary) -> void:
	if bool(summary["last"]):
		Run.advance()
		return
	## the banner is on screen while this waits, then the next level swaps in underneath it.
	await get_tree().create_timer(Run.CLEAR_PAUSE).timeout
	if Run.advance():
		_load_level()
