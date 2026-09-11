class_name Briefing
extends CanvasLayer


signal go_pressed
signal dismissed

const FACE_PATH := "res://Fonts/IBMPlexMono-Regular.ttf"
const FACE_BOLD_PATH := "res://Fonts/IBMPlexMono-Medium.ttf"
const INK := Color(0.72, 0.93, 0.80)
const DIM := Color(0.72, 0.93, 0.80, 0.5)
const HOT := Color(0.98, 0.74, 0.32)
const T_LINE := 24
const T_SMALL := 17
const T_HEAD := 20
const MARGIN := 48.0
const CONSOLE_WIDTH := 0.56
const TYPE_RATE := 45.0
const MAX_LINES := 6
const STAGGER := 0.45
const KEYS := ["view", "time", "stain", "stagger", "say", "mark", "line", "clear", "hold"]
const NZ_BOX := Rect2(-48.0, 166.0, 14.5, 13.0)
const CURSOR := "█"

## the imported font when the editor has imported it, the raw file when it has not yet: a font that
## arrived by hand is unknown to the importer until the editor's next scan.
static var FACE: Font = face(FACE_PATH)
static var FACE_BOLD: Font = face(FACE_BOLD_PATH)

var _root: Control
var _map: BriefingMap
var _head: Label
var _title: Label
var _stamp: Label
var _console: VBoxContainer
var _foot: HBoxContainer
var _key: KeyCap
var _foot_label: Label
var _index := -1
var _open := false
var _loaded := false
var _released := false
var _finished := false
var _waiting := false
var _play_id := 0
var _lines: Array[String] = []
var _dots := 0.0


static func face(path: String) -> Font:
	if ResourceLoader.exists(path):
		var imported := load(path) as Font
		if imported != null:
			return imported
	var raw := FontFile.new()
	if raw.load_dynamic_font(path) != OK:
		push_warning("briefing: cannot read %s" % path)
		return ThemeDB.fallback_font
	return raw


