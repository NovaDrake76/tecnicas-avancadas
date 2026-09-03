class_name NavBake
extends RefCounted

## a navigation mesh baked at runtime from whatever a level actually has in it. the levels are built
## from props whose collision only exists once the game runs, and Member 2's levels are not finished,
## so nothing is baked in the editor: main bakes when a level loads, behind the curtain, and the
## kiwis follow paths on it instead of running straight lines into walls. the settings are one place
## because the probe bakes a small one in the sky the same way.

const GROUP := "nav_geometry"


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
	mesh.cell_size = 0.3
	mesh.cell_height = 0.2
	## a kiwi: a 0.4 m wide capsule that StepClimb lifts 0.4 m
	mesh.agent_height = 0.7
	mesh.agent_radius = 0.3
	mesh.agent_max_climb = 0.4
	mesh.agent_max_slope = 46.0
	mesh.region_min_size = 4.0
	mesh.edge_max_error = 1.5
	region.navigation_mesh = mesh
	root.add_to_group(GROUP)
	parent.add_child(region)
	var started := Time.get_ticks_msec()
	region.bake_navigation_mesh(false)
	root.remove_from_group(GROUP)
	print("nav: baked %d polygons in %d ms" % [mesh.get_polygon_count(), Time.get_ticks_msec() - started])
	return region
