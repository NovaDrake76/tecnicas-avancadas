class_name VhsLayer
extends CanvasLayer


const SHADER := preload("res://Shaders/vhs.gdshader")
const FACE_PATH := "res://Fonts/IBMPlexMono-Medium.ttf"
const OSD := Color(0.96, 0.96, 0.9, 0.85)
const MARGIN := 44.0

## how long the tracking snow of a cut takes to settle.
@export var settle := 1.4
## seconds between two passes of the rolling band.
@export var band_period := 6.5
@export var tape := "TAPE 03"

var _rect: ColorRect
var _mat: ShaderMaterial
var _play: Label
var _clock: Label
var _stamp: Label
var _tracking := 0.0
var _band := 1.3
var _seconds := 4.0 * 60.0 + 12.0
var _blink := 0.0


func _ready() -> void:
	layer = 0
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var face := Briefing.face(FACE_PATH)
	_play = _label(root, face, 34)
	_play.text = "PLAY  >"
	_play.position = Vector2(MARGIN, MARGIN)
	_clock = _label(root, face, 26)
	_clock.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_clock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_clock.position = Vector2(MARGIN, -MARGIN - 30.0)
	_stamp = _label(root, face, 26)
	_stamp.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_stamp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stamp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stamp.text = "KIWI EMPIRE ARCHIVE  " + tape
	_stamp.position = Vector2(-MARGIN, -MARGIN - 30.0)
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	add_child(_rect)


func _label(parent: Control, face: Font, size: int) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", face)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", OSD)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(l)
	return l


func _process(delta: float) -> void:
	_tracking = maxf(0.0, _tracking - delta / settle)
	_band -= delta * 1.3 / band_period
	if _band < -0.2:
		_band = 1.2 + randf() * 0.4
	_seconds += delta
	_blink += delta
	_play.visible = fmod(_blink, 1.6) < 1.2 or _tracking > 0.0
	var whole := int(_seconds)
	@warning_ignore("integer_division")
	_clock.text = "SP  %d:%02d:%02d" % [whole / 3600, (whole / 60) % 60, whole % 60]
	_mat.set_shader_parameter("tracking", _tracking)
	_mat.set_shader_parameter("band_y", _band)


## a cut on the tape: the picture tears and snows for a moment, then settles.
func glitch() -> void:
	_tracking = 1.0


func tracking() -> float:
	return _tracking
