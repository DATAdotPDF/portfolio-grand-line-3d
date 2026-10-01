extends SceneTree

## Mede o perfil da base de cada ilha: raio horizontal máximo dos vértices por
## fatia de altura (em metros já escalados), para localizar o topo do "pedestal".
## Uso: Godot.exe --headless --path . --script res://Tests/measure_island_pedestals.gd

const ISLANDS := [
	["sobre", "res://Assets/Meshy_AI_island_1_about_harbor_0929193106_image-to-3d-texture.glb", 14.716394],
	["experiencia", "res://Assets/Meshy_AI_island_2_experience_f_0929193424_image-to-3d-texture.glb", 16.816385],
	["formacao", "res://Assets/Meshy_AI_island_3_formation_po_0929193844_image-to-3d-texture.glb", 15.769339],
	["projetos", "res://Assets/Meshy_AI_island_4_projects_shi_0929194206_image-to-3d-texture.glb", 16.810696],
	["contato", "res://Assets/Meshy_AI_island_5_contact_ligh_0929194453_image-to-3d-texture.glb", 19.970337],
]
const SLICE := 0.25
const MAX_HEIGHT := 5.0

func _initialize() -> void:
	for entry in ISLANDS:
		var model := (load(entry[1]) as PackedScene).instantiate() as Node3D
		root.add_child(model)
		var scale: float = entry[2]
		var bins := {}
		var floor_y := INF
		var points := PackedVector3Array()
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var relative: Transform3D = model.global_transform.affine_inverse() * mesh.global_transform
			for surface in range(mesh.mesh.get_surface_count()):
				var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for v in vertices:
					var p: Vector3 = relative * v * scale
					points.append(p)
					floor_y = minf(floor_y, p.y)
		for p in points:
			var h := p.y - floor_y
			if h > MAX_HEIGHT:
				continue
			var key := int(h / SLICE)
			bins[key] = maxf(float(bins.get(key, 0.0)), Vector2(p.x, p.z).length())
		var line := "PEDESTAL %s floor=%.3f profile:" % [entry[0], floor_y]
		for key in range(int(MAX_HEIGHT / SLICE)):
			line += " %.2f:%.1f" % [key * SLICE, float(bins.get(key, 0.0))]
		print(line)
		model.queue_free()
	quit()
