class_name HudStyle
extends RefCounted


const T_HERO := 96
const T_VALUE := 40
const T_UNIT := 28
const T_LABEL := 23
const T_MICRO := 20

const FACE := preload("res://Fonts/IBMPlexSansCondensed-SemiBold.ttf")
const FACE_HERO := preload("res://Fonts/IBMPlexSansCondensed-Bold.ttf")

const BRIGHT := Color(0.95, 0.97, 0.92)
const DIM := Color(0.78, 0.85, 0.82, 0.8)
const FAINT := Color(0.78, 0.85, 0.82, 0.5)
const HOT := Color(1.0, 0.82, 0.3)
const ALERT := Color(1.0, 0.38, 0.32)
const OK := Color(0.55, 0.85, 0.6)
const INK := Color(0.0, 0.0, 0.0, 0.8)


static func outline_for(size: int) -> int:
	return maxi(4, int(round(float(size) * 0.11)))


static func tune(label: Label, size: int, colour: Color) -> Label:
	label.add_theme_font_override("font", FACE_HERO if size >= T_VALUE else FACE)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", outline_for(size))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
