extends CanvasLayer


signal closed

const WEAPON_VIEW := preload("res://UI/weapon_view.gd")
const STAT_BARS := preload("res://UI/stat_bars.gd")
const BG := Color(0.04, 0.042, 0.04)

const KIND_NAMES := {
	"spring": "SPRING", "motor": "MOTOR", "bbs": "BBs", "magazines": "MAGAZINES",
}
const KIND_ANCHOR := {"spring": "Spring", "motor": "Motor", "bbs": "Magazine", "magazines": "Magazine"}

enum Page { LOADOUT, WEAPON }

var _root: Control
var _crumbs: HBoxContainer
var _points_l: Label
var _next_l: Label
var _left: VBoxContainer
var _right: VBoxContainer
var _centre: Control
var _view: Control
var _callouts: Control
var _message: Label
var _message_tween: Tween

var _page := Page.LOADOUT
var _slot := 0
var _part := "spring"
var _part_cards := {}
var _player: Node
var _bars: Control
var _hush_install := false


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("armory_panel")
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
	MenuStyle.sheet_margins(margin)
	_root.add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	margin.add_child(page)

	var head := HBoxContainer.new()
	page.add_child(head)
	var title_col := VBoxContainer.new()
	title_col.add_theme_constant_override("separation", 2)
	head.add_child(title_col)
	_text(title_col, "ARMORY", 58, MenuStyle.BRIGHT)
	_crumbs = HBoxContainer.new()
	_crumbs.add_theme_constant_override("separation", 22)
	title_col.add_child(_crumbs)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	var wallet := VBoxContainer.new()
	wallet.add_theme_constant_override("separation", 0)
	head.add_child(wallet)
	_points_l = _text(wallet, "", 44, MenuStyle.HOT)
	_points_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_next_l = _text(wallet, "", 14, MenuStyle.DIM)
	_next_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_message = _text(wallet, "", 15, MenuStyle.ACCENT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 36)
	page.add_child(body)
	var left_scroll := _scroller(body, 0.32)
	_left = _scroll_column(left_scroll)

	_centre = Control.new()
	_centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_centre)
	_centre.size_flags_stretch_ratio = 0.36
	_view = WEAPON_VIEW.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.margin = 1.12
	_centre.add_child(_view)
	_callouts = Control.new()
	_callouts.set_anchors_preset(Control.PRESET_FULL_RECT)
	_callouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callouts.draw.connect(_draw_callouts)
	_centre.add_child(_callouts)

	var right_scroll := _scroller(body, 0.32)
	_right = _scroll_column(right_scroll)

	var foot := HBoxContainer.new()
	page.add_child(foot)
	_solid(foot, "BACK TO THE RANGE", close).set_meta(UiSfx.QUIET, true)
	var foot_fill := Control.new()
	foot_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(foot_fill)
	_text(foot, "MISSIONS ARE ON THE BOARD BY THE WALL", 13, MenuStyle.DIM).size_flags_vertical = Control.SIZE_SHRINK_CENTER

	Armory.changed.connect(_refresh)
	Armory.refused.connect(_say)
	Armory.bought.connect(func(_p: Part) -> void: UiSfx.play("buy"))
	Armory.part_installed.connect(func(_p: Part) -> void:
		if not _hush_install:
			UiSfx.play("install"))


func _process(_delta: float) -> void:
	if visible and _page == Page.WEAPON:
		_callouts.queue_redraw()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if _page == Page.WEAPON:
			_go(Page.LOADOUT)
		else:
			close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_player = Player.local(get_tree())
	if _player != null:
		_player.process_mode = Node.PROCESS_MODE_DISABLED
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_to_group("holds_mouse")
	visible = true
	_page = Page.LOADOUT
	_refresh()
	UiSfx.play("bench_open")


func close(silent := false) -> void:
	if not visible:
		return
	if not silent:
		UiSfx.play("bench_close")
	remove_from_group("holds_mouse")
	visible = false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.visible = true
	if _player != null and is_instance_valid(_player):
		_player.process_mode = Node.PROCESS_MODE_INHERIT
		Armory.apply_to_player(_player)
	if DisplayServer.window_is_focused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func showing() -> String:
	return "loadout" if _page == Page.LOADOUT else _selected_model()


