class_name HudStyle
extends RefCounted

## the type scale and palette of the in-game hud, in one place so the sizes talk to each other
## instead of every label picking its own. one step is roughly a third bigger than the one below it,
## which is what makes a glance land on the ammunition first and on the figures at the bottom last.
## the colours are MenuStyle's, so the hud and the menus are the same game.

## the ammunition count. the one number read mid fight, so it is the only one this big.
const T_HERO := 96
## the fire mode and the target count: read at a glance, not stared at.
const T_VALUE := 40
## the capacity, the spare count, the clock. attached to a value above them.
const T_UNIT := 28
## captions and key hints. they name a thing, they are not the thing.
const T_LABEL := 23
## the two figures the brief wants permanently on screen but the eye does not need mid fight.
const T_MICRO := 20

const BRIGHT := Color(0.95, 0.97, 0.92)
const DIM := Color(0.78, 0.85, 0.82, 0.8)
const FAINT := Color(0.78, 0.85, 0.82, 0.5)
const HOT := Color(1.0, 0.82, 0.3)
const ALERT := Color(1.0, 0.38, 0.32)
const OK := Color(0.55, 0.85, 0.6)
const INK := Color(0.0, 0.0, 0.0, 0.8)


## the outline grows with the text, or a big number gets a hairline and a small one gets a border.
static func outline_for(size: int) -> int:
	return maxi(4, int(round(float(size) * 0.11)))


## everything a hud label needs, applied in one call. the scene sets the text and the position; the
## look comes from here, so a new label cannot quietly invent a fourteenth size.
static func tune(label: Label, size: int, colour: Color) -> Label:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", outline_for(size))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
