class_name MagazineCheck
extends Control


@export var colour := Color(0.95, 0.97, 0.92)
@export var dim := Color(0.78, 0.85, 0.82, 0.8)
@export var faint := Color(0.78, 0.85, 0.82, 0.4)
@export var empty_colour := Color(1.0, 0.38, 0.32)
@export var backing := Color(0.0, 0.0, 0.0, 0.8)
## where the count sits, as fractions of the screen: beside the magazine held up in the hand.
@export var count_at := Vector2(0.40, 0.58)
## where the pockets row sits, as a fraction of the screen height.
@export_range(0.5, 0.95) var pockets_height := 0.84
## the magazine in the weapon, drawn bigger than the ones in the pockets.
@export var held_box := Vector2(42.0, 74.0)
@export var pocket_box := Vector2(26.0, 46.0)

var _gun: Gun
var _pouch: MagazinePouch
var _showing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_for(gun: Gun, pouch: MagazinePouch) -> void:
	_gun = gun
	_pouch = pouch
	_showing = gun != null
	queue_redraw()


func hide_check() -> void:
	_showing = false
	queue_redraw()


func is_showing() -> bool:
	return _showing and _gun != null and is_instance_valid(_gun)


func count_shown() -> int:
	if not is_showing() or _pouch == null:
		return 0
	return _pouch.magazines(_gun.accepted_mag).size()


## how full the magazine in the weapon is DRAWN, which is what makes the icon say something the
## number does not have to.
func held_fill() -> float:
	if not is_showing() or _gun.magazine == null:
		return 0.0
	return clampf(float(_gun.magazine.count) / float(maxi(_gun.magazine.capacity, 1)), 0.0, 1.0)


func _process(_delta: float) -> void:
	if is_showing():
		queue_redraw()


func _draw() -> void:
	if not is_showing():
		return
	var mag: Magazine = _gun.magazine
	var at := Vector2(size.x * count_at.x, size.y * count_at.y)
	var tint := colour if mag != null and mag.count > 0 else empty_colour
	if mag != null:
		MagGlyph.draw_on(self, at - held_box * 0.5, held_box, held_fill(), tint, backing, 2.0)
	var text := "%d / %d" % [mag.count, mag.capacity] if mag != null else "NO MAGAZINE"
	_text(at + Vector2(held_box.x * 0.5 + 16.0, 12.0), text, HudStyle.T_VALUE, tint, HudStyle.FACE_HERO)
	if mag != null:
		_text(at + Vector2(held_box.x * 0.5 + 16.0, 36.0), "%.2f g" % mag.mass_grams(), HudStyle.T_MICRO, faint, HudStyle.FACE)

	var spares: Array[Magazine] = _pouch.magazines(_gun.accepted_mag) if _pouch != null else []
	var cx := size.x * 0.5
	var row_y := size.y * pockets_height
	var caption := "POCKETS   x%d" % spares.size() if not spares.is_empty() else "POCKETS EMPTY"
	_text_centred(Vector2(cx, row_y - 12.0), caption, HudStyle.T_MICRO, faint, HudStyle.FACE)
	if spares.is_empty():
		return
	var gap := pocket_box.x + 18.0
	var left := cx - (float(spares.size() - 1) * gap) * 0.5 - pocket_box.x * 0.5
	for i in spares.size():
		var corner := Vector2(left + float(i) * gap, row_y)
		var n: int = spares[i].count
		var shade := colour if n > 0 else empty_colour
		MagGlyph.draw_on(self, corner, pocket_box, float(n) / float(maxi(spares[i].capacity, 1)), shade, backing)
		_text_centred(corner + Vector2(pocket_box.x * 0.5, pocket_box.y + 22.0), "%d" % n, HudStyle.T_MICRO,
			dim if n > 0 else empty_colour, HudStyle.FACE)


func _text(at: Vector2, text: String, font_size: int, tint: Color, face: Font) -> void:
	draw_string_outline(face, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, HudStyle.outline_for(font_size), HudStyle.INK)
	draw_string(face, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)


func _text_centred(at: Vector2, text: String, font_size: int, tint: Color, face: Font) -> void:
	var w := 400.0
	var from := at - Vector2(w * 0.5, 0.0)
	draw_string_outline(face, from, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, HudStyle.outline_for(font_size), HudStyle.INK)
	draw_string(face, from, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, tint)