func callout_point(part: String) -> Vector2:
	return _view.anchor_point(String(KIND_ANCHOR.get(part, "")))


func picture_size() -> Vector2:
	return _view.size


func show_weapon(slot: int, part := "") -> void:
	if part != "":
		_part = part
	_go(Page.WEAPON, slot)


func _say(text: String) -> void:
	UiSfx.play("error")
	_message.text = text
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message.modulate.a = 1.0
	_message_tween = create_tween()
	_message_tween.tween_interval(2.4)
	_message_tween.tween_property(_message, "modulate:a", 0.0, 0.6)


func _go(page: Page, slot := -1) -> void:
	_page = page
	if slot >= 0:
		_slot = slot
	_refresh()


func _selected_model() -> String:
	if _slot < Armory.loadout.size():
		return Armory.loadout[_slot]
	return ""


func _refresh() -> void:
	if not visible:
		return
	_clear(_crumbs)
	_clear(_left)
	_clear(_right)
	_part_cards.clear()
	_points_l.text = "$%s" % _thousands(Armory.points)
	_next_l.text = "NEXT   LEVEL %d   %s" % [Run.level_index + 1, String(Run.current()["name"]).to_upper()]
	_build_crumbs()
	var model := _selected_model()
	_view.show_model(model)
	match _page:
		Page.LOADOUT:
			_build_loadout_left()
			_build_platform_right(model)
		Page.WEAPON:
			_build_parts_left(model)
			_build_options_right(model)
	_callouts.queue_redraw()


func _build_crumbs() -> void:
	_crumb("LOADOUT", _page == Page.LOADOUT, func() -> void: _go(Page.LOADOUT))
	for slot in Armory.SLOTS:
		var model := Armory.loadout[slot] if slot < Armory.loadout.size() else ""
		if model == "":
			continue
		_crumb("%s   %s" % ["PRIMARY" if slot == 0 else "SECONDARY", model],
			_page == Page.WEAPON and _slot == slot, func() -> void: _go(Page.WEAPON, slot))


func _crumb(text: String, on: bool, cb: Callable) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	_crumbs.add_child(col)
	var b := Button.new()
	b.text = text
	b.flat = true
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", MenuStyle.BRIGHT if on else MenuStyle.DIM)
	b.add_theme_color_override("font_hover_color", MenuStyle.BRIGHT)
	b.add_theme_color_override("font_pressed_color", MenuStyle.BRIGHT)
	b.add_theme_color_override("font_focus_color", MenuStyle.BRIGHT)
	b.pressed.connect(cb)
	b.name = text.to_upper().replace(" ", "_")
	col.add_child(b)
	var under := ColorRect.new()
	under.custom_minimum_size = Vector2(0, 2)
	under.color = MenuStyle.ACCENT if on else Color(0, 0, 0, 0)
	col.add_child(under)


