extends Node3D


const PANEL := preload("res://UI/armory_panel.gd")
const BOARD := preload("res://UI/mission_board.gd")

@onready var bench_interactable: Interactable = $Bench/Interactable
@onready var board_interactable: Interactable = $Board/Interactable

## the room is indoors: the sky's ambient light is turned down to this while it is up, and the fog off.
@export var ambient_colour := Color(0.5, 0.52, 0.58)
@export var ambient_energy := 0.4

var _panel: CanvasLayer
var _board: CanvasLayer
var _env: Environment
var _outdoors := {}


func _ready() -> void:
	_go_indoors()
	bench_interactable.interacted.connect(_on_bench)
	board_interactable.interacted.connect(func(_by: Node) -> void: _board.open())
	_panel = PANEL.new()
	add_child(_panel)
	_board = BOARD.new()
	add_child(_board)
	_board.deploy_pressed.connect(func() -> void: Armory.deploy())


func open_panel() -> void:
	_panel.open()


func _on_bench(_by: Node) -> void:
	open_panel()


func _go_indoors() -> void:
	_env = get_world_3d().environment
	if _env == null:
		return
	_outdoors = {"source": _env.ambient_light_source, "colour": _env.ambient_light_color,
		"energy": _env.ambient_light_energy, "fog": _env.fog_enabled}
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = ambient_colour
	_env.ambient_light_energy = ambient_energy
	_env.fog_enabled = false


func _exit_tree() -> void:
	if _env == null or _outdoors.is_empty():
		return
	_env.ambient_light_source = _outdoors["source"]
	_env.ambient_light_color = _outdoors["colour"]
	_env.ambient_light_energy = _outdoors["energy"]
	_env.fog_enabled = _outdoors["fog"]


func is_indoors() -> bool:
	return _env != null and _env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR and not _env.fog_enabled
