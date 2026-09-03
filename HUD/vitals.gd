class_name Vitals
extends Control

## the player's health, drawn only while it matters: a bar bottom left that comes in when you are hurt
## and goes once you have healed, and a red rim on the screen that flashes on each hit and lingers in
## proportion to what is missing. a bar sitting at full for a whole mission is furniture, and the rim
## is what tells you that you are being hit while you are looking at something else.

const BAR_POS := Vector2(80.0, 1004.0)
const BAR_SIZE := Vector2(360.0, 10.0)
const RIM := Color(0.85, 0.08, 0.05)
const FULL := Color(0.55, 0.85, 0.6)
const LOW := Color(1.0, 0.35, 0.3)

var _health: Health
var _ratio := 1.0
var _show := 0.0
var _flash := 0.0
var _rim: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rim = TextureRect.new()
	_rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rim.stretch_mode = TextureRect.STRETCH_SCALE
	_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, Color(RIM, 0.0))
	grad.set_color(1, Color(RIM, 0.9))
	grad.add_point(0.55, Color(RIM, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 256
	tex.height = 256
	_rim.texture = tex
	_rim.modulate.a = 0.0
	add_child(_rim)


## follows a Health node. the bar owns nothing, it draws what the component says.
func watch(player: Node) -> void:
	var h := player.get_node_or_null("Health") as Health if player != null else null
	if h == null:
		return
	if _health != null and _health.health_changed.is_connected(_on_health):
		_health.health_changed.disconnect(_on_health)
		_health.damaged.disconnect(_on_damaged)
	_health = h
	_health.health_changed.connect(_on_health)
	_health.damaged.connect(_on_damaged)
	_ratio = _health.current / maxf(_health.max_health, 0.001)
	queue_redraw()


func _on_health(current: float, max_health: float) -> void:
	_ratio = current / maxf(max_health, 0.001)
	queue_redraw()


## the rim flashes in proportion to the hit. a beam arrives as many small hits per second, and a
## full flash on each would paint the whole screen red for as long as it lasts.
func _on_damaged(amount: float, _current: float) -> void:
	_flash = maxf(_flash, clampf(amount / 10.0, 0.22, 1.0))


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 3.2)
	var missing := 1.0 - _ratio
	_rim.modulate.a = clampf(_flash * 0.85 + missing * missing * 0.7, 0.0, 1.0)
	var want := 1.0 if _ratio < 0.999 else 0.0
	_show = move_toward(_show, want, delta * (6.0 if want > _show else 1.2))
	if _show > 0.0 or _flash > 0.0:
		queue_redraw()


func _draw() -> void:
	if _show <= 0.01:
		return
	var a := _show
	draw_string(get_theme_default_font(), BAR_POS + Vector2(0.0, -8.0), "HEALTH",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.72, 0.82, 0.9, 0.75 * a))
	draw_rect(Rect2(BAR_POS, BAR_SIZE), Color(0.0, 0.0, 0.0, 0.5 * a), true)
	var colour := LOW.lerp(FULL, clampf(_ratio, 0.0, 1.0))
	if _flash > 0.0:
		colour = colour.lerp(Color.WHITE, _flash * 0.6)
	draw_rect(Rect2(BAR_POS, Vector2(BAR_SIZE.x * clampf(_ratio, 0.0, 1.0), BAR_SIZE.y)), Color(colour, a), true)
	draw_rect(Rect2(BAR_POS, BAR_SIZE), Color(1.0, 1.0, 1.0, 0.25 * a), false, 1.0)


func showing() -> bool:
	return _show > 0.01


func ratio() -> float:
	return _ratio