func _build_loadout_left() -> void:
	_section(_left, "WEAPONS")
	for slot in Armory.SLOTS:
		var model := Armory.loadout[slot] if slot < Armory.loadout.size() else ""
		var card := _card(_left, _slot == slot, func() -> void: _go(Page.WEAPON, slot))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		_thumb(row, model)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		row.add_child(col)
		_text(col, _kind_of(model), 13, MenuStyle.DIM, true)
		_text(col, model, 28, MenuStyle.BRIGHT, true)
		_text(col, "PRIMARY" if slot == 0 else "SECONDARY", 13, MenuStyle.ACCENT)
		var swap := _small(row, "SWAP", _cycle_slot.bind(slot))
		swap.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var for_sale: Array[Part] = []
	for p in Armory.parts_of(Part.Kind.WEAPON):
		if not Armory.owns(p.id):
			for_sale.append(p)
	if not for_sale.is_empty():
		_gap(_left, 14)
		_section(_left, "ARSENAL")
		for p in for_sale:
			var card := _card(_left, false, Callable())
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 14)
			card.add_child(row)
			_thumb(row, p.weapon_model)
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_theme_constant_override("separation", 0)
			row.add_child(col)
			_text(col, _kind_of(p.weapon_model), 13, MenuStyle.DIM, true)
			_text(col, p.title, 28, MenuStyle.BRIGHT, true)
			var buy := _small(row, "$%s" % _thousands(p.price), _buy.bind(p.id), Armory.can_afford(p.id))
			buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_gap(_left, 14)
	_section(_left, "MAGAZINES")
	for slot in Armory.SLOTS:
		var model := Armory.loadout[slot] if slot < Armory.loadout.size() else ""
		var t := _type_of(model)
		if t < 0:
			continue
		var mag_part := _magazine_part(t)
		var card := _card(_left, false, Callable())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		row.add_child(col)
		var n := int(Armory.magazines.get(t, 0))
		_text(col, "%s   %s" % [model, Ordnance.type_name(t).to_upper()], 13, MenuStyle.DIM, true)
		_text(col, "%d spare%s   %s" % [n, "" if n == 1 else "s", Armory.bb_for(t).title], 22, MenuStyle.BRIGHT, true)
		if mag_part != null:
			var b := _small(row, "Buy one more for $%s" % _thousands(mag_part.price), _buy.bind(mag_part.id), Armory.can_afford(mag_part.id))
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var for_belt: Array[Part] = []
	for p in Armory.parts_of(Part.Kind.UTILITY):
		if not bool(UtilityBelt.row(p.utility_id).get("free", false)):
			for_belt.append(p)
	if not for_belt.is_empty():
		_gap(_left, 14)
		_section(_left, "UTILITIES")
		for p in for_belt:
			var card := _card(_left, false, Callable())
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 14)
			card.add_child(row)
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_theme_constant_override("separation", 0)
			row.add_child(col)
			var n := int(Armory.utilities.get(p.utility_id, 0))
			var belt_cap := int(UtilityBelt.row(p.utility_id).get("max", 0))
			_text(col, UtilityBelt.title_of(p.utility_id), 13, MenuStyle.DIM, true)
			_text(col, "%d of %d on the belt" % [n, belt_cap], 22, MenuStyle.BRIGHT, true)
			_text(col, UtilityBelt.note_of(p.utility_id), 15, MenuStyle.DIM, true)
			var b := _small(row, "Carry one more for $%s" % _thousands(p.price), _buy.bind(p.id), Armory.can_afford(p.id))
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _build_platform_right(model: String) -> void:
	var gun := _gun_named(model)
	if gun == null:
		return
	_text(_right, "%s   %s" % ["PRIMARY" if _slot == 0 else "SECONDARY", _kind_of(model)], 13, MenuStyle.ACCENT)
	_text(_right, model, 44, MenuStyle.BRIGHT)
	_gap(_right, 10)
	_section(_right, "PLATFORM")
	_kv(_right, "MAGAZINE", "%s   %d   %.2f g" % [Ordnance.type_name(gun.accepted_mag).to_upper(), gun.ammo_capacity(), gun.equipped_mass() * 1000.0])
	_kv(_right, "ENERGY", "%.2f J" % gun.muzzle_energy())
	_kv(_right, "FIRE MODES", "SEMI / AUTO" if gun.allow_auto else "SEMI")
	_gap(_right, 14)
	_section(_right, "PERFORMANCE")
	_bars = STAT_BARS.new()
	_right.add_child(_bars)
	_bars.set_current(_stats_for(gun, {}))
	_gap(_right, 14)
	_section(_right, "PARTS")
	for key in _part_keys(model):
		_kv(_right, _installed_title(model, key), KIND_NAMES[key], true)
	_gap(_right, 14)
	var edit := _small(_right, "CONFIGURE", func() -> void: _go(Page.WEAPON))
	edit.size_flags_horizontal = Control.SIZE_SHRINK_END


