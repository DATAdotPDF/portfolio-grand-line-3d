@tool
extends MeshInstance3D

## Malha de água de alta resolução que acompanha o barco (no editor e no jogo).
## O shader ocean_patch desloca os vértices com as ondas; a esfera do oceano é
## descartada dentro deste raio, então de longe o planeta continua perfeitamente redondo.

const Scale = preload("res://Scripts/WorldScale.gd")

@export_node_path("Node3D") var target_path: NodePath = ^"../PlayerShip"
@export_node_path("MeshInstance3D") var sphere_path: NodePath = ^"../OceanMesh"
## Raio do patch em metros. Do barco, o horizonte fica a ~sqrt(2 R h) (≈ 100 m em R = 800).
@export_range(60.0, 600.0, 10.0) var patch_radius := 240.0:
	set(value):
		patch_radius = value
		_rebuild_mesh()
## Quadrados por lado da grade.
@export_range(32, 384, 8) var resolution := 192:
	set(value):
		resolution = value
		_rebuild_mesh()

func _ready() -> void:
	_rebuild_mesh()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_follow()

func _rebuild_mesh() -> void:
	if not is_inside_tree():
		return
	var grid := PlaneMesh.new()
	grid.size = Vector2.ONE * patch_radius * 2.0
	grid.subdivide_width = resolution - 1
	grid.subdivide_depth = resolution - 1
	mesh = grid
	var height := Scale.max_wave_height() + 6.0
	custom_aabb = AABB(Vector3(-patch_radius, -patch_radius * 0.2 - height, -patch_radius), Vector3(patch_radius * 2.0, patch_radius * 0.2 + height * 2.0, patch_radius * 2.0))

func _process(_delta: float) -> void:
	_follow()

func _follow() -> void:
	var target := get_node_or_null(target_path) as Node3D
	if target == null:
		return
	var planet_radius := Scale.radius()
	var cell := patch_radius * 2.0 / float(resolution)
	var source := target.global_position
	if target.has_method("get_global_transform_interpolated") and not Engine.is_editor_hint():
		source = target.get_global_transform_interpolated().origin
	# Ancora a grade em passos de uma célula, para os vértices não "nadarem".
	var snapped := (source.normalized() * planet_radius).snapped(Vector3.ONE * cell)
	var normal := snapped.normalized()
	var center := normal * planet_radius
	global_transform = Transform3D(Scale.surface_basis(normal), center)
	var materials: Array[ShaderMaterial] = []
	if material_override is ShaderMaterial:
		materials.append(material_override)
	var sphere := get_node_or_null(sphere_path) as MeshInstance3D
	if sphere and sphere.material_override is ShaderMaterial:
		materials.append(sphere.material_override)
	for material in materials:
		material.set_shader_parameter("patch_center", center)
		material.set_shader_parameter("patch_radius", patch_radius if visible else 0.0)
