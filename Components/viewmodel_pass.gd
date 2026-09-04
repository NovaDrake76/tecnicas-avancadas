class_name ViewmodelPass
extends Node

## everything the player is HOLDING is drawn by a second camera into its own SubViewport and
## composited over the view. That is the CS-style always-visible viewmodel, and it is here because a
## thing parked in camera space goes through the world the moment the world comes close: the weapon
## sinks into a wall the player stands against, and a carried body sinks into the floor the moment
## they crouch. The offset is fixed relative to the camera and the world is not.
##
## The alternative was switching depth testing off on the held object's materials, which is one line
## and wrong: without a depth test a model's far side draws over its near side, so a barrel shows
## through a receiver and a beak tears through a bird. A second pass has its OWN depth buffer, so the
## model still self-occludes correctly and only the WORLD is unable to cover it.
##
## The pass SHARES the level's World3D, so everything on it keeps the real lighting and the shadows
## it is standing in rather than becoming a flat cut-out; `transparent_bg` keeps everything but the
## held objects clear, so the sky never fills the composite.

## which visual layer held things are moved onto. nothing else in the game uses it.
@export_range(1, 20) var layer := 3
## the pass costs a whole second render of the scene, so it only runs while something is on it.
@export var enabled := true

var _main_cam: Camera3D
var _view: SubViewport
var _view_cam: Camera3D
var _image: TextureRect
var _mask := 0
## root -> { mesh: [layers, cast_shadow] }, so handing a thing back puts every mesh into the world
## exactly as it was found rather than at whatever the defaults happen to be.
var _held := {}


func _ready() -> void:
	add_to_group("viewmodel_pass")
	if enabled:
		## deferred: the player camera has to exist before the pass can mirror it.
		_build.call_deferred()


func mask() -> int:
	return _mask


func is_running() -> bool:
	return not _held.is_empty()


## put every mesh under this node onto the viewmodel layer. stops it casting a shadow too: it lives
## in the shared world, so a gun-shaped or bird-shaped shadow on the floor beside the player would
## give the whole trick away.
func take_over(root: Node3D) -> void:
	if not enabled or _mask == 0 or root == null or _held.has(root):
		return
	var was := {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		was[mesh] = [mesh.layers, mesh.cast_shadow]
		mesh.layers = _mask
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_held[root] = was
	_running(true)


func hand_back(root: Node3D) -> void:
	if not _held.has(root):
		return
	var was: Dictionary = _held[root]
	for mesh in was.keys():
		if is_instance_valid(mesh):
			var before: Array = was[mesh]
			mesh.layers = int(before[0])
			mesh.cast_shadow = int(before[1])
	_held.erase(root)
	_running(is_running())


## a root that was freed while it was held, so the pass does not keep rendering for a corpse that no
## longer exists.
func forget_freed() -> void:
	for root in _held.keys():
		if not is_instance_valid(root):
			_held.erase(root)
	_running(is_running())


func _build() -> void:
	if not is_inside_tree() or _view != null:
		return
	_main_cam = get_viewport().get_camera_3d()
	if _main_cam == null:
		## no camera at all: degrade to plain world rendering rather than half building the pass.
		enabled = false
		return
	_mask = 1 << (layer - 1)
	_main_cam.cull_mask &= ~_mask

	_view = SubViewport.new()
	_view.name = "ViewmodelViewport"
	_view.transparent_bg = true
	_view.handle_input_locally = false
	## the MAIN viewport owns the 3d listener; a second one would double every positional sound.
	_view.audio_listener_enable_3d = false
	_view.own_world_3d = false
	_view.world_3d = _main_cam.get_world_3d()
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_view.msaa_3d = get_viewport().msaa_3d
	_view.size = Vector2i(get_viewport().get_visible_rect().size)
	add_child(_view)

	_view_cam = Camera3D.new()
	_view_cam.name = "ViewmodelCamera"
	_view_cam.cull_mask = _mask
	_view_cam.near = _main_cam.near
	_view_cam.far = _main_cam.far
	_view.add_child(_view_cam)
	_view_cam.current = true

	## over the 3d view and UNDER the hud, which is a CanvasLayer at 1.
	var canvas := CanvasLayer.new()
	canvas.name = "ViewmodelComposite"
	canvas.layer = 0
	add_child(canvas)
	_image = TextureRect.new()
	_image.name = "ViewmodelImage"
	_image.texture = _view.get_texture()
	_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.visible = false
	canvas.add_child(_image)


func _running(on: bool) -> void:
	if _view != null:
		_view.render_target_update_mode = \
			SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if _image != null:
		_image.visible = on


## the second camera stands exactly where the first one does, with the same lens, so everything on
## the layer lands on screen where its own offset puts it and nowhere else. matching `near` is what
## keeps the aim pose honest: the rifle's stock is still clipped by the near plane while aiming,
## which is how looking through a sight works, and only WORLD geometry stops covering it.
func _process(_delta: float) -> void:
	if _view == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if cam != _main_cam:
		## quitting to the menu builds a new camera under a player that outlives it.
		_main_cam = cam
		_main_cam.cull_mask &= ~_mask
	if _view.world_3d != cam.get_world_3d():
		_view.world_3d = cam.get_world_3d()
	var screen := Vector2i(get_viewport().get_visible_rect().size)
	if _view.size != screen:
		_view.size = screen
	_view_cam.global_transform = cam.global_transform
	_view_cam.fov = cam.fov
	_view_cam.near = cam.near
	_view_cam.far = cam.far