func _build_parts_left(model: String) -> void:
	var back := Button.new()
	back.text = "<   LOADOUT"
	back.flat = true
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.add_theme_font_size_override("font_size", 13)
	back.add_theme_color_override("font_color", MenuStyle.DIM)
	back.add_theme_color_override("font_hover_color", MenuStyle.BRIGHT)
	back.pressed.connect(func() -> void: _go(Page.LOADOUT))
	_left.add_child(back)
	_text(_left, _kind_of(model), 13, MenuStyle.DIM)
	_text(_left, model, 44, MenuStyle.BRIGHT)
	_gap(_left, 10)
	_section(_left, "PARTS")
	var keys := _part_keys(model)
	if not _part in keys:
		_part = keys[0]
	for key in keys:
		var card := _card(_left, _part == key, _pick_part.bind(key))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		row.add_child(col)
		_text(col, KIND_NAMES[key], 13, MenuStyle.ACCENT if _part == key else MenuStyle.DIM)
		_text(col, _installed_title(model, key), 24, MenuStyle.BRIGHT, true)
		_text(col, _installed_detail(model, key), 14, MenuStyle.DIM, true)
		_part_cards[key] = card


func _build_options_right(model: String) -> void:
	var gun := _gun_named(model)
	if gun == null:
		return
	var t := gun.accepted_mag
	_text(_right, KIND_NAMES.get(_part, ""), 13, MenuStyle.ACCENT)
	match _part:
		"spring":
			_text(_right, "Stiffer spring, more energy, faster BB", 24, MenuStyle.BRIGHT, true)
			_gap(_right, 8)
			for p in Armory.parts_of(Part.Kind.SPRING, model):
				_option(model, p, p.title, "k %.0f N/m   x %.0f mm   %.2f J" % [p.spring_k, p.spring_x * 1000.0, p.energy()],
					Armory.installed_part(model, "spring") == p)
		"motor":
			_text(_right, "Faster motor, higher cadence", 24, MenuStyle.BRIGHT, true)
			_gap(_right, 8)
			for p in Armory.parts_of(Part.Kind.MOTOR, model):
				_option(model, p, p.title, "%.0f RPM   %.1f BB/s" % [p.rpm, p.rpm / (60.0 * gun.rotations_per_shot)],
					Armory.installed_part(model, "motor") == p)
		"bbs":
			_text(_right, "Heavier BB, slower and steadier", 24, MenuStyle.BRIGHT, true)
			_gap(_right, 8)
			for p in Armory.parts_of(Part.Kind.BB_LOT):
				var v := gun.muzzle_speed(p.bb_mass_kg)
				_bb_option(t, p, "%.0f m/s   %.0f fps" % [v, v * 3.28084], Armory.bb_for(t) == p)
		"magazines":
			var mag_part := _magazine_part(t)
			var n := int(Armory.magazines.get(t, 0))
			_text(_right, "Spare %s magazines" % Ordnance.type_name(t).to_lower(), 24, MenuStyle.BRIGHT, true)
			_text(_right, "%d carried, the pouch holds 4. each one is refilled with the loaded BBs at the bench." % n, 14, MenuStyle.DIM, true)
			_gap(_right, 8)
			if mag_part != null:
				var row := _row(_right)
				_text(row, mag_part.title, 20, MenuStyle.BRIGHT, true)
				_small(row, "Buy one more for $%s" % _thousands(mag_part.price), _buy.bind(mag_part.id), Armory.can_afford(mag_part.id))
	_gap(_right, 18)
	_section(_right, "PERFORMANCE")
	_bars = STAT_BARS.new()
	_right.add_child(_bars)
	_bars.set_current(_stats_for(gun, {}))


