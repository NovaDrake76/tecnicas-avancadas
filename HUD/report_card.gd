class_name ReportCard
extends Control

## the results screen. one panel: the mission, a ring that fills to the grade with the letter CLIMBING
## through the table as it goes, a bar per term so the player can see where the letter was won or lost,
## and the numbers under it. it is handed the summary and plays; it never asks Run for anything except
## the letter for a ratio, which is the one piece of the rule it has to draw.

const PANEL_SIZE := Vector2(1240, 700)
const RING_BOX := 300.0
const RING_RADIUS := 118.0
const RING_THICKNESS := 18.0
const TERMS := [["STEALTH", "grade_stealth"], ["ACCURACY", "grade_accuracy"], ["TIME", "grade_time"]]

## the ring fills over this, the bars follow one after another, and the numbers arrive last. the whole
## thing is under two seconds so Run.CLEAR_PAUSE still leaves time to read it.
const FADE_IN := 0.22
const RING_DELAY := 0.30
const RING_TIME := 1.15
const BAR_DELAY := 0.55
const BAR_STEP := 0.16
const BAR_TIME := 0.55
const FOOTER_DELAY := 1.5
## the card takes input only once it has finished playing, so the last shot's click cannot skip it
const ARM_AFTER := 2.1

signal dismissed

var ring_ratio := 0.0:
	set(value):
		ring_ratio = clampf(value, 0.0, 1.0)
		if _ring != null:
			_ring.queue_redraw()
		if _letter != null:
			var text := Run.grade_letter(ring_ratio)
			_letter.text = text
			_letter.add_theme_color_override("font_color", MenuStyle.grade_color(text))
			_percent.text = "%d%%" % int(round(ring_ratio * 100.0))

var _panel: PanelContainer
var _title: Label
var _mission: Label
var _ring: Control
var _letter: Label
var _percent: Label
var _rows: Array = []
var _stats: Array[Label] = []
var _footer: Control
var _earned: Label
var _best: Label
var _hint: Label
var _armed := false
var _tweens: Array[Tween] = []


## one term: name, a bar that fills, and the letter that bar has earned so far.
class TermRow extends HBoxContainer:
	var _bar: Control
	var _tag: Label
	var colour := Color.WHITE

	var fill := 0.0:
		set(value):
			fill = clampf(value, 0.0, 1.0)
			var text := Run.grade_letter(fill)
			colour = MenuStyle.grade_color(text)
			if _bar != null:
				_bar.queue_redraw()
			if _tag != null:
				_tag.text = text
				_tag.add_theme_color_override("font_color", colour)

	func setup(name: String) -> void:
		add_theme_constant_override("separation", 18)
		var label := Label.new()
		label.text = name
		label.custom_minimum_size = Vector2(160, 0)
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", MenuStyle.DIM)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(label)
		_bar = Control.new()
		_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_bar.custom_minimum_size = Vector2(0, 18)
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.draw.connect(_draw_bar)
		add_child(_bar)
		_tag = Label.new()
		_tag.custom_minimum_size = Vector2(74, 0)
		_tag.add_theme_font_size_override("font_size", 28)
		_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_tag)
		fill = 0.0

	func letter() -> String:
		return _tag.text if _tag != null else ""

	func _draw_bar() -> void:
		var box := Rect2(Vector2.ZERO, _bar.size)
		_bar.draw_rect(box, Color(1.0, 1.0, 1.0, 0.07), true)
		if fill > 0.001:
			_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(_bar.size.x * fill, _bar.size.y)), colour, true)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	## the world keeps playing behind the card, so it is dimmed rather than covered.
	var scrim := ColorRect.new()
	scrim.color = Color(0.0, 0.0, 0.0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -PANEL_SIZE.x * 0.5
	_panel.offset_top = -PANEL_SIZE.y * 0.5
	_panel.offset_right = PANEL_SIZE.x * 0.5
	_panel.offset_bottom = PANEL_SIZE.y * 0.5
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.055, 0.05, 0.97)
	style.border_color = MenuStyle.HAIRLINE
	style.set_border_width_all(1)
	style.content_margin_left = 56.0
	style.content_margin_right = 56.0
	style.content_margin_top = 44.0
	style.content_margin_bottom = 40.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 0)
	_panel.add_child(page)

	_title = _text(page, "", 32, MenuStyle.ACCENT)
	_mission = _text(page, "", 64, MenuStyle.BRIGHT)
	_gap(page, 26)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 56)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	body.add_child(_build_ring())
	var terms := VBoxContainer.new()
	terms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terms.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	terms.add_theme_constant_override("separation", 22)
	body.add_child(terms)
	for term in TERMS:
		var row := TermRow.new()
		terms.add_child(row)
		row.setup(String(term[0]))
		_rows.append(row)

	_gap(page, 22)
	_footer = VBoxContainer.new()
	_footer.add_theme_constant_override("separation", 0)
	page.add_child(_footer)
	_hairline(_footer)
	_gap(_footer, 20)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 24)
	_footer.add_child(stats)
	for caption in ["TARGETS", "SHOTS", "ACCURACY", "TIME", "STEALTH"]:
		_stats.append(_stat(stats, caption))
	_gap(_footer, 22)
	var money := HBoxContainer.new()
	_footer.add_child(money)
	_earned = _text(money, "", 30, MenuStyle.HOT)
	var spread := Control.new()
	spread.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money.add_child(spread)
	_best = _text(money, "", 30, MenuStyle.DIM)
	_gap(_footer, 18)
	_hint = _text(_footer, "PRESS ENTER TO RETURN TO THE ARMORY", 15, MenuStyle.DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _build_ring() -> Control:
	_ring = Control.new()
	_ring.custom_minimum_size = Vector2(RING_BOX, RING_BOX)
	_ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	_letter = Label.new()
	_letter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_letter.add_theme_font_size_override("font_size", 128)
	_letter.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_letter.add_theme_constant_override("outline_size", 10)
	_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.add_child(_letter)
	_percent = Label.new()
	_percent.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_percent.offset_top = -74.0
	_percent.offset_bottom = -40.0
	_percent.add_theme_font_size_override("font_size", 22)
	_percent.add_theme_color_override("font_color", MenuStyle.DIM)
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_percent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.add_child(_percent)
	return _ring


func _draw_ring() -> void:
	var centre := _ring.size * 0.5
	_ring.draw_arc(centre, RING_RADIUS, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.07), RING_THICKNESS, true)
	if ring_ratio <= 0.001:
		return
	## from twelve o'clock, clockwise, the way every dial the player has seen fills.
	var from := -PI * 0.5
	_ring.draw_arc(centre, RING_RADIUS, from, from + TAU * ring_ratio, 96,
		MenuStyle.grade_color(Run.grade_letter(ring_ratio)), RING_THICKNESS, true)


