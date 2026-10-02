extends MeshInstance3D

## Rota tracejada sobre a água, do barco em direção à ilha de destino (pelo
## grande círculo do globo). Os traços são geometria (não shader) e correm para a
## frente; acompanham a altura das ondas e somem nas pontas pelo alfa do vértice.

const DASH := 2.6
const GAP := 2.0
const STEP := 0.9
const WIDTH := 0.55

@export var max_length := 140.0
@export var hide_within := 70.0
@export var line_color := Color(0.97, 0.93, 0.82, 0.85)

var ship: Node3D
var ocean: Node
var target: Node3D
var material := StandardMaterial3D.new()
var strip := ArrayMesh.new()
var scroll := 0.0

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Opaco: no Compatibility a faixa transparente some sob a água. As pontas afinam em vez de esmaecer.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = line_color
	mesh = strip

func _process(delta: float) -> void:
	strip.clear_surfaces()
	if not is_instance_valid(ship) or not is_instance_valid(target) or not visible:
		return
	var start := ship.global_position
	var up := start.normalized()
	var goal := target.global_position.normalized()
	var radius := start.length()
	var distance := up.angle_to(goal) * radius
	if distance < hide_within:
		return
	var axis := up.cross(goal).normalized()
	if axis.length_squared() < 0.5:
		return
	var length := minf(max_length, distance - hide_within * 0.5)
	var base_radius: float = float(ocean.radius) if ocean else radius
	scroll = fposmod(scroll + delta * 3.0, DASH + GAP)
	global_transform = Transform3D(Basis.IDENTITY, start)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var dash_start := 4.0 + scroll
	while dash_start < length:
		var dash_end := minf(dash_start + DASH, length)
		var along := dash_start
		var first := vertices.size()
		while true:
			var n := up.rotated(axis, along / radius).normalized()
			var fade := smoothstep(4.0, 14.0, along) * (1.0 - smoothstep(length * 0.5, length, along))
			var side := (axis.cross(n)).cross(n).normalized() * WIDTH * 0.5 * fade
			var height: float = float(ocean.height_at(n * base_radius)) if ocean else 0.0
			var center := n * (base_radius + height + 0.15) - start
			var color := line_color
			vertices.append(center - side)
			vertices.append(center + side)
			colors.append(color)
			colors.append(color)
			normals.append(n)
			normals.append(n)
			uvs.append(Vector2(along, 0.0))
			uvs.append(Vector2(along, 1.0))
			if along >= dash_end:
				break
			along = minf(along + STEP, dash_end)
		for i in range(first, vertices.size() - 2, 2):
			indices.append_array(PackedInt32Array([i, i + 1, i + 2, i + 1, i + 3, i + 2]))
		dash_start += DASH + GAP
	if indices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	# O renderer Compatibility não desenha a malha sem normais.
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	strip.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	strip.surface_set_material(0, material)
