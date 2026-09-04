class_name FireModeIcon
extends Control

## the fire mode as a glance: one round for semi, three for auto. the word stays next to it because
## the brief asks for SEMI or AUTO by name; this is for the player who does not read mid fight.

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


## how many rounds are lit. the probe reads this; the player reads the picture.
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
		## a semi only weapon shows the two it will never fire as ghosts, so the missing F is explained
		var c := colour if i < lit else (ghost if _can_auto else Color(ghost, 0.1))
		_draw_round(at, c)


func _draw_round(at: Vector2, c: Color) -> void:
	var w := round_size.x
	var h := round_size.y
	var tip_h := h * 0.38
	## the tip: a half ellipse on top of the casing
	var pts := PackedVector2Array()
	var steps := 8
	for i in steps + 1:
		var a := PI + PI * float(i) / float(steps)
		pts.append(at + Vector2(w * 0.5 + cos(a) * w * 0.5, tip_h + sin(a) * tip_h))
	draw_colored_polygon(pts, c)
	## the casing, with a rim line near the base
	draw_rect(Rect2(at + Vector2(0.0, tip_h), Vector2(w, h - tip_h)), c)
	draw_line(at + Vector2(0.0, h - 3.5), at + Vector2(w, h - 3.5), Color(0, 0, 0, 0.45), 1.0)
