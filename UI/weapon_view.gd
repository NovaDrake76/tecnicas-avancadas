extends Control

## a weapon rendered on its own, side on, in a viewport with its own world: the bench's picture of the
## gun. it takes the MODEL node out of the weapon scene and never lets the Gun script run, so nothing
## here joins the weapon group, fires, or prints a config. the part anchors come along for the callouts.

@export var sway_degrees := 6.0
@export var sway_period := 7.0
@export var margin := 1.25

var _viewport: SubViewport
var _rect: TextureRect
var _camera: Camera3D
var _pivot: Node3D
var _model: Node3D
var _anchors := {}
var _extent := Vector2(0.3, 0.15)
var _t := 0.0
var _model_name := ""

const SCENES := {
	"M4A1": "res://Guns/gun/gun.tscn",
	"M870": "res://Guns/gun/m870.tscn",
	"M1911": "res://Guns/gun/m1911.tscn",
	"G18C": "res://Guns/gun/g18c.tscn",
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.size = Vector2i(maxi(int(size.x), 64), maxi(int(size.y), 64))
	add_child(_viewport)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0, 0, 0, 0)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.8)
	env.environment.ambient_light_energy = 0.55
	_viewport.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 40, 0)
	key.light_energy = 1.6
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, -140, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.9, 0.55, 0.45)
	_viewport.add_child(rim)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	## the muzzle is -z in gun space. a camera on +x looking back at the origin puts -z on screen right,
	## so every weapon points the same way the reference sheet does.
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.05
	_camera.far = 10.0
	_viewport.add_child(_camera)
	_camera.look_at_from_position(Vector3(3.0, 0.0, 0.0), Vector3.ZERO, Vector3.UP)

	_rect = TextureRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	## the texture follows the control, never the other way round, or a card would grow to its picture
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.texture = _viewport.get_texture()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	if _viewport == null:
		return
	_viewport.size = Vector2i(maxi(int(size.x), 64), maxi(int(size.y), 64))
	_fit()


func _process(delta: float) -> void:
	if _model == null:
		return
	_t += delta
	_pivot.rotation.y = deg_to_rad(sway_degrees) * sin(_t * TAU / sway_period)


func model_name() -> String:
	return _model_name


## puts a weapon on the turntable by model name. anything that was there is gone.
func show_model(model: String) -> void:
	if model == _model_name and _model != null:
		return
	for c in _pivot.get_children():
		c.queue_free()
	_model = null
	_anchors.clear()
	_model_name = model
	if not SCENES.has(model):
		return
	var scene := load(SCENES[model]) as PackedScene
	if scene == null:
		return
	var gun := scene.instantiate()
	var body := gun.get_node_or_null("Model") as Node3D
	var anchors := gun.get_node_or_null("Anchors") as Node3D
	if body == null:
		gun.free()
		return
	gun.remove_child(body)
	if anchors != null:
		gun.remove_child(anchors)
	gun.free()
	_model = Node3D.new()
	_pivot.add_child(_model)
	_model.add_child(body)
	if anchors != null:
		_model.add_child(anchors)
		for a in anchors.get_children():
			if a is Node3D:
				_anchors[a.name] = a
	var bounds := MagazinePickup.mesh_bounds(_model)
	_model.position = -bounds.get_center()
	_extent = Vector2(bounds.size.z, bounds.size.y)
	_fit()


func _fit() -> void:
	if _camera == null:
		return
	## orthographic size is the vertical extent. a long gun is fitted by its length over the aspect,
	## a tall one (a pistol) by its height, whichever asks for more.
	var aspect := size.x / maxf(size.y, 1.0)
	_camera.size = maxf(_extent.x * margin / maxf(aspect, 0.01), _extent.y * margin)


func anchor_names() -> Array:
	return _anchors.keys()


## where a part sits on the picture, in this control's own pixels. Vector2(-1, -1) if there is none.
func anchor_point(part: String) -> Vector2:
	if not _anchors.has(part) or _camera == null:
		return Vector2(-1, -1)
	var node := _anchors[part] as Node3D
	var p := _camera.unproject_position(node.global_position)
	var ratio := size / Vector2(_viewport.size)
	return p * ratio
