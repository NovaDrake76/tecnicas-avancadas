extends Node3D


const PANEL := preload("res://UI/armory_panel.gd")
const BOARD := preload("res://UI/mission_board.gd")

@onready var bench_interactable: Interactable = $Bench/Interactable
@onready var board_interactable: Interactable = $Board/Interactable

var _panel: CanvasLayer
var _board: CanvasLayer


func _ready() -> void:
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
