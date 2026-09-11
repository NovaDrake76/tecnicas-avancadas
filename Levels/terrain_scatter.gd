@tool
class_name TerrainScatter
extends Foliage


class Rule:
	var scenes: Array[String]
	var count: int
	var ids: Array[int]
	var y_min: float
	var y_max: float
	var slope_min: float
	var slope_max: float
	var scale_min: float
	var scale_max: float
	var sink: float
	var tint: Color

	func _init(s: Array[String], c: int, on: Array[int], lo: float, hi: float, smin: float, smax: float,
			grow_min: float, grow_max: float, sk := 0.05, tone := Color.WHITE) -> void:
		scenes = s
		count = c
		ids = on
		y_min = lo
		y_max = hi
		slope_min = smin
		slope_max = smax
		scale_min = grow_min
		scale_max = grow_max
		sink = sk
		tint = tone


@export_group("Terrain")
## the Terrain3D this plants on; empty finds the first one beside this node.
@export var terrain_path: NodePath
## nothing is planted this close to the edge of the terrain.
@export var margin := 6.0
## texture ids that count as open ground: trees and grass go here and nowhere else.
@export var ground_ids: Array[int] = [0, 1]
## texture ids of the valley floor, where the ferns are.
@export var valley_ids: Array[int] = [1]
## big boulders on the rim, above the treeline, on top of the ordinary rock_count.
@export var rim_rock_count := 160
## nothing grows below this: the valley floor, or wherever the level's water would be.
@export var floor_height := -12.0
## nothing but rock and the odd tuft grows above this; a mountain reads as one because the trees stop.
@export var treeline := 48.0

var _terrain: Node3D


func build() -> void:
	for child in get_children():
		child.queue_free()
	_terrain = _find_terrain()
	if _terrain == null:
		push_warning("terrain_scatter: no Terrain3D beside %s" % name)
		return
	_rng.seed = scatter_seed

	var rules: Array[Rule] = [
		Rule.new(["tree_pine_a", "tree_pine_b", "tree_a", "tree_b", "tree_c"], tree_count, ground_ids,
			floor_height, treeline, 0.0, 0.55, 0.9, 1.8, 0.35),
		Rule.new(["grass_a", "grass_b", "grass_c", "grass_d"], grass_count, ground_ids,
			floor_height, treeline + 25.0, 0.0, 1.0, 1.0, 2.2, 0.02, grass_tint),
		Rule.new(["fern_a", "fern_b"], fern_count, valley_ids, floor_height, floor_height + 25.0, 0.0, 0.8, 1.0, 2.0, 0.04),
		Rule.new(["stone_a", "stone_b"], rock_count, [], floor_height, 400.0, 0.55, 3.0, 0.7, 2.2, 0.2),
		Rule.new(["stone_a", "stone_b"], rim_rock_count, [], treeline, 400.0, 0.25, 3.0, 1.4, 3.6, 0.25),
		Rule.new(["log_a", "stump_a"], debris_count, ground_ids, floor_height, treeline, 0.0, 0.5, 0.9, 1.6, 0.12),
	]

	var trunks := PackedVector3Array()
	var trunk_scales := PackedFloat32Array()
	var rocks := PackedVector3Array()
	var rock_radii := PackedFloat32Array()

	for rule in rules:
		var is_tree := rule.scenes[0].begins_with("tree")
		var is_rock := rule.scenes[0].begins_with("stone")
		var per_species := maxi(1, floori(float(rule.count) / rule.scenes.size()))
		for source in rule.scenes:
			var placements := _place_on_terrain(rule, per_species)
			var box := _emit(source, placements, rule.tint)
			if is_tree and tree_collision:
				for t in placements:
					trunks.append(t.origin)
					trunk_scales.append(t.basis.get_scale().y)
			if is_rock and rock_collision and box.size != Vector3.ZERO:
				var half := maxf(box.size.x, box.size.z) * 0.5 * rock_radius_scale
				for t in placements:
					rocks.append(t.origin)
					rock_radii.append(half * t.basis.get_scale().y)

	if tree_collision and trunks.size() > 0:
		_build_trunk_bodies(trunks, trunk_scales)
	if rock_collision and rocks.size() > 0:
		_build_rock_bodies(rocks, rock_radii)


func _find_terrain() -> Node3D:
	if not terrain_path.is_empty():
		return get_node_or_null(terrain_path) as Node3D
	var parent := get_parent()
	if parent == null or not ClassDB.class_exists("Terrain3D"):
		return null
	for node in parent.get_children():
		if node.is_class("Terrain3D"):
			return node as Node3D
	return null


func _ground(x: float, z: float) -> float:
	if _terrain == null:
		return 0.0
	var h: float = _terrain.get("data").call("get_height", Vector3(x, 0.0, z))
	return h if is_finite(h) else -1000.0


func _texture_at(x: float, z: float) -> int:
	return int(_terrain.get("data").call("get_control_base_id", Vector3(x, 0.0, z)))


func _slope(x: float, z: float) -> float:
	var d := 1.5
	var dy_x := _ground(x + d, z) - _ground(x - d, z)
	var dy_z := _ground(x, z + d) - _ground(x, z - d)
	return Vector2(dy_x, dy_z).length() / (2.0 * d)


func _bounds() -> Rect2:
	var box := NavBake.terrain_bounds(_terrain)
	return Rect2(box.position.x + margin, box.position.z + margin, box.size.x - 2.0 * margin, box.size.z - 2.0 * margin)


func _place_on_terrain(rule: Rule, wanted: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var area := _bounds()
	var attempts := wanted * 12
	while out.size() < wanted and attempts > 0:
		attempts -= 1
		var x := area.position.x + _rng.randf() * area.size.x
		var z := area.position.y + _rng.randf() * area.size.y
		var y := _ground(x, z)
		if y < rule.y_min or y > rule.y_max:
			continue
		if not rule.ids.is_empty() and not rule.ids.has(_texture_at(x, z)):
			continue
		var tilt := _slope(x, z)
		if tilt < rule.slope_min or tilt > rule.slope_max:
			continue
		var grow := _rng.randf_range(rule.scale_min, rule.scale_max)
		var orient := Basis.from_euler(Vector3(UPRIGHT.x, _rng.randf() * TAU, 0.0)).scaled(Vector3.ONE * grow)
		out.append(Transform3D(orient, Vector3(x, y - rule.sink * grow, z)))
	return out
