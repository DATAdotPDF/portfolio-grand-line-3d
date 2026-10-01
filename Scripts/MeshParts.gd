extends RefCounted

static func extract(model: Node3D, region: AABB, part_name: String) -> Node3D:
	for instance in model.find_children("*","MeshInstance3D",true,false):
		if instance.mesh.get_surface_count()!=1: continue
		var arrays: Array = instance.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var chosen := PackedInt32Array()
		var kept := PackedInt32Array()
		for i in range(0,indices.size(),3):
			var center := (vertices[indices[i]]+vertices[indices[i+1]]+vertices[indices[i+2]])/3.0
			var face := PackedInt32Array([indices[i],indices[i+1],indices[i+2]])
			if region.has_point(center): chosen.append_array(face)
			else: kept.append_array(face)
		if chosen.size()<30: continue
		var material: Material = instance.get_active_material(0)
		var base_arrays := arrays.duplicate(true)
		base_arrays[Mesh.ARRAY_INDEX] = kept
		var base_mesh := ArrayMesh.new()
		base_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,base_arrays)
		base_mesh.surface_set_material(0,material)
		var lod := ImporterMesh.from_mesh(base_mesh)
		lod.generate_lods(60.0,0.0,[])
		instance.mesh = lod.get_mesh()
		var root := Node3D.new()
		root.name = part_name
		root.position = region.get_center()
		instance.add_child(root)
		var moved := vertices.duplicate()
		for i in range(moved.size()): moved[i]-=root.position
		arrays[Mesh.ARRAY_VERTEX]=moved
		arrays[Mesh.ARRAY_INDEX]=chosen
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(0,material)
		var part := MeshInstance3D.new()
		var part_lod := ImporterMesh.from_mesh(mesh)
		part_lod.generate_lods(60.0,0.0,[])
		part.mesh = part_lod.get_mesh()
		root.add_child(part)
		print("PART_EXTRACTED ",part_name," triangles=",int(chosen.size()/3.0))
		return root
	return null
