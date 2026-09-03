extends CanvasLayer

## the tactical board: every mission as a card with its picture, the one selected shown large with its
## brief, par and best score, and DEPLOY. locked missions say how many clears they still need. the
## rule lives in Run; this screen only draws it. the player is frozen underneath like at the bench.

signal deploy_pressed
signal closed

const BG := Color(0.04, 0.042, 0.04)

var _root: Control
var _left: VBoxContainer
var _right: VBoxContainer
var _points_l: Label
var _message: Label
var _deploy_btn: Button
var _message_tween: Tween
var _selected := 0
var _player: Node


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("mission_board")
	visible = false

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 32)
	_root.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	margin.add_child(page)

	var head := HBoxContainer.new()
	page.add_child(head)
	var title_col := VBoxContainer.new()
	head.add_child(title_col)
	MenuStyle.sheet_text(title_col, "MISSIONS", 58, MenuStyle.BRIGHT)
	MenuStyle.sheet_text(title_col, "COMPLETE ANY MISSION TO OPEN THE NEXT ONE", 13, MenuStyle.DIM)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	var wallet := VBoxContainer.new()
	head.add_child(wallet)
	_points_l = MenuStyle.sheet_text(wallet, "", 44, MenuStyle.HOT)
	_points_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_message = MenuStyle.sheet_text(wallet, "", 15, MenuStyle.ACCENT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 48)
	page.add_child(body)
	var left_scroll := MenuStyle.sheet_scroller(body, 0.42)
	_left = MenuStyle.sheet_column(left_scroll)
	var right_scroll := MenuStyle.sheet_scroller(body, 0.58)
	_right = MenuStyle.sheet_column(right_scroll)

	var foot := HBoxContainer.new()
	page.add_child(foot)
	MenuStyle.sheet_solid(foot, "BACK TO THE RANGE", close).set_meta(UiSfx.QUIET, true)
	var foot_fill := Control.new()
	foot_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(foot_fill)
	_deploy_btn = MenuStyle.sheet_solid(foot, "DEPLOY", _on_deploy, true)
	_deploy_btn.set_meta(UiSfx.QUIET, true)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible


func selected() -> int:
	return _selected


func open() -> void:
	if visible:
		return
	_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		_player.process_mode = Node.PROCESS_MODE_DISABLED
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	## the cursor is this screen's until it closes; the player will not take it back on a focus-in
	add_to_group("holds_mouse")
	visible = true
	## the mission after the furthest one cleared, if it is open: the one you are most likely here to
	## play. a fresh run lands on the first.
	_selected = Run.suggested_level()
	_refresh()


func close(silent := false) -> void:
	if not visible:
		return
	if not silent:
		UiSfx.play("back")
	remove_from_group("holds_mouse")
	visible = false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.visible = true
	if _player != null and is_instance_valid(_player):
		_player.process_mode = Node.PROCESS_MODE_INHERIT
	if DisplayServer.window_is_focused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func select(index: int) -> void:
	if index < 0 or index >= Run.level_count():
		return
	if index != _selected:
		UiSfx.play("switch")
	_selected = index
	_refresh()


## deploys into the selected mission. a locked one is refused with what it still needs.
func deploy() -> bool:
	if not Run.select_level(_selected):
		_say("Locked. Complete %d more mission%s first." % [Run.unlock_needs(_selected), "" if Run.unlock_needs(_selected) == 1 else "s"])
		return false
	UiSfx.play("deploy")
	close(true)
	deploy_pressed.emit()
	return true


func _on_deploy() -> void:
	deploy()


func _say(text: String) -> void:
	UiSfx.play("error")
	_message.text = text
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message.modulate.a = 1.0
	_message_tween = create_tween()
	_message_tween.tween_interval(2.4)
	_message_tween.tween_property(_message, "modulate:a", 0.0, 0.6)


