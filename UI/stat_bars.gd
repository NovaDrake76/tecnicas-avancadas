extends VBoxContainer


const STATS := [
	["v0", "VELOCITY", "%.0f m/s", 200.0, false],
	["cadence", "CADENCE", "%.1f BB/s", 25.0, false],
	["reach", "REACH", "%.0f m", 80.0, false],
	["impact", "IMPACT @30 m", "%.2f J", 0.5, false],
	["time", "FLIGHT TO 30 m", "%.2f s", 0.6, true],
]
const GAIN := Color(0.45, 0.85, 0.5)
const LOSS := Color(0.95, 0.4, 0.35)

var _current := {}
var _preview := {}
var _rows := {}


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for spec in STATS:
		var key := String(spec[0])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var caption := Label.new()
		caption.text = String(spec[1])
		caption.custom_minimum_size = Vector2(150, 0)
		caption.add_theme_font_size_override("font_size", 13)
		caption.add_theme_color_override("font_color", MenuStyle.DIM)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(caption)
		var bar := Control.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size = Vector2(0, 12)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.draw.connect(_draw_bar.bind(key))
		row.add_child(bar)
		var value := Label.new()
		value.custom_minimum_size = Vector2(190, 0)
		value.add_theme_font_size_override("font_size", 15)
		value.add_theme_color_override("font_color", MenuStyle.BRIGHT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(value)
		_rows[key] = {"bar": bar, "value": value, "spec": spec}


func set_current(stats: Dictionary) -> void:
	_current = stats
	_preview = {}
	_redraw()


func set_preview(stats: Dictionary) -> void:
	_preview = stats
	_redraw()


func current() -> Dictionary:
	return _current


func preview() -> Dictionary:
	return _preview


func _redraw() -> void:
	for key in _rows:
		var r: Dictionary = _rows[key]
		var spec: Array = r["spec"]
		var fmt := String(spec[2])
		var now := float(_current.get(key, 0.0))
		var label := r["value"] as Label
		if _preview.is_empty() or not _preview.has(key):
			label.text = fmt % now
			label.add_theme_color_override("font_color", MenuStyle.BRIGHT)
		else:
			var next := float(_preview[key])
			label.text = (fmt % now) + "  >  " + (fmt % next)
			label.add_theme_color_override("font_color", _delta_colour(key, now, next))
		(r["bar"] as Control).queue_redraw()


func _delta_colour(key: String, now: float, next: float) -> Color:
	var spec: Array = _rows[key]["spec"]
	var less_is_better: bool = spec[4]
	if is_equal_approx(now, next):
		return MenuStyle.BRIGHT
	var better := (next < now) if less_is_better else (next > now)
	return GAIN if better else LOSS


func _draw_bar(key: String) -> void:
	var r: Dictionary = _rows[key]
	var bar := r["bar"] as Control
	var spec: Array = r["spec"]
	var full := float(spec[3])
	var w := bar.size.x
	var h := bar.size.y
	bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(1, 1, 1, 0.07), true)
	var now := clampf(float(_current.get(key, 0.0)) / full, 0.0, 1.0)
	if _preview.is_empty() or not _preview.has(key):
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(w * now, h)), MenuStyle.BRIGHT, true)
		return
	var next := clampf(float(_preview[key]) / full, 0.0, 1.0)
	var colour := _delta_colour(key, float(_current.get(key, 0.0)), float(_preview[key]))
	var keep := minf(now, next)
	bar.draw_rect(Rect2(Vector2.ZERO, Vector2(w * keep, h)), MenuStyle.BRIGHT, true)
	if next > now:
		bar.draw_rect(Rect2(Vector2(w * now, 0.0), Vector2(w * (next - now), h)), colour, true)
	elif now > next:
		bar.draw_rect(Rect2(Vector2(w * next, 0.0), Vector2(w * (now - next), h)), Color(colour, 0.75), true)
