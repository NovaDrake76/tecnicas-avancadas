class_name ScopeView
extends Control


const RADIUS := 0.44
const LINE := Color(0.04, 0.05, 0.04)
const GAP := 14.0

var _scope: AimScope
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bind.call_deferred()


func _bind() -> void:
	_scope = get_tree().get_first_node_in_group("aim_scope") as AimScope


func _process(_delta: float) -> void:
	## re-found, because quitting to the menu frees the player and the scope with it, and a freed node compares equal to null.
	if _scope == null or not is_instance_valid(_scope):
		_bind()
		if _scope == null:
			return
	var want := _scope.scope_amount()
	if is_equal_approx(want, _t):
		return
	_t = want
	queue_redraw()


func amount() -> float:
	return _t


func _draw() -> void:
	if _t <= 0.01:
		return
	var middle := size * 0.5
	var radius := minf(size.x, size.y) * RADIUS
	var ink := Color(0.0, 0.0, 0.0, _t)
	var wide := size.length()
	draw_arc(middle, radius + wide * 0.5, 0.0, TAU, 128, ink, wide)
	draw_arc(middle, radius * 0.94, 0.0, TAU, 96, Color(0.0, 0.0, 0.0, 0.35 * _t), radius * 0.12)

	var mark := Color(LINE, _t)
	draw_line(middle - Vector2(radius, 0.0), middle - Vector2(GAP, 0.0), mark, 2.0)
	draw_line(middle + Vector2(GAP, 0.0), middle + Vector2(radius, 0.0), mark, 2.0)
	draw_line(middle - Vector2(0.0, radius), middle - Vector2(0.0, GAP), mark, 2.0)
	draw_line(middle + Vector2(0.0, GAP), middle + Vector2(0.0, radius), mark, 2.0)
	var step := radius * 0.16
	for i in range(1, 5):
		var along := step * float(i)
		var tick := 7.0 if i % 2 == 0 else 4.0
		draw_line(middle + Vector2(-along, -tick), middle + Vector2(-along, tick), mark, 2.0)
		draw_line(middle + Vector2(along, -tick), middle + Vector2(along, tick), mark, 2.0)
		draw_line(middle + Vector2(-tick, along), middle + Vector2(tick, along), mark, 2.0)
	draw_circle(middle, 1.6, mark)