func _option(model: String, p: Part, title: String, detail: String, installed: bool) -> void:
	var row := _row(_right, _hover_part.bind(model, p))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	_text(col, title, 20, MenuStyle.HOT if installed else MenuStyle.BRIGHT, true)
	_text(col, detail, 14, MenuStyle.DIM, true)
	if installed:
		_text(row, "INSTALLED", 13, MenuStyle.ACCENT).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	elif Armory.owns(p.id):
		_small(row, "INSTALL", _install.bind(model, p.id)).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		_small(row, "$%s" % _thousands(p.price), _buy.bind(p.id), Armory.can_afford(p.id)).size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _bb_option(t: Ordnance.MagType, p: Part, detail: String, loaded: bool) -> void:
	var row := _row(_right, _hover_part.bind(_selected_model(), p))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	_text(col, p.title, 20, MenuStyle.HOT if loaded else MenuStyle.BRIGHT, true)
	_text(col, detail, 14, MenuStyle.DIM, true)
	if loaded:
		_text(row, "LOADED", 13, MenuStyle.ACCENT).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	elif Armory.owns(p.id):
		_small(row, "LOAD", _choose_bb.bind(t, p.id)).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		_small(row, "$%s" % _thousands(p.price), _buy.bind(p.id), Armory.can_afford(p.id)).size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw_callouts() -> void:
	if _page != Page.WEAPON:
		return
	var inv := _callouts.get_global_transform().affine_inverse()
	for key in _part_cards:
		var card := _part_cards[key] as Control
		if card == null or not is_instance_valid(card):
			continue
		var column := card.get_parent()
		while column != null and not column is ScrollContainer:
			column = column.get_parent()
		if column != null:
			var frame := (column as Control).get_global_rect()
			if frame.size.y < 12.0 or not frame.grow(-6.0).encloses(card.get_global_rect()):
				continue
		var anchor_name: String = KIND_ANCHOR.get(key, "")
		var target: Vector2 = _view.anchor_point(anchor_name)
		if target.x < 0.0:
			continue
		target = inv * (_view.get_global_transform() * target)
		var r := card.get_global_rect()
		var from := inv * Vector2(r.end.x, r.position.y + r.size.y * 0.5)
		var on: bool = key == _part
		var colour := MenuStyle.ACCENT if on else Color(MenuStyle.DIM, 0.35)
		var width := 2.0 if on else 1.0
		var elbow := Vector2(from.x + 28.0, from.y)
		_callouts.draw_line(from, elbow, colour, width, true)
		_callouts.draw_line(elbow, target, colour, width, true)
		_callouts.draw_circle(target, 8.0 if on else 5.0, Color(BG, 0.9))
		_callouts.draw_circle(target, 6.0 if on else 3.5, colour)
		if on:
			_callouts.draw_arc(target, 11.0, 0.0, TAU, 32, colour, 1.5, true)


func _pick_part(key: String) -> void:
	_part = key
	_refresh()


func _cycle_slot(slot: int) -> void:
	var weapons := Armory.owned_weapons()
	if weapons.is_empty():
		return
	var current := Armory.loadout[slot] if slot < Armory.loadout.size() else ""
	var at := weapons.find(current)
	for step in weapons.size():
		var candidate := weapons[(at + 1 + step) % weapons.size()]
		if candidate != current and Armory.set_slot(slot, candidate):
			_slot = slot
			return
	_say("Nothing else to carry. Buy a weapon in the arsenal.")


func _buy(id: String) -> void:
	var p := Armory.part(id)
	if p == null or not Armory.buy(id):
		return
	var model := _selected_model()
	_hush_install = true
	match p.kind:
		Part.Kind.SPRING, Part.Kind.MOTOR:
			if p.fits_weapon(model):
				Armory.install(model, id)
		Part.Kind.BB_LOT:
			var t := _type_of(model)
			if t >= 0:
				Armory.choose_bb(t, id)
		Part.Kind.WEAPON:
			Armory.set_slot(_slot, p.weapon_model)
	_hush_install = false


func buy_here(id: String) -> void:
	_buy(id)


func _stats_for(gun: Gun, over: Dictionary) -> Dictionary:
	var k := float(over.get("k", gun.spring_constant))
	var x := float(over.get("x", gun.spring_compression))
	var rpm := float(over.get("rpm", gun.motor_rpm))
	var mass := float(over.get("mass", gun.equipped_mass()))
	var energy := 0.5 * k * x * x / float(maxi(1, gun.pellets))
	var v0 := sqrt(2.0 * energy / maxf(mass, 0.00001))
	var flight := BB.flight(v0, mass, gun.hopup)
	return {
		"v0": v0,
		"cadence": rpm / (60.0 * float(maxi(1, gun.rotations_per_shot))),
		"reach": float(flight["reach"]),
		"impact": float(flight["impact"]),
		"time": float(flight["time"]),
	}


