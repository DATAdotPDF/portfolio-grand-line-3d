extends RefCounted

## Colisão dos colossos pelo contorno real na linha d'água (Pedro, 2026-10-18: tartaruga e
## caranguejo com colisão errada — cilindro de 72 m no caranguejo, que vai de ~47 m na frente a
## ~115 m nas pernas; a tartaruga com o contorno medido antes de afundar e inclinar o modelo).
## Mede os vértices do modelo já na pose do esqueleto (pele aplicada), na faixa do casco do barco,
## em SECTORS fatias em volta do centro; cada fatia vira um prisma triangular convexo (centro e as
## duas bordas): o conjunto é o contorno em estrela do bicho.

const SECTORS := 48
## Faixa do barco (casco até o mastro) em volta da linha d'água (m, no espaço do nó do bicho: y 0 =
## água, até 40 m): a borda da carapaça e o casco da tartaruga (mais alto atrás) passam por cima do
## barco; o que cobre o barco bloqueia. Embaixo, -3 m: a traseira da tartaruga afunda um pouco
## (inclinada para a frente) e aparece pela água.
const BAND := Vector2(-3.0, 40.0)
const MAX_VERTS := 30000

## Raio do corpo (m) em cada fatia, no espaço de `frame` (y para cima, 0 = água).
static func radii(model: Node3D, frame: Node3D) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SECTORS)
	var to_frame := frame.global_transform.affine_inverse()
	# Planeta pequeno (~800 m): longe do centro o mar cai abaixo do plano do bicho (r²/2R: ~7 m a
	# 107 m). A altura conta a partir do mar ali, não do plano.
	var planet := frame.global_position.length()
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D if mi.skin != null else null
		var binds: Array[Transform3D] = []
		if skeleton != null:
			for i in mi.skin.get_bind_count():
				var bone := mi.skin.get_bind_bone(i)
				if bone < 0:
					bone = skeleton.find_bone(mi.skin.get_bind_name(i))
				binds.append(skeleton.get_bone_global_pose(maxi(bone, 0)) * mi.skin.get_bind_pose(i))
		var base := to_frame * (skeleton.global_transform if skeleton != null else mi.global_transform)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if skeleton != null and arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if not bones.is_empty() else PackedFloat32Array()
			var per := bones.size() / maxi(verts.size(), 1)
			var stride := maxi(1, verts.size() / MAX_VERTS)
			for vi in range(0, verts.size(), stride):
				var v := verts[vi]
				if per > 0:
					var acc := Vector3.ZERO
					var total := 0.0
					for j in per:
						var w := weights[vi * per + j]
						if w > 0.0:
							acc += (binds[bones[vi * per + j]] * v) * w
							total += w
					if total > 0.0:
						v = acc / total
				var p := base * v
				var r := Vector2(p.x, p.z).length()
				var h := p.y + r * r / (2.0 * planet)
				if h < BAND.x or h > BAND.y:
					continue
				var k := int(fposmod(atan2(p.z, p.x), TAU) / TAU * SECTORS) % SECTORS
				out[k] = maxf(out[k], r)
	return out

## Troca as formas de `body` pelo contorno (prismas de bottom a top, acima do mar de cada ponto:
## a borda desce junto com a curva do planeta).
static func fill(body: CollisionObject3D, r: PackedFloat32Array, bottom: float, top: float) -> void:
	var planet := body.global_position.length()
	for child in body.get_children():
		if child is CollisionShape3D:
			body.remove_child(child)
			child.queue_free()
	for k in SECTORS:
		var reach := r[k]
		if reach < 0.5:
			continue
		# Cada fatia vai de uma borda à outra com o raio dela: as vizinhas se encostam, sem vão.
		var a0 := TAU * k / SECTORS
		var a1 := TAU * (k + 1) / SECTORS
		var drop := reach * reach / (2.0 * planet)
		var points := PackedVector3Array()
		for y in [bottom, top]:
			points.append(Vector3(0.0, y, 0.0))
			points.append(Vector3(cos(a0) * reach, y - drop, sin(a0) * reach))
			points.append(Vector3(cos(a1) * reach, y - drop, sin(a1) * reach))
		var convex := ConvexPolygonShape3D.new()
		convex.points = points
		var shape := CollisionShape3D.new()
		shape.shape = convex
		body.add_child(shape)
