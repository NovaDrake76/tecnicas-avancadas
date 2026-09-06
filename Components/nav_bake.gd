class_name NavBake
extends RefCounted


const GROUP := "nav_geometry"
const CELL_SIZE := 0.3
const CELL_HEIGHT := 0.2


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
	mesh.agent_height = CELL_HEIGHT * 4.0
	mesh.agent_radius = CELL_SIZE
	mesh.agent_max_climb = CELL_HEIGHT * 2.0
	mesh.agent_max_slope = 46.0
	mesh.region_min_size = 4.0
	mesh.edge_max_error = 1.5
	region.navigation_mesh = mesh
	root.add_to_group(GROUP)
	parent.add_child(region)
	var map := region.get_navigation_map()
	if map.is_valid():
		NavigationServer3D.map_set_cell_size(map, CELL_SIZE)
		NavigationServer3D.map_set_cell_height(map, CELL_HEIGHT)
	var started := Time.get_ticks_msec()
	region.bake_navigation_mesh(false)
	root.remove_from_group(GROUP)
	print("nav: baked %d polygons in %d ms" % [mesh.get_polygon_count(), Time.get_ticks_msec() - started])
	return region
