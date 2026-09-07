@tool
extends EditorScenePostImport


func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(i) as StandardMaterial3D
			var mat: StandardMaterial3D = source.duplicate() if source != null else StandardMaterial3D.new()
			if mat.albedo_texture != null:
				continue
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mi.mesh.surface_set_material(i, mat)
	return scene
