@tool
extends Node3D

## Ancora as cinco ilhas pela configuração lat/lon de Config/world_layout.tres.
## Roda no editor e no jogo; mudar o raio do planeta ou uma coordenada reposiciona
## tudo sozinho. A altura de cada ilha usa a base MEDIDA do próprio GLB (AABB),
## e a placa de título fica acima do topo medido, na mesma normal radial.

const Scale = preload("res://Scripts/WorldScale.gd")

signal anchors_applied

@export var apply_now := false:
	set(value):
		if value:
			apply_layout()

func _ready() -> void:
	var layout := Scale.layout()
	if not layout.changed.is_connected(apply_layout):
		layout.changed.connect(apply_layout)
	apply_layout()

func apply_layout() -> void:
	if not is_inside_tree():
		return
	var layout := Scale.layout()
	var planet_radius := layout.planet_radius
	var count := mini(get_child_count(), layout.islands.size())
	for i in range(count):
		var mount := get_child(i) as Node3D
		var anchor := layout.islands[i]
		if mount == null or anchor == null:
			continue
		mount.global_transform = Scale.anchor_transform(anchor, planet_radius)
		mount.set_meta("section", anchor.section)
		mount.set_meta("surface_normal", mount.global_position.normalized())
		var model := mount.get_node_or_null("IslandModel") as Node3D
		if model == null:
			continue
		var bounds := measure_model(model)
		var floor_offset := bounds.position.y
		var ceiling_offset := bounds.end.y
		model.position.y = -floor_offset - anchor.submersion
		mount.set_meta("floor_offset", floor_offset)
		mount.set_meta("ceiling_offset", ceiling_offset)
		var island_top := model.position.y + ceiling_offset
		mount.set_meta("island_floor", -anchor.submersion)
		mount.set_meta("island_top", island_top)
		var title := mount.get_node_or_null("IslandTitleSign") as Node3D
		if title != null:
			var plate_half := Scale.PLATE_HALF_HEIGHT
			var plate := title.get_node_or_null("NameplateMesh") as Node3D
			if plate != null:
				var plate_bounds := _local_bounds(plate)
				plate_half = plate_bounds.size.y * plate.scale.y * 0.5
			title.position = Vector3(0.0, island_top + anchor.plate_clearance + plate_half, 0.0)
			title.set("base_position", title.position)
			mount.set_meta("plate_ceiling", title.position.y + plate_half)
	anchors_applied.emit()

## AABB do modelo no espaço da âncora, ignorando a altura atual (só escala/rotação).
## Retorna floor/ceiling já escalados: os valores reais medidos no GLB × escala.
static func measure_model(model: Node3D) -> AABB:
	var local := _local_bounds(model)
	var placement := Transform3D(model.transform.basis, Vector3(model.position.x, 0.0, model.position.z))
	return placement * local

static func _local_bounds(node: Node3D) -> AABB:
	var total := AABB()
	var found := false
	var inverse := node.global_transform.affine_inverse()
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var part: AABB = (inverse * mesh.global_transform) * mesh.get_aabb()
		total = total.merge(part) if found else part
		found = true
	return total
