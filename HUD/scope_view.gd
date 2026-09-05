class_name ScopeView
extends Control

## looking THROUGH a telescope, which is not the same as looking down a set of iron sights with the
## camera pulled in.
##
## the first attempt just placed the eye behind the scope the way the rifle's eye sits on its sight
## groove, and it was photographed: at 24 degrees of view an 18 mm tube eight centimetres away fills
## most of the screen, so the picture was the INSIDE of the scope body. a model with no glass and no
## bore through it cannot be looked through, and no pose fixes that -- moving the eye back far enough
## to see past the tube would put it half a metre behind the weapon, which is not a viewmodel any
## more.
##
## so the scope is drawn rather than modelled, which is what every game with a telescopic sight does:
## at full magnification the weapon is taken off the screen and the sight picture is a black surround,
## a circle and a reticle. the WORLD inside the circle is the real camera at its narrow fov, so what
## is in the circle is honest -- nothing here fakes a view.
##
## it covers the world and nothing else. it is the first child of the hud, so the alert ring, the
## reload ring and the ammunition all draw on top: a player standing still with a telescope on their
## eye is the most exposed they can be, and hiding the arcs that say who has noticed them would be
## taking away the one thing they can act on.

## how much of the screen's short side the sight picture is.
const RADIUS := 0.44
## the reticle's black. not pure black, or it disappears against the surround at the edges.
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
	## the same re-find every hud element here does: quitting to the menu frees the player and the
	## scope with it, and a freed node compares equal to null.
	if _scope == null or not is_instance_valid(_scope):
		_bind()
		if _scope == null:
			return
	var want := _scope.scope_amount()
	if is_equal_approx(want, _t):
		return
	_t = want
	queue_redraw()


## for the probe: 0 when there is no telescope on the weapon or the player is not looking through it.
func amount() -> float:
	return _t


func _draw() -> void:
	if _t <= 0.01:
		return
	var middle := size * 0.5
	var radius := minf(size.x, size.y) * RADIUS
	var ink := Color(0.0, 0.0, 0.0, _t)
	## the surround is one very thick ARC rather than four rectangles round a hole: an arc is drawn
	## as a ring of that width, so a width the length of the screen covers everything outside the
	## circle including the corners, and the edge of the circle is the arc's own inner edge.
	var wide := size.length()
	draw_arc(middle, radius + wide * 0.5, 0.0, TAU, 128, ink, wide)
	## a soft edge just inside the glass, which is what a real sight picture has and what keeps the
	## hard circle from reading as a sticker over the screen.
	draw_arc(middle, radius * 0.94, 0.0, TAU, 96, Color(0.0, 0.0, 0.0, 0.35 * _t), radius * 0.12)

	var mark := Color(LINE, _t)
	draw_line(middle - Vector2(radius, 0.0), middle - Vector2(GAP, 0.0), mark, 2.0)
	draw_line(middle + Vector2(GAP, 0.0), middle + Vector2(radius, 0.0), mark, 2.0)
	draw_line(middle - Vector2(0.0, radius), middle - Vector2(0.0, GAP), mark, 2.0)
	draw_line(middle + Vector2(0.0, GAP), middle + Vector2(0.0, radius), mark, 2.0)
	## the ticks are not decoration: they are what a marksman's sight gives you over an iron one, a
	## scale to hold over with at range, and this weapon exists to be shot at range.
	var step := radius * 0.16
	for i in range(1, 5):
		var along := step * float(i)
		var tick := 7.0 if i % 2 == 0 else 4.0
		draw_line(middle + Vector2(-along, -tick), middle + Vector2(-along, tick), mark, 2.0)
		draw_line(middle + Vector2(along, -tick), middle + Vector2(along, tick), mark, 2.0)
		draw_line(middle + Vector2(-tick, along), middle + Vector2(tick, along), mark, 2.0)
	draw_circle(middle, 1.6, mark)
