extends Node


const POOL := 28
const RISE := 1.1
const LIFE := 0.75
const BIG_SCALE := 1.5

const COLOR_HIT := Color(0.95, 0.95, 0.92)
const COLOR_BIG := Color(1.0, 0.62, 0.12)
const COLOR_GAIN := Color(0.45, 0.85, 0.55)

var enabled := true

var _pool: Array[Label3D] = []
var _life: Array[float] = []
var _base: Array[Vector3] = []
var _scale: Array[float] = []
var _next := 0
var _host: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ensure_pool() -> void:
	var scene := get_tree().current_scene
	if scene == _host and not _pool.is_empty() and is_instance_valid(_pool[0]):
		return
	_host = scene
	_pool.clear()
	_life.clear()
	_base.clear()
	_scale.clear()
	if scene == null:
		return
	for _i in POOL:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = false
		l.fixed_size = true
		l.pixel_size = 0.0006
		l.font_size = 56
		l.outline_size = 18
		l.outline_modulate = Color(0, 0, 0, 0.85)
		l.visible = false
		scene.add_child(l)
		_pool.append(l)
		_life.append(0.0)
		_base.append(Vector3.ZERO)
		_scale.append(1.0)


func show_at(at: Vector3, text: String, color := COLOR_HIT, big := false) -> void:
	if not enabled:
		return
	_ensure_pool()
	if _pool.is_empty():
		return

	var i := _next
	for k in POOL:
		var candidate := (_next + k) % POOL
		if _life[candidate] <= 0.0:
			i = candidate
			break
	_next = (i + 1) % POOL

	var l := _pool[i]
	l.text = text
	l.modulate = color
	l.visible = true
	l.global_position = at
	_base[i] = at
	_life[i] = LIFE
	_scale[i] = BIG_SCALE if big else 1.0
	l.scale = Vector3.ONE * _scale[i]


func _process(delta: float) -> void:
	for i in _pool.size():
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		var l := _pool[i]
		if _life[i] <= 0.0:
			l.visible = false
			continue
		var t := 1.0 - _life[i] / LIFE
		l.global_position = _base[i] + Vector3.UP * (RISE * t)
		l.modulate.a = 1.0 - t * t
