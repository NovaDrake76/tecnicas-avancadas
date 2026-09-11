class_name NavBake
extends RefCounted


const GROUP := "nav_geometry"
const CELL_SIZE := 0.3
const CELL_HEIGHT := 0.2
const TERRAIN_HEIGHT := 400.0


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
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, root)
	root.remove_from_group(GROUP)
	var terrain_faces := 0
	for terrain in terrains_under(root):
		## a Terrain3D collider lives in the physics server with no node, so the parser never sees it; the terrain hands its faces over itself.
		var box := terrain_bounds(terrain)
		var faces: PackedVector3Array = terrain.call("generate_nav_mesh_source_geometry", box, false)
		source.add_faces(faces, Transform3D.IDENTITY)
		terrain_faces += int(faces.size() / 3.0)
	if source.has_data():
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	region.navigation_mesh = mesh
	print("nav: baked %d polygons in %d ms (%d terrain faces)" % [mesh.get_polygon_count(),
		Time.get_ticks_msec() - started, terrain_faces])
	return region


static func terrains_under(root: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not ClassDB.class_exists("Terrain3D"):
		return out
	for node in root.find_children("*", "Terrain3D", true, false):
		out.append(node as Node3D)
	return out


static func terrain_bounds(terrain: Node3D) -> AABB:
	var size := int(terrain.get("region_size"))
	var spacing := float(terrain.get("vertex_spacing"))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var locations: Array = terrain.get("data").get("region_locations")
	for cell in locations:
		var at := cell as Vector2i
		lo = lo.min(Vector2(at) * size * spacing)
		hi = hi.max((Vector2(at) + Vector2.ONE) * size * spacing)
	if locations.is_empty():
		return AABB()
	return AABB(Vector3(lo.x, -TERRAIN_HEIGHT * 0.5, lo.y), Vector3(hi.x - lo.x, TERRAIN_HEIGHT, hi.y - lo.y))
