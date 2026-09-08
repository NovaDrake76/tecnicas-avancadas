class_name FireModeIcon
extends Control


@export var colour := Color(1.0, 0.78, 0.35)
@export var ghost := Color(1.0, 0.78, 0.35, 0.22)
@export var round_size := Vector2(7.0, 18.0)
@export var gap := 3.0

var _mode: Gun.FireMode = Gun.FireMode.SEMI
var _can_auto := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(round_size.x * 3.0 + gap * 2.0, round_size.y)


func set_state(mode: Gun.FireMode, auto_allowed: bool) -> void:
	_mode = mode
	_can_auto = auto_allowed
	queue_redraw()


func bullets() -> int:
	return 3 if _mode == Gun.FireMode.AUTO else 1


func can_auto() -> bool:
	return _can_auto


func _draw() -> void:
	var lit := bullets()
	var total := 3
	var width := round_size.x * total + gap * (total - 1)
	var x0 := size.x - width
	var y0 := (size.y - round_size.y) * 0.5
	for i in total:
		var at := Vector2(x0 + i * (round_size.x + gap), y0)
		var c := colour if i < lit else (ghost if _can_auto else Color(ghost, 0.1))
		_draw_round(at, c)


func _draw_round(at: Vector2, c: Color) -> void:
	RoundGlyph.draw_on(self, at, round_size, c)


## the shape one of its rounds is, so anything else claiming to draw the same round can be checked against it.
func round_points() -> PackedVector2Array:
	return RoundGlyph.outline(Vector2.ZERO, round_size)
