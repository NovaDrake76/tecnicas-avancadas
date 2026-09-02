extends CanvasLayer

## the curtain between scenes: a quick fade to black, "Loading..." bottom right with a kiwi running in
## place, and a fade back once the next scene has settled. every swap goes through cover() and
## uncover(), so a level never pops in half built. headless has no frames to fade, so there it is instant.

signal covered
signal uncovered

@export var fade_time := 0.3
## the curtain stays down at least this long, so the kiwi is seen and the cut never flickers.
@export var min_black := 0.55

const KIWI_SCENE := "res://Models/kiwi.glb"

var _rect: ColorRect
var _label: Label
var _kiwi_view: Control
var _tween: Tween
var _covered_at := 0.0
var _busy := false


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0.02, 0.02, 0.02)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	add_child(_rect)

	_label = Label.new()
	_label.text = "Loading..."
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.84))
	_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.position = Vector2(-72.0 - 190.0, -64.0 - 40.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.add_child(_label)

	_kiwi_view = _build_kiwi()
	if _kiwi_view != null:
		_rect.add_child(_kiwi_view)
	visible = false


## a small viewport with the kiwi running on the spot, side on, no ai attached.
func _build_kiwi() -> Control:
	if DisplayServer.get_name() == "headless" or not ResourceLoader.exists(KIWI_SCENE):
		return null
	var scene := load(KIWI_SCENE) as PackedScene
	if scene == null:
		return null
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	holder.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.size = Vector2(240, 180)
	holder.position = Vector2(-60.0 - 240.0, -40.0 - 180.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(240, 180)
	holder.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0, 0, 0, 0)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.environment.ambient_light_energy = 0.7
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.4
	vp.add_child(sun)
	var kiwi := scene.instantiate() as Node3D
	vp.add_child(kiwi)
	var anim := kiwi.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim != null:
		for name in anim.get_animation_list():
			if String(name).to_lower().ends_with("run"):
				anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR
				anim.play(name)
				break
	var cam := Camera3D.new()
	vp.add_child(cam)
	## the kiwi faces -z; from +x its nose points to screen right, running towards the label
	cam.look_at_from_position(Vector3(2.4, 0.5, 0.0), Vector3(0.0, 0.42, 0.0), Vector3.UP)
	cam.fov = 32.0
	var rect := TextureRect.new()
	rect.texture = vp.get_texture()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(rect)
	return holder


func is_covering() -> bool:
	return visible and _rect.modulate.a >= 0.99


func is_busy() -> bool:
	return _busy


## fade to black. returns once the screen is fully covered.
func cover() -> void:
	_busy = true
	visible = true
	if _instant():
		_rect.modulate.a = 1.0
	else:
		_kill()
		_tween = create_tween()
		_tween.tween_property(_rect, "modulate:a", 1.0, fade_time)
		await _tween.finished
	_covered_at = Time.get_ticks_msec() / 1000.0
	covered.emit()


## fade back in. waits out min_black first, so a fast load still shows the curtain for a beat.
func uncover() -> void:
	if not visible:
		_busy = false
		return
	if not _instant():
		var held := Time.get_ticks_msec() / 1000.0 - _covered_at
		if held < min_black:
			await get_tree().create_timer(min_black - held, true).timeout
		_kill()
		_tween = create_tween()
		_tween.tween_property(_rect, "modulate:a", 0.0, fade_time)
		await _tween.finished
	_rect.modulate.a = 0.0
	visible = false
	_busy = false
	uncovered.emit()


func _instant() -> bool:
	return DisplayServer.get_name() == "headless"


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