func _ready() -> void:
	layer = 45
	add_to_group("briefing")
	visible = false
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_map = BriefingMap.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.label_font = FACE_BOLD
	_map.label_size = T_SMALL
	_root.add_child(_map)

	_head = _label(FACE, T_HEAD, DIM)
	_head.position = Vector2(MARGIN, MARGIN)
	_root.add_child(_head)
	_title = _label(FACE_BOLD, T_LINE, INK)
	_title.position = Vector2(MARGIN, MARGIN + T_HEAD * 1.5)
	_root.add_child(_title)

	_stamp = _label(FACE_BOLD, T_HEAD, HOT)
	_stamp.text = "EYES ONLY"
	_stamp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stamp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stamp.position = Vector2(-MARGIN - 160.0, MARGIN)
	_stamp.rotation = deg_to_rad(-5.0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	box.border_color = HOT
	box.set_border_width_all(2)
	box.set_content_margin_all(6.0)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	_stamp.add_theme_stylebox_override("normal", box)
	_root.add_child(_stamp)

	_console = VBoxContainer.new()
	_console.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_console.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_console.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_console.alignment = BoxContainer.ALIGNMENT_END
	_console.add_theme_constant_override("separation", 6)
	_root.add_child(_console)

	_foot = HBoxContainer.new()
	_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_foot.add_theme_constant_override("separation", 12)
	_root.add_child(_foot)
	_key = KeyCap.new()
	_key.action = &"ui_accept"
	_key.text_size = 17
	_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_foot.add_child(_key)
	_foot_label = _label(FACE, T_SMALL, INK)
	_foot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_foot.add_child(_foot_label)
	_root.resized.connect(_layout)
	_layout()


func _label(font: Font, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


func _layout() -> void:
	var w := _root.size.x
	var h := _root.size.y
	_foot.position = Vector2(MARGIN, h - MARGIN - 32.0)
	_console.position = Vector2(MARGIN, h - MARGIN - 32.0 - 24.0 - _console.size.y)
	_console.custom_minimum_size = Vector2(w * CONSOLE_WIDTH, 0.0)
	_console.size = Vector2(w * CONSOLE_WIDTH, _console.size.y)
	_stamp.position = Vector2(w - MARGIN - _stamp.size.x, MARGIN)


func _process(delta: float) -> void:
	if not visible:
		return
	_dots += delta
	if not _loaded:
		_foot_label.text = "LOADING" + ".".repeat(1 + int(fmod(_dots * 2.0, 3.0)))
	_console.position = Vector2(MARGIN, _root.size.y - MARGIN - 32.0 - 24.0 - _console.size.y)


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not visible:
		return
	if event.is_action_pressed("ui_accept"):
		if skip():
			get_viewport().set_input_as_handled()


## main arms it before the curtain falls and presents it once the screen is black, so the sheet
## never draws over the safe house. a release that arrives in between is honoured: nothing shows.
func arm(index: int) -> void:
	_index = index
	_open = true
	_released = false
	_loaded = false
	_finished = false
	_waiting = false
	_play_id += 1
	_lines.clear()
	for child in _console.get_children():
		child.queue_free()
	_map.reset_view()
	visible = false


func present() -> void:
	if not _open or _released:
		return
	var row := Run.LEVELS[_index] as Dictionary
	_head.text = "GHOST KIWI RECON  //  MISSION %02d BRIEFING" % (_index + 1)
	_title.text = String(row.get("name", "")).to_upper()
	visible = true
	_dots = 0.0
	_refresh_footer()
	_play(Run.briefing_of(_index))


func loaded() -> void:
	_loaded = true
	_refresh_footer()


## enter. on the host it asks main to release everybody; on a client it only says this machine is
## ready, because the host decides when the mission starts.
func skip() -> bool:
	if not _open or not _loaded:
		return false
	if Net.is_host():
		go_pressed.emit()
	else:
		_waiting = true
		_refresh_footer()
	return true


func release() -> void:
	_released = true
	if _open:
		_open = false
		_play_id += 1
		visible = false
	dismissed.emit()


func is_open() -> bool:
	return _open


func is_released() -> bool:
	return _released


func is_loaded() -> bool:
	return _loaded


func is_finished() -> bool:
	return _finished


func is_waiting() -> bool:
	return _waiting


func lines() -> Array[String]:
	return _lines.duplicate()


func map() -> BriefingMap:
	return _map


func _refresh_footer() -> void:
	_key.visible = _loaded and not _waiting
	if not _loaded:
		_foot_label.text = "LOADING"
	elif _waiting:
		_foot_label.text = "READY. WAITING FOR THE HOST"
	elif not Net.is_host():
		_foot_label.text = "READY"
	elif _finished:
		_foot_label.text = "DEPLOY"
	else:
		_foot_label.text = "SKIP BRIEFING"
	_key.refresh()


func _play(script: Array) -> void:
	var id := _play_id
	for raw in script:
		if id != _play_id:
			return
		var beat := raw as Dictionary
		if bool(beat.get("clear", false)):
			_clear_lines()
		var tween: Tween = null
		if beat.has("view"):
			var v := beat["view"] as Array
			tween = _map.look_at_place(float(v[0]), float(v[1]), float(v[2]), float(beat.get("time", 2.2)))
		if beat.has("mark"):
			var m := beat["mark"] as Array
			_map.mark(float(m[0]), float(m[1]), String(m[2]), m.size() > 3 and String(m[3]) == "done")
		if beat.has("line"):
			var l := beat["line"] as Array
			_map.line(float(l[0]), float(l[1]), float(l[2]), float(l[3]))
		if beat.has("stain"):
			_stain_staggered(beat["stain"] as Array, float(beat.get("stagger", STAGGER)), id)
		if beat.has("say"):
			await _type(String(beat["say"]), id)
		if id != _play_id:
			return
		if tween != null and tween.is_running():
			await tween.finished
		if id != _play_id:
			return
		await get_tree().create_timer(float(beat.get("hold", 0.7))).timeout
	if id == _play_id:
		_finished = true
		_refresh_footer()


func _stain_staggered(ids: Array, stagger: float, id: int) -> void:
	for i in ids.size():
		if i > 0:
			await get_tree().create_timer(stagger).timeout
		if id != _play_id:
			return
		if not _map.stain(String(ids[i])):
			push_warning("briefing: the map has no region '%s'" % String(ids[i]))


func _type(text: String, id: int) -> void:
	for old in _console.get_children():
		(old as Label).add_theme_color_override("font_color", DIM)
	var line := _label(FACE, T_LINE, INK)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_console.add_child(line)
	_lines.append(text)
	while _console.get_child_count() > MAX_LINES:
		var first := _console.get_child(0)
		_console.remove_child(first)
		first.queue_free()
	var shown := 0
	while shown < text.length():
		if id != _play_id:
			return
		shown += 1
		line.text = "> " + text.substr(0, shown) + CURSOR
		if shown % 3 == 1 and text[shown - 1] != " ":
			UiSfx.play("tick")
		await get_tree().create_timer(1.0 / TYPE_RATE).timeout
	if id == _play_id:
		line.text = "> " + text


## what is wrong with a script, as sentences; nothing if it would play. a probe runs every mission's
## through it, because a misspelt key plays as silence and a short list as a crash.
static func validate(script: Array, on_map: Callable) -> Array[String]:
	var wrong: Array[String] = []
	if script.is_empty():
		wrong.append("no beats")
	for i in script.size():
		if not (script[i] is Dictionary):
			wrong.append("beat %d is not a dictionary" % i)
			continue
		var beat := script[i] as Dictionary
		for key in beat:
			if not KEYS.has(String(key)):
				wrong.append("beat %d: unknown key '%s'" % [i, key])
		if beat.has("view") and not _place(beat["view"], 3):
			wrong.append("beat %d: view is not [lat, lon, zoom]" % i)
		if beat.has("mark") and not (_place(beat["mark"], 3) and (beat["mark"] as Array).size() <= 4
				and NZ_BOX.has_point(Vector2(float(beat["mark"][0]), float(beat["mark"][1])))):
			wrong.append("beat %d: mark is not [lat, lon, label] on New Zealand" % i)
		if beat.has("line") and not (_place(beat["line"], 4) and _place((beat["line"] as Array).slice(2), 2)):
			wrong.append("beat %d: line is not [lat, lon, lat, lon]" % i)
		if beat.has("stain"):
			for r in beat["stain"] as Array:
				if not on_map.call(String(r)):
					wrong.append("beat %d: region '%s' is not on the map" % [i, r])
		if beat.has("say") and String(beat["say"]).strip_edges().is_empty():
			wrong.append("beat %d: says nothing" % i)
	return wrong


static func _place(value: Variant, at_least: int) -> bool:
	if not (value is Array) or (value as Array).size() < at_least:
		return false
	var a := value as Array
	return absf(float(a[0])) <= 90.0 and absf(float(a[1])) <= 180.0


func _clear_lines() -> void:
	_lines.clear()
	for child in _console.get_children():
		_console.remove_child(child)
		child.queue_free()
