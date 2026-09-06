@tool
class_name PatrolRoute
extends Node3D


## true walks A B C A B C; false walks A B C B A B C, which is what a corridor or a wall wants.
@export var loop := true
## seconds a bird stands at each stop before moving on.
@export var dwell := 4.0
## how much that varies, each way.
@export var dwell_jitter := 1.5
## 0 means the bird's own walk_speed.
@export var speed := 0.0
## the line drawn in the editor, so a route can be laid out by eye.
@export var show_in_editor := true

var _drawn: MeshInstance3D
var _was: PackedVector3Array


func _ready() -> void:
	add_to_group("patrol_route")
	if Engine.is_editor_hint():
		set_process(true)


func points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for child in get_children():
		var node := child as Node3D
		if node != null and node != _drawn:
			out.append(node.global_position)
	return out


func stops() -> int:
	return points().size()


func next_index(from: int, direction: int) -> Array:
	var total := stops()
	if total <= 1:
		return [0, direction]
	if loop:
		return [(from + 1) % total, 1]
	var step := 1 if direction >= 0 else -1
	var want := from + step
	if want >= total:
		return [maxi(total - 2, 0), -1]
	if want < 0:
		return [mini(1, total - 1), 1]
	return [want, step]


func nearest_index(to: Vector3) -> int:
	var all := points()
	var best := 0
	var near := INF
	for i in all.size():
		var d := all[i].distance_to(to)
		if d < near:
			near = d
			best = i
	return best


func point_at(index: int) -> Vector3:
	var all := points()
	if all.is_empty():
		return global_position
	return all[clampi(index, 0, all.size() - 1)]


func wait_time() -> float:
	return maxf(dwell + randf_range(-dwell_jitter, dwell_jitter), 0.0)


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var now := points()
	if now == _was:
		return
	_was = now
	_redraw(now)


func _redraw(all: PackedVector3Array) -> void:
	if _drawn != null and is_instance_valid(_drawn):
		_drawn.queue_free()
		_drawn = null
	if not show_in_editor or all.size() < 2:
		return
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.4, 0.95, 0.6)
	material.vertex_color_use_as_albedo = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for point in all:
		mesh.surface_add_vertex(to_local(point))
	if loop:
		mesh.surface_add_vertex(to_local(all[0]))
	mesh.surface_end()
	_drawn = MeshInstance3D.new()
	_drawn.mesh = mesh
	add_child(_drawn)
