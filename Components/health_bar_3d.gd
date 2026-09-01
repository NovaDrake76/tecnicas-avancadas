class_name HealthBar3D
extends Node3D

## a world space bar built from two unshaded billboard quads at real world size.
## it appears when the owner is damaged and hides again after hide_after seconds, 0 means never hide.

const COLOR_HARM := Color(0.85, 0.25, 0.25)
const COLOR_GAIN := Color(0.35, 0.8, 0.45)
const COLOR_BACK := Color(0.05, 0.06, 0.06, 0.75)

@export var hide_after := 3.0
@export var width := 1.1
@export var height := 0.11
@export var offset := Vector3(0, 2.2, 0)

var _fill: MeshInstance3D
var _back: MeshInstance3D
var _fill_mat: StandardMaterial3D
var _timer := 0.0
var _ratio := 1.0


func _ready() -> void:
	position = offset
	_back = _quad(COLOR_BACK, 0.0)
	_fill = _quad(COLOR_HARM, 0.001)
	_fill_mat = _fill.material_override as StandardMaterial3D
	visible = hide_after <= 0.0


func _quad(col: Color, z: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	## no fixed_size here, on geometry that flag scales the bar up with distance instead of keeping it legible.
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.position.z = z
	add_child(mi)
	return mi


## drive it from a Health component, this is all a caller has to do.
func track(h: Health) -> void:
	if h == null:
		return
	h.health_changed.connect(func(current: float, maximum: float) -> void:
		set_ratio(current / maxf(maximum, 0.001)))
	set_ratio(h.current / maxf(h.max_health, 0.001))
	if hide_after > 0.0:
		visible = false


func set_ratio(r: float) -> void:
	_ratio = clampf(r, 0.0, 1.0)
	if _fill:
		## scale from the left edge, a centred half bar just looks like a small full one.
		_fill.scale.x = maxf(_ratio, 0.0001)
		_fill.position.x = -width * 0.5 * (1.0 - _ratio)
	if _fill_mat:
		_fill_mat.albedo_color = COLOR_HARM.lerp(COLOR_GAIN, _ratio)
	if hide_after > 0.0:
		visible = _ratio > 0.0
		_timer = hide_after


func _process(delta: float) -> void:
	if hide_after <= 0.0 or not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		visible = false