func _stats_with_part(gun: Gun, p: Part) -> Dictionary:
	var over := {}
	match p.kind:
		Part.Kind.SPRING:
			over = {"k": p.spring_k, "x": p.spring_x}
		Part.Kind.MOTOR:
			over = {"rpm": p.rpm}
		Part.Kind.BB_LOT:
			over = {"mass": p.bb_mass_kg}
	return _stats_for(gun, over)


func _hover_part(on: bool, model: String, p: Part) -> void:
	if _bars == null or not is_instance_valid(_bars):
		return
	var gun := _gun_named(model)
	if not on or gun == null:
		_bars.set_preview({})
		return
	_bars.set_preview(_stats_with_part(gun, p))


func preview_part(id: String) -> void:
	var p := Armory.part(id)
	_hover_part(p != null, _selected_model(), p)


func preview_stats() -> Dictionary:
	return _bars.preview() if _bars != null else {}


func current_stats() -> Dictionary:
	return _bars.current() if _bars != null else {}


func _install(model: String, id: String) -> void:
	Armory.install(model, id)


func _choose_bb(t: Ordnance.MagType, id: String) -> void:
	Armory.choose_bb(t, id)


func _part_keys(model: String) -> Array:
	var keys := ["spring"]
	if not Armory.parts_of(Part.Kind.MOTOR, model).is_empty():
		keys.append("motor")
	keys.append("bbs")
	keys.append("magazines")
	return keys


func _installed_title(model: String, key: String) -> String:
	match key:
		"spring", "motor":
			var p := Armory.installed_part(model, key)
			return p.title if p != null else "none"
		"bbs":
			var t := _type_of(model)
			return Armory.bb_for(t).title if t >= 0 else ""
		"magazines":
			var t := _type_of(model)
			var n := int(Armory.magazines.get(t, 0)) if t >= 0 else 0
			return "%d spare%s" % [n, "" if n == 1 else "s"]
	return ""


func _installed_detail(model: String, key: String) -> String:
	var gun := _gun_named(model)
	if gun == null:
		return ""
	match key:
		"spring":
			return "%.2f J   k %.0f N/m  x %.0f mm" % [gun.muzzle_energy(), gun.spring_constant, gun.spring_compression * 1000.0]
		"motor":
			return "%.1f BB/s   %.0f RPM" % [gun.shots_per_second(), gun.motor_rpm]
		"bbs":
			return "%.0f m/s from this spring" % gun.muzzle_speed(gun.equipped_mass())
		"magazines":
			return "%d rounds each" % gun.ammo_capacity()
	return ""


func _magazine_part(t: int) -> Part:
	for p in Armory.parts_of(Part.Kind.MAGAZINE):
		if p.mag_type == t:
			return p
	return null


func _kind_of(model: String) -> String:
	var gun := _gun_named(model)
	if gun == null:
		return ""
	match gun.accepted_mag:
		Ordnance.MagType.Rifle:
			return "ASSAULT RIFLE"
		Ordnance.MagType.Shotgun:
			return "PUMP SHOTGUN"
		Ordnance.MagType.Marksman:
			return "BOLT RIFLE"
		Ordnance.MagType.PistolHeavy:
			return "HEAVY PISTOL"
		Ordnance.MagType.PistolMachine:
			return "MACHINE PISTOL"
	return ""


func _type_of(model: String) -> int:
	var gun := _gun_named(model)
	return gun.accepted_mag if gun != null else -1


func _gun_named(model: String) -> Gun:
	var rack := get_tree().get_first_node_in_group("weapon_rack") as WeaponRack
	if rack == null:
		return null
	for g in rack.all_weapons():
		if g.weapon_model == model:
			return g
	return null


func _scroller(parent: Control, share: float) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = share
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size = Vector2(4, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.04)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(1, 1, 1, 0.18)
	for k in ["scroll", "scroll_focus"]:
		bar.add_theme_stylebox_override(k, track)
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(k, grab)
	return scroll