func _refresh() -> void:
	if not visible:
		return
	MenuStyle.sheet_clear(_left)
	MenuStyle.sheet_clear(_right)
	_points_l.text = "$%s" % MenuStyle.thousands(Armory.points)
	MenuStyle.sheet_section(_left, "OPERATIONS")
	for i in Run.level_count():
		var entry: Dictionary = Run.LEVELS[i]
		var unlocked: bool = Run.is_unlocked(i)
		var card := MenuStyle.sheet_card(_left, i == _selected, select.bind(i))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		card.add_child(row)
		var pic := _picture(row, String(entry.get("image", "")), Vector2(208, 117))
		if not unlocked:
			pic.modulate = Color(0.45, 0.45, 0.45)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		row.add_child(col)
		MenuStyle.sheet_text(col, "MISSION %d" % (i + 1), 13, MenuStyle.DIM, true)
		MenuStyle.sheet_text(col, String(entry["name"]).to_upper(), 26, MenuStyle.BRIGHT if unlocked else MenuStyle.DIM, true)
		if not unlocked:
			var need: int = Run.unlock_needs(i)
			MenuStyle.sheet_text(col, "LOCKED   %d more clear%s" % [need, "" if need == 1 else "s"], 13, MenuStyle.ACCENT, true)
		elif Run.best(i) > 0:
			MenuStyle.sheet_text(col, "CLEARED   %s   BEST $%s" % [Run.grade_letter(Run.best_grade(i)), MenuStyle.thousands(Run.best(i))], 13, MenuStyle.OK, true)
		else:
			MenuStyle.sheet_text(col, "OPEN", 13, MenuStyle.ACCENT, true)

	var sel: Dictionary = Run.LEVELS[_selected]
	var open: bool = Run.is_unlocked(_selected)
	MenuStyle.sheet_text(_right, "MISSION %d   %s" % [_selected + 1, "OPEN" if open else "LOCKED"], 13, MenuStyle.ACCENT)
	MenuStyle.sheet_text(_right, String(sel["name"]), 44, MenuStyle.BRIGHT, true)
	MenuStyle.sheet_gap(_right, 6)
	var big := _picture(_right, String(sel.get("image", "")), Vector2(0, 380))
	big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not open:
		big.modulate = Color(0.5, 0.5, 0.5)
	MenuStyle.sheet_gap(_right, 10)
	MenuStyle.sheet_text(_right, String(sel.get("brief", "")), 20, MenuStyle.BRIGHT, true)
	MenuStyle.sheet_gap(_right, 14)
	MenuStyle.sheet_section(_right, "INTEL")
	MenuStyle.sheet_kv(_right, "PAR TIME", "%d:%02d" % [int(float(sel["par"])) / 60, int(float(sel["par"])) % 60])
	MenuStyle.sheet_kv(_right, "BEST GRADE", Run.grade_letter(Run.best_grade(_selected)) if Run.best(_selected) > 0 else "none yet")
	MenuStyle.sheet_kv(_right, "BEST SCORE", "$%s" % MenuStyle.thousands(Run.best(_selected)) if Run.best(_selected) > 0 else "none yet")
	MenuStyle.sheet_kv(_right, "REWARD", "the score, minus what this mission already paid")
	if not open:
		var need: int = Run.unlock_needs(_selected)
		MenuStyle.sheet_kv(_right, "UNLOCK", "complete %d more mission%s" % [need, "" if need == 1 else "s"])
	_deploy_btn.disabled = not open
	_deploy_btn.modulate.a = 1.0 if open else 0.4


func _picture(parent: Control, path: String, size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.custom_minimum_size = size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if path != "" and ResourceLoader.exists(path):
		r.texture = load(path)
	else:
		## no picture yet: a dark plate so the layout holds
		var plate := PlaceholderTexture2D.new()
		plate.size = Vector2(16, 9)
		r.texture = plate
		r.modulate = Color(0.25, 0.27, 0.25)
	parent.add_child(r)
	return r
