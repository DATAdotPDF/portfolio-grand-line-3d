extends RefCounted

static func build(mount: Node3D, model: Node3D, radius: float) -> void:
	var key := str(hash(var_to_str([model.scene_file_path,FileAccess.get_modified_time(model.scene_file_path),model.position,model.scale,radius,4])))
	var cache_path := "user://shore_"+key+".bin"
	if FileAccess.file_exists(cache_path):
		var cache_reader := FileAccess.open(cache_path,FileAccess.READ)
		var data: Variant = cache_reader.get_var()
		if data is Dictionary and data.has("faces") and data.has("coast"):
			_attach(mount,data.faces,data.coast)
			return
	var faces := PackedVector3Array()
	var coast := PackedVector3Array()
	for instance in model.find_children("*","MeshInstance3D",true,false):
		var relative: Transform3D = mount.global_transform.affine_inverse()*instance.global_transform
		for surface in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0,indices.size(),3):
				var v := PackedVector3Array([relative*vertices[indices[i]],relative*vertices[indices[i+1]],relative*vertices[indices[i+2]]])
				var cuts := PackedVector3Array()
				for edge in range(3):
					var edge_a := v[edge]
					var edge_b := v[(edge+1)%3]
					var da := (edge_a+Vector3.UP*radius).length()-radius
					var db := (edge_b+Vector3.UP*radius).length()-radius
					if (da<0.0) != (db<0.0): cuts.append(edge_a.lerp(edge_b,da/(da-db)))
				if cuts.size()!=2 or cuts[0].distance_squared_to(cuts[1])<0.000001: continue
				var a := cuts[0]
				var b := cuts[1]
				var ua := (a+Vector3.UP*radius).normalized()
				var ub := (b+Vector3.UP*radius).normalized()
				# A thin vertical wall at the actual mean-water intersection, not an offset ring.
				faces.append_array(PackedVector3Array([a-ua*3.0,b-ub*3.0,b+ub*3.0,a-ua*3.0,b+ub*3.0,a+ua*3.0]))
				coast.append(a)
				coast.append(b)
	var cache_writer := FileAccess.open(cache_path,FileAccess.WRITE)
	if cache_writer: cache_writer.store_var({"faces":faces,"coast":coast})
	_attach(mount,faces,coast)

static func _attach(mount: Node3D, faces: PackedVector3Array, coast: PackedVector3Array) -> void:
	var body := StaticBody3D.new()
	body.name = "CoastWall"
	body.collision_layer = 1
	body.collision_mask = 2
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	mount.add_child(body)
	mount.set_meta("coast_points",coast)
	var cells := {}
	var samples := PackedVector3Array()
	for point in coast:
		var cell := Vector3i((point*4.0).floor())
		if not cells.has(cell):
			cells[cell]=true
			samples.append(point)
	mount.set_meta("coast_samples",samples)
	print("COAST_WALL ",mount.name," segments=",int(coast.size()/2.0))

static func distance_to_coast(island: Node3D, world_point: Vector3) -> float:
	var points: PackedVector3Array = island.get_meta("coast_samples",PackedVector3Array())
	var local := island.to_local(world_point)
	var best := INF
	for point in points: best=minf(best,local.distance_squared_to(point))
	return sqrt(best)
