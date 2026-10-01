extends Node3D

const ASSETS := [
	["ilha_sobre", "res://Assets/Meshy_AI_island_1_about_harbor_0929193106_image-to-3d-texture.glb"],
	["ilha_experiencia", "res://Assets/Meshy_AI_island_2_experience_f_0929193424_image-to-3d-texture.glb"],
	["ilha_formacao", "res://Assets/Meshy_AI_island_3_formation_po_0929193844_image-to-3d-texture.glb"],
	["ilha_projetos", "res://Assets/Meshy_AI_island_4_projects_shi_0929194206_image-to-3d-texture.glb"],
	["ilha_contato", "res://Assets/Meshy_AI_island_5_contact_ligh_0929194453_image-to-3d-texture.glb"],
	["placa_sobre", "res://Assets/Optimized/title_sobre.glb"],
	["placa_experiencia", "res://Assets/Optimized/title_experiencia.glb"],
	["placa_formacao", "res://Assets/Optimized/title_formacao.glb"],
	["placa_projetos", "res://Assets/Optimized/title_projetos.glb"],
	["placa_contato", "res://Assets/Optimized/title_contato.glb"]
]

func _ready() -> void:
	for entry in ASSETS:
		var source := load(entry[1]) as PackedScene
		if source == null:
			push_error("ASSET_MEASURE missing=" + entry[1])
			continue
		var model := source.instantiate() as Node3D
		add_child(model)
		var bounds := AABB()
		var found := false
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null:
				continue
			var relative: Transform3D = model.global_transform.affine_inverse() * mesh.global_transform
			var part: AABB = relative * mesh.get_aabb()
			bounds = bounds.merge(part) if found else part
			found = true
		if found:
			print("ASSET_MEASURE ", entry[0], " floor=", bounds.position.y, " ceiling=", bounds.end.y, " size=", bounds.size)
		else:
			push_error("ASSET_MEASURE no_mesh=" + entry[0])
		model.queue_free()
