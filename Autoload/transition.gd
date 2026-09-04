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
## the bird runs ABOVE the word, not across it. both boxes hang off the bottom right corner, and the
## kiwi's floor sits clear of the label's ceiling so they can never share a pixel.
const KIWI_BOX := Rect2(-340.0, -320.0, 260.0, 200.0)
const LABEL_BOX := Rect2(-340.0, -104.0, 260.0, 52.0)

var _rect: ColorRect
var _label: Label
var _tween: Tween
var _kiwi: Node3D
var _kiwi_view: Control
var _clip := ""
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
	_corner(_label, LABEL_BOX)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.add_child(_label)

	_kiwi_view = _build_kiwi()
	if _kiwi_view != null:
		_rect.add_child(_kiwi_view)
	visible = false


## a small viewport with the kiwi running on the spot, side on, no ai attached.
func _build_kiwi() -> Control:
	if not ResourceLoader.exists(KIWI_SCENE):
		return null
	var scene := load(KIWI_SCENE) as PackedScene
	if scene == null:
		return null
	var holder := Control.new()
	_corner(holder, KIWI_BOX)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(KIWI_BOX.size)
	## the curtain starts hidden, and a viewport that only draws WHEN_VISIBLE never woke up again.
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0, 0, 0, 0)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.5
	## without tonemapping the lit side clips straight to white and the vertex colours are lost again.
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.0
	vp.add_child(sun)
	var kiwi := scene.instantiate() as Node3D
	vp.add_child(kiwi)
	## the glb ships its colours as VERTEX data with the flag off, so raw it renders white.
	Kiwi.enable_vertex_colors(kiwi)
	## turned to run towards the word rather than away from it. the BIRD is turned, not the camera,
	## so the sun keeps lighting the side we are looking at.
	kiwi.rotation_degrees.y = 180.0
	_kiwi = kiwi
	var anim := kiwi.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim != null:
		for clip in anim.get_animation_list():
			if String(clip).to_lower().ends_with("run"):
				anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				anim.play(clip)
				_clip = String(clip)
				break
	var cam := Camera3D.new()
	## side on from +x. the angle is set outright rather than with look_at, which needs the node in the
	## tree and this whole subtree is built before it is added.
	cam.position = Vector3(1.7, 0.30, 0.0)
	cam.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	cam.fov = 34.0
	vp.add_child(cam)
	cam.make_current()
	var rect := TextureRect.new()
	rect.texture = vp.get_texture()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(rect)
	return holder


## anchors a box to the bottom right corner. the offsets are negative, so the box hangs inward from
## the corner and the numbers read as "this far from the right, this far up".
func _corner(node: Control, box: Rect2) -> void:
	node.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	node.offset_left = box.position.x
	node.offset_top = box.position.y
	node.offset_right = box.position.x + box.size.x
	node.offset_bottom = box.position.y + box.size.y


## what the loading screen built, for the probe: the running clip and whether the bird is coloured.
func kiwi_clip() -> String:
	return _clip


func kiwi_is_coloured() -> bool:
	if _kiwi == null:
		return false
	for node in _kiwi.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(i) as StandardMaterial3D
			if mat == null or not mat.vertex_color_use_as_albedo:
				return false
	return true


func is_covering() -> bool:
	return visible and _rect.modulate.a >= 0.99


func is_busy() -> bool:
	return _busy


## fade to black. returns once the screen is fully covered.
func cover() -> void:
	## the world goes quiet behind the curtain, the way it goes dark
	Sfx.set_gain(&"SFX", &"curtain", -14.0)
	Sfx.set_gain(&"Ambience", &"curtain", -14.0)
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
	Sfx.set_gain(&"SFX", &"curtain", 0.0)
	Sfx.set_gain(&"Ambience", &"curtain", 0.0)
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