func _scroll_column(scroll: ScrollContainer) -> VBoxContainer:
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 18)
	scroll.add_child(pad)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	pad.add_child(col)
	return col


func _text(parent: Control, text: String, size: int, colour: Color, wrapped := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrapped:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


func _section(parent: Control, text: String) -> void:
	_gap(parent, 2)
	_text(parent, text, 13, MenuStyle.DIM)
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = MenuStyle.HAIRLINE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	_gap(parent, 4)


func _gap(parent: Control, h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)


func _kv(parent: Control, key: String, value: String, accent_value := false) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var k := _text(row, key, 14, MenuStyle.BRIGHT if accent_value else MenuStyle.DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := _text(row, value, 13 if accent_value else 17, MenuStyle.ACCENT if accent_value else MenuStyle.BRIGHT)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = MenuStyle.HAIRLINE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)


func _card(parent: Control, selected: bool, on_click: Callable) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = MenuStyle.CARD
	style.content_margin_left = 16.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	if selected:
		style.border_width_left = 3
		style.border_color = MenuStyle.ACCENT
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	if on_click.is_valid():
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				UiSfx.play("click")
				on_click.call())
		panel.mouse_entered.connect(func() -> void:
			style.bg_color = MenuStyle.CARD_HOVER
			UiSfx.play("hover"))
		panel.mouse_exited.connect(func() -> void: style.bg_color = MenuStyle.CARD)
	return col


func _row(parent: Control, on_hover := Callable()) -> HBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_bottom = 1
	style.border_color = MenuStyle.HAIRLINE
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	if on_hover.is_valid():
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		var enter := func() -> void:
			style.bg_color = Color(1, 1, 1, 0.03)
			on_hover.call(true)
		var leave := func() -> void:
			style.bg_color = Color(0, 0, 0, 0)
			on_hover.call(false)
		panel.mouse_entered.connect(enter)
		panel.mouse_exited.connect(leave)
		row.child_entered_tree.connect(func(c: Node) -> void:
			if c is BaseButton:
				c.mouse_entered.connect(enter)
				c.mouse_exited.connect(leave))
	return row


func _thumb(parent: Control, model: String) -> Control:
	var view := WEAPON_VIEW.new()
	view.custom_minimum_size = Vector2(160, 84)
	view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	view.clip_contents = true
	view.sway_degrees = 0.0
	view.margin = 1.3
	parent.add_child(view)
	view.show_model.call_deferred(model)
	return view


func _solid(parent: Control, text: String, cb: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(230, 44)
	b.add_theme_font_size_override("font_size", 16)
	var normal := StyleBoxFlat.new()
	normal.bg_color = MenuStyle.ACCENT if accent else Color(0.12, 0.125, 0.12)
	normal.content_margin_left = 24.0
	normal.content_margin_right = 24.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.95, 0.4, 0.3) if accent else Color(0.2, 0.21, 0.2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_color_override("font_color", MenuStyle.BRIGHT)
	b.add_theme_color_override("font_hover_color", MenuStyle.BRIGHT)
	b.add_theme_color_override("font_pressed_color", MenuStyle.BRIGHT)
	b.add_theme_color_override("font_focus_color", MenuStyle.BRIGHT)
	b.pressed.connect(cb)
	b.name = text.to_upper().replace(" ", "_")
	parent.add_child(b)
	return b


func _small(parent: Control, text: String, cb: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(84, 34)
	b.add_theme_font_size_override("font_size", 14)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.16, 0.165, 0.16) if enabled else Color(0.1, 0.1, 0.1)
	normal.content_margin_left = 14.0
	normal.content_margin_right = 14.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.24, 0.25, 0.24)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", normal)
	var fc := MenuStyle.BRIGHT if enabled else Color(MenuStyle.DIM, 0.45)
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", MenuStyle.BRIGHT)
	b.add_theme_color_override("font_pressed_color", MenuStyle.BRIGHT)
	b.add_theme_color_override("font_focus_color", fc)
	b.pressed.connect(cb)
	b.name = text.to_upper().replace(" ", "_")
	parent.add_child(b)
	return b


func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return out


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
