"""Seleção do TECIDO de bandeiras nos modelos do Meshy (malha única: pano, mastro e cordas juntos).

Usado por Tools/animate_world_props.py. Nada de altura ou região sozinhas (o mastro e a verga ficavam
junto com o pano): cada face recebe a cor da textura de cor no centro dela (UV), e é pano se a cor é
de pano (azul/anil, preto-azulado, ou branco do desenho cercado de pano) e NÃO de madeira/corda
(marrom/ocre/verde-musgo). Depois só ficam os pedaços de pano LIGADOS (faces vizinhas), grandes, dentro
da caixa da bandeira. O peso do pano cresce com a distância até a madeira mais próxima: o que
encosta na madeira (costura, argola) fica com peso 0 e não se mexe.
"""
import colorsys
import bmesh
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree


def _base_images(mesh):
	"""Imagem da cor base de cada material (índice do material → (pixels Nx4, largura, altura))."""
	out = {}
	for i, slot in enumerate(mesh.material_slots):
		mat = slot.material
		if not mat or not mat.use_nodes:
			continue
		bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
		if not bsdf or not bsdf.inputs["Base Color"].links:
			continue
		node = bsdf.inputs["Base Color"].links[0].from_node
		if node.type != "TEX_IMAGE" or not node.image:
			continue
		img = node.image
		w, h = img.size
		px = np.empty(w * h * 4, dtype=np.float32)
		img.pixels.foreach_get(px)
		out[i] = (px.reshape(h, w, 4), w, h)
	return out


def face_colors(mesh, indices=None):
	"""Cor (r, g, b) no centro UV das faces (média dos cantos e do centro): {índice: cor}."""
	images = _base_images(mesh)
	uv = mesh.data.uv_layers.active.data
	cols = {}
	polys = mesh.data.polygons
	for idx in (indices if indices is not None else range(len(polys))):
		poly = polys[idx]
		img = images.get(poly.material_index)
		if img is None:
			cols[idx] = (0.5, 0.5, 0.5)
			continue
		px, w, h = img
		uvs = [uv[li].uv for li in poly.loop_indices]
		center = sum(uvs, Vector((0.0, 0.0))) / len(uvs)
		samples = [center] + [center.lerp(u, 0.5) for u in uvs]
		acc = np.zeros(3)
		for s in samples:
			x = int((s.x % 1.0) * (w - 1))
			y = int((s.y % 1.0) * (h - 1))
			acc += px[y, x, :3]
		cols[idx] = tuple(acc / len(samples))
	return cols


def is_wood(c):
	h, s, v = colorsys.rgb_to_hsv(*c)
	hue = h * 360.0
	return 12.0 <= hue <= 95.0 and s > 0.18 and v > 0.08


def is_cloth(c, palette):
	h, s, v = colorsys.rgb_to_hsv(*c)
	hue = h * 360.0
	if "blue" in palette and 175.0 <= hue <= 265.0 and s > 0.15 and v > 0.12:
		return True
	if "dark" in palette and v < 0.2 and not (12.0 <= hue <= 95.0 and s > 0.3):
		return True
	return False


def cloth_faces(mesh, box_min, box_max, palette=("blue", "dark"), min_faces=60):
	"""Faces de pano dentro da caixa (espaço do mundo do mesh): cor de pano + desenho branco cercado de
	pano, só pedaços ligados com pelo menos min_faces faces. Devolve (faces de pano, faces de madeira)."""
	mw = mesh.matrix_world
	bm = bmesh.new()
	bm.from_mesh(mesh.data)
	bm.faces.ensure_lookup_table()
	inside = set()
	for f in bm.faces:
		c = mw @ f.calc_center_median()
		if all(box_min[i] <= c[i] <= box_max[i] for i in range(3)):
			inside.add(f.index)
	cols = face_colors(mesh, inside)
	cloth = {i for i in inside if is_cloth(cols[i], palette)}
	wood = {i for i in inside if is_wood(cols[i])}
	# Desenho claro (caveira, rosa dos ventos) e bordas do pano: tudo que está LIGADO ao pano e não é
	# madeira/corda entra junto (enchendo a partir do pano, sem sair da caixa da bandeira).
	stack = list(cloth)
	while stack:
		i = stack.pop()
		for e in bm.faces[i].edges:
			for g in e.link_faces:
				j = g.index
				if j in inside and j not in cloth and j not in wood:
					cloth.add(j)
					stack.append(j)
	# Pedaços ligados (faces que dividem aresta).
	seen = set()
	keep = set()
	for start in cloth:
		if start in seen:
			continue
		comp = []
		stack = [start]
		seen.add(start)
		while stack:
			i = stack.pop()
			comp.append(i)
			for e in bm.faces[i].edges:
				for g in e.link_faces:
					if g.index in cloth and g.index not in seen:
						seen.add(g.index)
						stack.append(g.index)
		if len(comp) >= min_faces:
			keep.update(comp)
	bm.free()
	return keep, set(range(len(mesh.data.polygons))) - keep


def cloth_vertex_weights(mesh, cloth, falloff, box_min=None, box_max=None):
	"""Peso de pano por vértice: 0 em qualquer vértice de face que não é pano (mastro, verga, corda) e
	crescendo com a distância até esse vértice mais próximo (falloff = distância até peso 1)."""
	cloth_verts = set()
	for i in cloth:
		cloth_verts.update(mesh.data.polygons[i].vertices)
	mw = mesh.matrix_world
	rigid_verts = set()
	pad = Vector((falloff, falloff, falloff)) * 2.0
	for poly in mesh.data.polygons:
		if poly.index in cloth:
			continue
		if box_min is not None:
			c = mw @ poly.center
			if not all(box_min[i] - pad[i] <= c[i] <= box_max[i] + pad[i] for i in range(3)):
				continue
		rigid_verts.update(poly.vertices)
	tree = KDTree(len(rigid_verts))
	for k, i in enumerate(rigid_verts):
		tree.insert(mw @ mesh.data.vertices[i].co, k)
	tree.balance()
	weights = {}
	for i in cloth_verts:
		if i in rigid_verts:
			continue
		p = mw @ mesh.data.vertices[i].co
		_, _, d = tree.find(p)
		t = min(max(d / falloff, 0.0), 1.0)
		weights[i] = t * t * (3.0 - 2.0 * t)
	return weights
