class_name NavBake
extends RefCounted

## a navigation mesh baked at runtime from whatever a level actually has in it. the levels are built
## from props whose collision only exists once the game runs, and Member 2's levels are not finished,
## so nothing is baked in the editor: main bakes when a level loads, behind the curtain, and the
## kiwis follow paths on it instead of running straight lines into walls. the settings are one place
## because the probe bakes a small one in the sky the same way.

const GROUP := "nav_geometry"
## the hill ring's concave mesh is most of level 1's bake, so the cell is coarse on purpose; raise it
## further if the two seconds ever matter. the MAP has to be told the same two numbers: it keeps its
## own copy, godot's defaults are 0.25 and 0.25, and a mesh rasterised finer than the map it is put on
## warns and can drop edges. one const each, read by both, is what keeps them from drifting apart.
const CELL_SIZE := 0.3
const CELL_HEIGHT := 0.2


## a fresh region under `parent`, baked from every static collider on the world layer under `root`.
## synchronous on purpose: it runs behind the curtain, and a kiwi that starts moving before the mesh
## exists would take the straight line the mesh is there to replace.
static func bake(root: Node, parent: Node) -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	region.name = "NavRegion"
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name = GROUP
	mesh.cell_size = CELL_SIZE
	mesh.cell_height = CELL_HEIGHT
	## a kiwi: a 0.4 m wide capsule that StepClimb lifts 0.4 m. every one of these is measured in
	## CELLS, so a value that is not a whole number of them is ceiled and the bake warns: 0.7 m of
	## headroom was already being rounded up to 0.8, which is 4 cells, so it says 0.8. the radius is
	## one cell_size and the climb two cell_heights, both exact.
	mesh.agent_height = CELL_HEIGHT * 4.0
	mesh.agent_radius = CELL_SIZE
	mesh.agent_max_climb = CELL_HEIGHT * 2.0
	mesh.agent_max_slope = 46.0
	mesh.region_min_size = 4.0
	mesh.edge_max_error = 1.5
	region.navigation_mesh = mesh
	root.add_to_group(GROUP)
	parent.add_child(region)
	## after add_child, or the region has no map to speak of yet
	var map := region.get_navigation_map()
	if map.is_valid():
		NavigationServer3D.map_set_cell_size(map, CELL_SIZE)
		NavigationServer3D.map_set_cell_height(map, CELL_HEIGHT)
	var started := Time.get_ticks_msec()
	region.bake_navigation_mesh(false)
	root.remove_from_group(GROUP)
	print("nav: baked %d polygons in %d ms" % [mesh.get_polygon_count(), Time.get_ticks_msec() - started])
	return region
