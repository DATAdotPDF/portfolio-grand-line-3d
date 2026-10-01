extends Node3D

const ASSETS := [
	["ilha_sobre", "res://Assets/Optimized/island_sobre.glb"],
	["ilha_experiencia", "res://Assets/Optimized/island_experiencia.glb"],
	["ilha_formacao", "res://Assets/Optimized/island_formacao.glb"],
	["ilha_projetos", "res://Assets/Optimized/island_projetos.glb"],
	["ilha_contato", "res://Assets/Optimized/island_contato.glb"],
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