## the letter on the ring right now. it climbs while the ring fills, so the probe reads it at the end.
func letter() -> String:
	return _letter.text if _letter != null else ""


func term_letters() -> Array:
	var out := []
	for row in _rows:
		out.append(row.letter())
	return out


func is_showing() -> bool:
	return visible


func hide_card() -> void:
	_kill()
	_armed = false
	visible = false


func is_armed() -> bool:
	return _armed


## enter, space or the interact key once the card has played. the same path the probe takes.
func try_dismiss() -> bool:
	if not visible or not _armed:
		return false
	_armed = false
	dismissed.emit()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _armed:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		if try_dismiss():
			get_viewport().set_input_as_handled()


func heading() -> String:
	return _title.text


## fills the card in from the summary, then plays it.
func play(s: Dictionary, title: String) -> void:
	_kill()
	_title.text = title
	_mission.text = String(s.get("name", "")).to_upper()
	var seen := int(s.get("detections", 0))
	_stats[0].text = "%d / %d" % [int(s.get("targets", 0)), int(s.get("total", 0))]
	_stats[1].text = "%d" % int(s.get("shots", 0))
	_stats[2].text = "%d%%" % int(round(float(s.get("accuracy", 0.0)) * 100.0))
	_stats[3].text = "%s  (par %s)" % [_clock(float(s.get("time", 0.0))), _clock(float(s.get("par", 0.0)))]
	_stats[4].text = "undetected" if seen == 0 else "spotted by %d" % seen
	_stats[4].add_theme_color_override("font_color",
		MenuStyle.OK if seen == 0 else Color(1.0, 0.45, 0.4))
	_earned.text = "EARNED  $%s" % MenuStyle.thousands(int(s.get("gained", 0)))
	_best.text = "BEST  $%s" % MenuStyle.thousands(int(s.get("best", 0)))

	visible = true
	_armed = false
	modulate.a = 0.0
	ring_ratio = 0.0
	for row in _rows:
		row.fill = 0.0
	_footer.modulate.a = 0.0
	_hint.modulate.a = 0.0

	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 1.0, FADE_IN)
	_tweens.append(fade)

	var ring := create_tween()
	ring.tween_interval(RING_DELAY)
	ring.tween_property(self, "ring_ratio", clampf(float(s.get("grade", 0.0)), 0.0, 1.0), RING_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tweens.append(ring)

	for i in _rows.size():
		var target := clampf(float(s.get(String(TERMS[i][1]), 0.0)), 0.0, 1.0)
		var bar := create_tween()
		bar.tween_interval(BAR_DELAY + BAR_STEP * float(i))
		bar.tween_property(_rows[i], "fill", target, BAR_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tweens.append(bar)

	var tail := create_tween()
	tail.tween_interval(FOOTER_DELAY)
	tail.tween_property(_footer, "modulate:a", 1.0, 0.4)
	_tweens.append(tail)

	## the hint arrives last and breathes, so the eye lands on it after the numbers
	var arm := create_tween()
	arm.tween_interval(ARM_AFTER)
	arm.tween_callback(func() -> void: _armed = true)
	arm.tween_property(_hint, "modulate:a", 1.0, 0.4)
	arm.set_loops()
	arm.tween_property(_hint, "modulate:a", 0.45, 0.9).set_trans(Tween.TRANS_SINE)
	arm.tween_property(_hint, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	_tweens.append(arm)


## the same card without the animation, for a probe that cannot wait two seconds of tweens.
func show_now(s: Dictionary, title: String) -> void:
	play(s, title)
	_kill()
	modulate.a = 1.0
	_footer.modulate.a = 1.0
	ring_ratio = clampf(float(s.get("grade", 0.0)), 0.0, 1.0)
	for i in _rows.size():
		_rows[i].fill = clampf(float(s.get(String(TERMS[i][1]), 0.0)), 0.0, 1.0)
	_hint.modulate.a = 1.0
	_armed = true


func _kill() -> void:
	for t in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()


func _text(parent: Control, text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## a caption over its value, the shape every number on the card takes.
func _stat(parent: Control, caption: String) -> Label:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	parent.add_child(col)
	_text(col, caption, 17, MenuStyle.DIM)
	return _text(col, "", 28, MenuStyle.BRIGHT)


func _hairline(parent: Control) -> void:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = MenuStyle.HAIRLINE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)


func _gap(parent: Control, h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)


func _clock(seconds: float) -> String:
	var whole := int(round(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]
