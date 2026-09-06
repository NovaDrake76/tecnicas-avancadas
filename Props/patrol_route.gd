@tool
class_name PatrolRoute
extends Node3D

## a walk somebody wrote down. drop this in a level, give it Marker3D children, and point a kiwi's
## `route` at it: that bird walks the stops in order, waits at each, and starts again.
##
## it exists because the birds had no patterns to learn. every kiwi picked a random point inside
## `wander_radius` and strolled to it, which looks alive and is worth nothing to a stealth player:
## watch the pattern, find the gap, move is the core loop of this entire genre, and there was no
## pattern to watch. the design writing on it is blunt -- the patrol route IS the gameplay content,
## and the level designer is the person who should be authoring it.
##
## the variation is deliberate and it is the other half of the same lesson. MGSV is the reference
## everyone cites for the balance: routes consistent enough to be read, with enough jitter in the
## waits that a player cannot run a stopwatch on them. `dwell_jitter` is that and nothing more --
## the ORDER never varies, or there would be nothing to learn.
##
## every bird is still free to do something else. `Kiwi.duty` is the choice, per bird: WANDER is
## what the whole field used to do, FIXED is a sentry that holds one spot, ROUTE is this. A level
## wants all three -- a mortar crew never leaves its tube, a tower sentry never leaves its tower,
## and the yard is where a patrol is worth walking.

## true walks A B C A B C; false walks A B C B A B C, which is what a corridor or a wall wants.
@export var loop := true
## seconds a bird stands at each stop before moving on.
@export var dwell := 4.0
## how much that varies, each way. the route stays readable, the stopwatch does not work.
@export var dwell_jitter := 1.5
## 0 means the bird's own walk_speed. set it to make one patrol brisker than another.
@export var speed := 0.0
## the line drawn in the editor, so a route can be laid out by eye. never built in a running game.
@export var show_in_editor := true

var _drawn: MeshInstance3D
var _was: PackedVector3Array


func _ready() -> void:
	add_to_group("patrol_route")
	if Engine.is_editor_hint():
		set_process(true)


## the stops, in the order they are written, in world space. any Node3D child counts, so a marker,
## a prop or an empty all work and nothing has to be a special type.
func points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for child in get_children():
		var node := child as Node3D
		if node != null and node != _drawn:
			out.append(node.global_position)
	return out


func stops() -> int:
	return points().size()


## where the bird goes after the stop it just finished, and which way it is walking afterwards.
## the two are returned together because a ping-pong route turns round at the ends, and working
## that out in the bird would put half of this node's rule in the other file.
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


## the stop a bird should rejoin the route at: the nearest one. a patrol that has chased somebody
## across the compound walks back to the part of its beat it is standing in, not all the way to
## the first marker like a wind-up toy.
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


## ---------------------------------------------------------------- the editor's line
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var now := points()
	if now == _was:
		return
	_was = now
	_redraw(now)


## the line is built with NO owner, the same rule `Prop` follows: a level with twenty routes in it
## stays a few kilobytes, and nothing drawn here is ever saved into the scene file.
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
