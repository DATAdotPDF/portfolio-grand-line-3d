@tool
extends MeshInstance3D

@export var camera: Camera3D
@export var ocean_radius: float = 200.0
var ocean_mat: ShaderMaterial

func _ready() -> void:
	ocean_mat = material_override as ShaderMaterial
	if ocean_mat == null:
		ocean_mat = get_active_material(0) as ShaderMaterial
	# MainWorld handles water input and sends ripples to OceanSimulation.
	set_process_input(false)
	set_process(false)
