extends Node3D


@onready var reel: MenuReel = $Reel
@onready var vhs: VhsLayer = $Vhs


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Fade.uncover()
	Score.menu_theme()
	reel.cut.connect(func(_index: int) -> void: vhs.glitch())
