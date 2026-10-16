# Split the Meshy sloop (single fused mesh) into Hull / Sail_Main / Sail_Stern / Flag and add a Rudder.
# Blender axes: +X = stern (back), -X = bow, +Z = up. Run inside Blender: split(obj_name, prefix).
#
# How to regenerate both runtime models (Blender 5.x, inside its Python console or via the MCP):
#   1. Import the CURRENT optimized GLBs as sources (they must be the single-mesh Meshy versions;
#      the originals were backed up in _backup/sloop_2026-10-05/):
#        Assets/Optimized/sloop_clean_sail.glb       -> rename the mesh object "Optimized_Mesh_0.001"
#        Assets/OptimizedMobile/sloop_clean_sail.glb -> rename the mesh object "Mobile_Mesh"
#      Both at the origin, no transform.
#   2. Run this file, then: export_all(r"D:\Godot\Projects\portifolio-pedro-ferreira-3d-2026")
#      It writes both GLBs back with nodes Hull / Sail_Main / Sail_Stern / Flag / Rudder
#      (names the game looks up in Scripts/main_world.gd) and bakes the rudder texture once.
#   3. In Godot, reimport and check with: Godot --path . --script res://Tests/sloop_probe.gd
#
# Numbers tied to this specific Meshy model (bounding boxes, mast line, rudder hinge, atlas UV windows)
# are measured for it; a different model needs them re-measured.
import bpy, bmesh, numpy as np
from collections import defaultdict
from mathutils import Vector, Matrix


def _arrays(obj):
    me = obj.data
    nf = len(me.polygons)
    ls = np.zeros(nf, int); me.polygons.foreach_get("loop_start", ls)
    lt = np.zeros(nf, int); me.polygons.foreach_get("loop_total", lt)
    vi = np.zeros(len(me.loops), int); me.loops.foreach_get("vertex_index", vi)
    co = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    uv = np.zeros(len(me.loops) * 2); me.uv_layers.active.data.foreach_get("uv", uv); uv = uv.reshape(-1, 2)
    fc = np.zeros(nf * 3); me.polygons.foreach_get("center", fc); fc = fc.reshape(-1, 3)
    img = [n for n in obj.material_slots[0].material.node_tree.nodes if n.type == 'TEX_IMAGE' and n.outputs[0].links
           and any(l.to_socket.name == "Base Color" for l in n.outputs[0].links)][0].image
    W, H = img.size
    px = np.array(img.pixels[:]).reshape(H, W, -1)[:, :, :3]
    fuv = np.array([uv[ls[f]:ls[f] + lt[f]].mean(0) for f in range(nf)])
    rgb = px[np.clip((fuv[:, 1] * H).astype(int), 0, H - 1), np.clip((fuv[:, 0] * W).astype(int), 0, W - 1)]
    _, weld = np.unique(np.round(co / 0.0015).astype(np.int64), axis=0, return_inverse=True)
    weld = weld.ravel()
    fverts = [weld[vi[ls[f]:ls[f] + lt[f]]] for f in range(nf)]
    v2f = defaultdict(list)
    for f, vs in enumerate(fverts):
        for v in vs:
            v2f[v].append(f)
    nbr = [set(g for v in vs for g in v2f[v] if g != f) for f, vs in enumerate(fverts)]
    return fc, rgb, nbr, fuv, co


def classify(obj):
    fc, rgb, nbr, fuv, co = _arrays(obj)
    x, y, z = fc[:, 0], fc[:, 1], fc[:, 2]
    mn, mx = rgb.min(1), rgb.max(1); sat = mx - mn
    cloth = (sat < 0.16) & (mn > 0.28)
    red = (rgb[:, 0] > 0.45) & (rgb[:, 0] - rgb[:, 2] > 0.3)
    dark = mx < 0.22
    lab = np.zeros(len(fc), int)  # 0 hull, 1 main sail, 2 stern sail, 3 flag
    boxM = (x > -0.24) & (x < 0.015) & (z > -0.14) & (z < 0.56)
    lab[boxM & cloth] = 1
    lab[dark & (z > 0.56)] = 3
    for _ in range(4):  # majority filter: fill specks inside the main sail and the flag
        new = lab.copy()
        for f in np.where(boxM | (z > 0.56))[0]:
            nb = [lab[g] for g in nbr[f]]
            if not nb: continue
            c = np.bincount(nb, minlength=4); best = c.argmax()
            if c[best] >= 0.6 * len(nb) and best != lab[f]:
                if best == 1 and not (cloth[f] or sat[f] < 0.25): continue
                new[f] = best
        lab = new
    # Stern sail (lateen, hung on a diagonal yard, pierced by the stern mast): cloth colours only, away from
    # the mast and yard axes, not horizontal (deck), grown from red/white seeds.
    me = obj.data
    fn = np.zeros(len(fc) * 3); me.polygons.foreach_get("normal", fn); fn = fn.reshape(-1, 3)
    redS = (rgb[:, 0] > 0.45) & (rgb[:, 0] - rgb[:, 2] > 0.3) & (rgb[:, 1] < 0.42)
    whiteS = (mn > 0.55) & (sat < 0.22)
    wood = (sat > 0.15) & (mx < 0.72) & ~redS
    boxS = (x > 0.6) & (x < 0.93) & (np.abs(y) < 0.34) & (z > -0.22) & (z < 0.3)
    mm = boxS & wood & (np.abs(y) < 0.06) & (x > 0.76) & (x < 0.88) & (z > 0.02) & (z < 0.2)
    mast = np.median(fc[mm][:, :2], 0)
    # The stern mast is raked: fit its axis as a 3D line through the wood near the first guess.
    near = boxS & wood & (np.linalg.norm(fc[:, :2] - mast, axis=1) < 0.06) & (z > -0.15) & (z < 0.22)
    mp = fc[near].mean(0); md = np.linalg.svd(fc[near] - mp)[2][0]
    if md[2] < 0: md = -md
    relm = fc - mp; dm = np.linalg.norm(relm - np.outer(relm @ md, md), axis=1)
    yy = boxS & wood & (dm > 0.06) & (z > -0.05)
    P = fc[yy]; yc = P.mean(0); yd = np.linalg.svd(P - yc)[2][0]
    rel = fc - yc; dyard = np.linalg.norm(rel - np.outer(rel @ yd, yd), axis=1)
    knob = (z > 0.2) & (dm < 0.06)
    ok = boxS & ~wood & ~knob & (dyard > 0.034) & (dm > 0.045) & (np.abs(fn[:, 2]) < 0.85)
    sail = np.zeros(len(fc), bool); seen = np.zeros(len(fc), bool)
    for s0 in np.where(ok & (redS | whiteS))[0]:
        if seen[s0]: continue
        comp = [s0]; seen[s0] = True; i = 0
        while i < len(comp):
            f = comp[i]; i += 1
            for g in nbr[f]:
                if not seen[g] and ok[g]: seen[g] = True; comp.append(g)
        if len(comp) >= 40: sail[comp] = True
    ok2 = boxS & ~wood & ~knob & (dm > 0.012) & (dyard > 0.026) & (redS | (mn > 0.5) & (sat < 0.25) | (sat < 0.3))
    front = list(np.where(sail)[0])
    for _ in range(10):
        nxt = []
        for f in front:
            for g in nbr[f]:
                if not sail[g] and ok2[g]: sail[g] = True; nxt.append(g)
        front = nxt
    for _ in range(3):
        for f in np.where(boxS & ~sail & ~wood & ~knob)[0]:
            nb = list(nbr[f])
            if nb and sum(sail[g] for g in nb) >= 0.6 * len(nb): sail[f] = True
    # The lateen yard and the ropes lashed to it move with the sail (the rig slides forward of the mast as one piece).
    along = (fc - yc) @ yd; a0, a1 = np.percentile(along[yy], [1, 99])
    yard = (np.abs(y) < 0.36) & (x > 0.55) & (x < 0.97) & (z > -0.2) & (z < 0.3) & (dyard < 0.06) & (dm > 0.04)         & ~knob & (along > a0 - 0.06) & (along < a1 + 0.06)
    rig = sail | yard
    # Dilate a few rings so shards and the yard end caps go with the rig; never take the mast, its knob or the deck.
    keep_out = (dm < 0.035) | knob | (z < -0.27) | (x < 0.55)
    front = list(np.where(rig)[0])
    for _ in range(3):
        nxt = []
        for f in front:
            for g in nbr[f]:
                if not rig[g] and not keep_out[g] and lab[g] == 0: rig[g] = True; nxt.append(g)
        front = nxt
    lab[rig & (lab == 0)] = 2
    obj["stern_mast_line"] = [float(v) for v in (*mp, *md)]
    return lab, fc, rgb, fuv


def _pick_uv(fc, rgb, fuv, lab, target, region):
    m = region & (lab == 0)
    d = np.linalg.norm(rgb[m] - np.array(target), axis=1)
    return fuv[np.where(m)[0][d.argmin()]]


def split(obj_name, prefix):
    src = bpy.data.objects[obj_name]
    lab, fc, rgb, fuv = classify(src)
    names = {0: "Hull", 1: "Sail_Main", 2: "Sail_Stern", 3: "Flag"}
    coll = bpy.data.collections.get(prefix) or bpy.data.collections.new(prefix)
    if coll.name not in bpy.context.scene.collection.children: bpy.context.scene.collection.children.link(coll)
    for o in list(coll.objects): bpy.data.objects.remove(o, do_unlink=True)
    root = bpy.data.objects.new(prefix + "_Sloop", None); coll.objects.link(root)
    parts = {}
    for k, name in names.items():
        me = src.data.copy(); me.name = prefix + "_" + name
        bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if lab[f.index] != k], context='FACES')
        bm.to_mesh(me); bm.free()
        for a in list(me.color_attributes): me.color_attributes.remove(a)
        o = bpy.data.objects.new(name, me); coll.objects.link(o); o.parent = root
        parts[name] = o
    push_stern_sail(parts["Sail_Stern"], src["stern_mast_line"])
    trim_below_deck(parts["Sail_Stern"], parts["Hull"])
    zip_mast_slit(parts["Sail_Stern"], src["stern_mast_line"], parts["Sail_Stern"]["rig_shift"])
    x = fc[:, 0]; z = fc[:, 2]; y = fc[:, 1]
    wood_uv = _pick_uv(fc, rgb, fuv, lab, (0.52, 0.35, 0.21), (x > 0.3) & (np.abs(y) > 0.2) & (z < -0.3))
    iron_uv = _pick_uv(fc, rgb, fuv, lab, (0.30, 0.31, 0.33), (x > 0.4) & (z < -0.2))
    rud = build_rudder(src.data.materials[0], wood_uv, iron_uv, prefix)
    coll.objects.link(rud); rud.parent = root
    parts["Rudder"] = rud
    return {k: (len(v.data.polygons)) for k, v in parts.items()}, np.bincount(lab, minlength=4).tolist()


def push_stern_sail(obj, mast_line, radius=0.035, margin=0.012):
    # Slide the whole stern rig (sail + yard) toward the bow (-X) just enough that no cloth near the mast
    # stays behind it: a rigid move, so the cloth keeps its shape (no folds).
    me = obj.data
    co = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    p = np.array(mast_line[:3]); d = np.array(mast_line[3:])
    k = (co[:, 2] - p[2]) / d[2]
    xm = p[0] + d[0] * k; ym = p[1] + d[1] * k
    near = np.abs(co[:, 1] - ym) < radius + 0.02
    shift = max(0.0, float(np.max(co[near, 0] - (xm[near] - radius - margin)))) if near.any() else 0.0
    co[:, 0] -= shift
    me.vertices.foreach_set("co", co.ravel()); me.update()
    obj["rig_shift"] = shift


def trim_below_deck(sail, hull, radius=0.02):
    # After sliding forward, the lowest corner of the stern sail ends up inside the poop deck/rail:
    # drop the faces that sit under the hull's upward-facing surfaces (they were hidden there anyway).
    from mathutils import kdtree
    hm = hull.data
    ups = [(p.center.copy(), p.center.z) for p in hm.polygons if p.normal.z > 0.6]
    kd = kdtree.KDTree(len(ups))
    for i, (c, _) in enumerate(ups): kd.insert((c.x, c.y, 0.0), i)
    kd.balance()
    sm = sail.data
    under = set()
    for v in sm.vertices:
        hits = kd.find_range((v.co.x, v.co.y, 0.0), radius)
        if hits and v.co.z < max(ups[i][1] for _, i, _ in hits) - 0.004:
            under.add(v.index)
    bm = bmesh.new(); bm.from_mesh(sm); bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if any(v.index in under for v in f.verts)], context='FACES')
    bm.to_mesh(sm); bm.free(); sm.update()
    sail["trimmed_verts"] = len(under)


def zip_mast_slit(obj, mast_line, shift):
    # Where the stern mast went through the cloth there are holes; after the rig slides forward they read as a
    # slit. Weld the UV-seam splits, then pull the slit's border vertices onto the old mast line (in the beam
    # direction only): the neighbouring cloth stretches a little and the stripes stay continuous.
    me = obj.data
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0015)
    p = np.array(mast_line[:3]); d = np.array(mast_line[3:])
    zipped = 0
    for v in bm.verts:
        if not any(e.is_boundary for e in v.link_edges): continue
        ym = p[1] + d[1] * (v.co.z - p[2]) / d[2]
        xm = p[0] + d[0] * (v.co.z - p[2]) / d[2] - shift
        if abs(v.co.y - ym) < 0.06 and abs(v.co.x - xm) < 0.09 and v.co.z > -0.24:
            v.co.y = ym; zipped += 1
    bm.normal_update(); bm.to_mesh(me); bm.free(); me.update()
    obj["zipped_verts"] = zipped


# Texture windows in the Meshy atlas (same UV layout on desktop and mobile): painted planks with cracks/grain,
# and the dark iron of the hull bands. The rudder is mapped onto them so it shades like the rest of the ship.
WOOD_UV = (0.8438, 0.3438); WOOD_HALF = 0.012
IRON_UV = (0.426, 0.695); IRON_HALF = 0.005


def build_rudder(material, wood_uv, iron_uv, prefix):
    # Hinge axis on the sternpost, raked like the hull: top A -> bottom B (blender coords).
    A = Vector((0.94, 0.0, -0.22)); B = Vector((0.87, 0.0, -0.78))
    axis = (B - A).normalized()            # points down along the hinge
    aft = Vector((1, 0, 0)) - axis * axis.dot(Vector((1, 0, 0))); aft.normalize()
    L = (B - A).length
    bm = bmesh.new()
    iron_layer = bm.faces.layers.int.new("iron")

    def box(c0, c1, half_y, iron=False):
        # c0/c1: (u, w) corners in hinge plane (u along axis from A, w aft); square-ish slab.
        (u0, w0), (u1, w1) = c0, c1
        pts = []
        for (u, w) in ((u0, w0), (u0, w1), (u1, w1), (u1, w0)):
            base = A + axis * u + aft * w
            pts.append((base + Vector((0, -half_y, 0)), base + Vector((0, half_y, 0))))
        v = [bm.verts.new(p) for pair in pts for p in pair]
        quads = [(0, 2, 4, 6), (1, 7, 5, 3), (0, 1, 3, 2), (2, 3, 5, 4), (4, 5, 7, 6), (6, 7, 1, 0)]
        for q in quads:
            f = bm.faces.new([v[i] for i in q])
            f[iron_layer] = 1 if iron else 0

    def blade():
        # Tapered blade: narrow at the top, wide at the bottom, thinner at the trailing edge.
        rows = 6; u_top, u_bot = 0.08, L + 0.015
        ring = []
        for i in range(rows + 1):
            t = i / rows; u = u_top + (u_bot - u_top) * t
            chord = 0.055 + 0.105 * t ** 0.8
            lead, trail = A + axis * u + aft * 0.004, A + axis * u + aft * (0.004 + chord)
            ring.append([bm.verts.new(lead + Vector((0, -0.013, 0))), bm.verts.new(trail + Vector((0, -0.007, 0))),
                         bm.verts.new(trail + Vector((0, 0.007, 0))), bm.verts.new(lead + Vector((0, 0.013, 0)))])
        for i in range(rows):
            a, b = ring[i], ring[i + 1]
            for j in range(4):
                bm.faces.new([a[j], a[(j + 1) % 4], b[(j + 1) % 4], b[j]])
        bm.faces.new(ring[0][::-1]); bm.faces.new(ring[-1])

    blade()
    box((0.0, -0.018), (0.12, 0.018), 0.017)                 # rudder stock (post at the hinge)
    box((0.0, -0.012), (0.022, -0.10), 0.012)                # tiller over the stern rail
    for u in (0.18, 0.31):                                    # iron straps (pintles/gudgeons) that reach the hull
        box((u, -0.1), (u + 0.022, 0.05), 0.019, iron=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    # Small chamfer on every edge so the light draws the rudder's outline like the hand-painted hull.
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.0025, segments=1, affect='EDGES', clamp_overlap=True)
    bm.normal_update()
    # UVs: planar projection in the hinge frame onto the atlas windows (wood grain runs along the blade).
    uvl = bm.loops.layers.uv.new("UVMap")
    span = L + 0.1
    for f in bm.faces:
        side = abs(f.normal.y) < 0.5
        center, half = (IRON_UV, IRON_HALF) if f[iron_layer] else (WOOD_UV, WOOD_HALF)
        for l in f.loops:
            rel = l.vert.co - A
            u = rel.dot(axis); w = rel.dot(aft)
            a = rel.y * 2.0 + w if side else w
            l[uvl].uv = (center[0] + (a / span) * 2 * half, center[1] + (u / span - 0.5) * 2 * half)
    me = bpy.data.meshes.new(prefix + "_Rudder"); bm.to_mesh(me); bm.free()
    me.materials.append(material)
    up = -axis
    rot = up.to_track_quat('Z', 'X').to_matrix().to_4x4()
    mat = Matrix.Translation(A) @ rot
    me.transform(mat.inverted())
    o = bpy.data.objects.new("Rudder", me); o.matrix_world = mat
    for p in me.polygons: p.use_smooth = False
    return o


def bake_rudder_material(rudder, size=512):
    # The rudder gets its own small baked texture (stylised planks with grain, plank seams, worn lighter edges,
    # ambient occlusion and dark iron straps) in the hull's palette, instead of a flat colour from the atlas.
    scene = bpy.context.scene
    prev_engine = scene.render.engine
    me = rudder.data
    while me.uv_layers: me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name="UVMap")
    for o in bpy.context.view_layer.objects: o.select_set(False)
    rudder.hide_set(False); rudder.select_set(True); bpy.context.view_layer.objects.active = rudder
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.03)
    bpy.ops.object.mode_set(mode='OBJECT')

    color_img = bpy.data.images.new("rudder_wood", size, size)
    ao_img = bpy.data.images.new("rudder_ao", size, size)
    bake = bpy.data.materials.new("RudderBake"); bake.use_nodes = True
    nt = bake.node_tree; nt.nodes.clear(); N = nt.nodes.new; Lk = nt.links.new
    out = N("ShaderNodeOutputMaterial"); emit = N("ShaderNodeEmission")
    tc = N("ShaderNodeTexCoord"); sep = N("ShaderNodeSeparateXYZ"); Lk(tc.outputs["Object"], sep.inputs[0])
    wave = N("ShaderNodeTexWave"); wave.bands_direction = 'X'; wave.inputs["Scale"].default_value = 9.0
    wave.inputs["Distortion"].default_value = 7.0; wave.inputs["Detail"].default_value = 4.0
    Lk(tc.outputs["Object"], wave.inputs["Vector"])
    noise = N("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 40.0; Lk(tc.outputs["Object"], noise.inputs["Vector"])
    mixg = N("ShaderNodeMix"); mixg.data_type = 'FLOAT'; mixg.inputs["Factor"].default_value = 0.35
    Lk(wave.outputs["Fac"], mixg.inputs["A"]); Lk(noise.outputs["Fac"], mixg.inputs["B"])
    ramp = N("ShaderNodeValToRGB"); el = ramp.color_ramp.elements
    el[0].position = 0.25; el[0].color = (0.045, 0.02, 0.008, 1); el[1].position = 0.8; el[1].color = (0.20, 0.095, 0.038, 1)  # linear
    Lk(mixg.outputs["Result"], ramp.inputs["Fac"])
    # Plank seams every ~4 cm across the blade (object X ~ aft).
    mul = N("ShaderNodeMath"); mul.operation = 'MULTIPLY'; mul.inputs[1].default_value = 25.0; Lk(sep.outputs["X"], mul.inputs[0])
    fr = N("ShaderNodeMath"); fr.operation = 'FRACT'; Lk(mul.outputs[0], fr.inputs[0])
    seam = N("ShaderNodeMath"); seam.operation = 'LESS_THAN'; seam.inputs[1].default_value = 0.07; Lk(fr.outputs[0], seam.inputs[0])
    dark = N("ShaderNodeMix"); dark.data_type = 'RGBA'; dark.blend_type = 'MULTIPLY'
    Lk(seam.outputs[0], dark.inputs["Factor"]); Lk(ramp.outputs["Color"], dark.inputs["A"]); dark.inputs["B"].default_value = (0.35, 0.3, 0.28, 1)
    # Worn, lighter edges (convex areas).
    geo = N("ShaderNodeNewGeometry"); er = N("ShaderNodeValToRGB"); er.color_ramp.elements[0].position = 0.5; er.color_ramp.elements[1].position = 0.56
    Lk(geo.outputs["Pointiness"], er.inputs["Fac"])
    wear = N("ShaderNodeMix"); wear.data_type = 'RGBA'; wear.blend_type = 'SCREEN'
    Lk(er.outputs["Color"], wear.inputs["Factor"]); Lk(dark.outputs["Result"], wear.inputs["A"]); wear.inputs["B"].default_value = (0.16, 0.09, 0.045, 1)
    # Iron straps: dark slate with a little mottling.
    attr = N("ShaderNodeAttribute"); attr.attribute_name = "iron"; attr.attribute_type = 'GEOMETRY'
    iron = N("ShaderNodeMix"); iron.data_type = 'RGBA'
    ir = N("ShaderNodeValToRGB"); ir.color_ramp.elements[0].color = (0.02, 0.022, 0.026, 1); ir.color_ramp.elements[1].color = (0.08, 0.085, 0.095, 1)
    Lk(noise.outputs["Fac"], ir.inputs["Fac"])
    Lk(attr.outputs["Fac"], iron.inputs["Factor"]); Lk(wear.outputs["Result"], iron.inputs["A"]); Lk(ir.outputs["Color"], iron.inputs["B"])
    Lk(iron.outputs["Result"], emit.inputs["Color"]); Lk(emit.outputs[0], out.inputs[0])
    tex = N("ShaderNodeTexImage"); tex.image = color_img; nt.nodes.active = tex
    me.materials.clear(); me.materials.append(bake)

    scene.render.engine = 'CYCLES'; scene.cycles.samples = 16
    scene.render.bake.margin = 4
    bpy.ops.object.bake(type='EMIT')
    tex.image = ao_img; nt.nodes.active = tex
    scene.world.light_settings.distance = 0.08
    bpy.ops.object.bake(type='AO')
    scene.render.engine = prev_engine

    c = np.array(color_img.pixels[:]).reshape(-1, 4); a = np.array(ao_img.pixels[:]).reshape(-1, 4)
    c[:, :3] *= (0.5 + 0.5 * a[:, :1])
    color_img.pixels[:] = c.ravel()
    color_img.pack()
    bpy.data.images.remove(ao_img)

    final = bpy.data.materials.new("RudderWood"); final.use_nodes = True
    bsdf = final.node_tree.nodes["Principled BSDF"]
    t2 = final.node_tree.nodes.new("ShaderNodeTexImage"); t2.image = color_img
    final.node_tree.links.new(t2.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    me.materials.clear(); me.materials.append(final)
    bpy.data.materials.remove(bake)
    return final


NAMES = ["Hull", "Sail_Main", "Sail_Stern", "Flag", "Rudder"]


def export_all(project_root, desk_src="Optimized_Mesh_0.001", mob_src="Mobile_Mesh"):
    # Builds both runtime models (desktop and mobile) from their imported Meshy-optimized meshes and writes the GLBs.
    # The rudder texture is baked once and shared by both versions.
    import os
    report = {}
    rudder_mesh = None
    for src, prefix, rel in ((desk_src, "Desk", r"Assets\Optimized\sloop_clean_sail.glb"),
                             (mob_src, "Mob", r"Assets\OptimizedMobile\sloop_clean_sail.glb")):
        for c in ("Desk", "Mob"):
            if c in bpy.data.collections:
                for o in bpy.data.collections[c].objects:
                    if o.name in NAMES: o.name = c + "_" + o.name
        if prefix in bpy.data.collections:
            for o in list(bpy.data.collections[prefix].objects): bpy.data.objects.remove(o, do_unlink=True)
        counts, _ = split(src, prefix)
        coll = bpy.data.collections[prefix]
        rud = coll.objects["Rudder"]
        if rudder_mesh is None:
            bake_rudder_material(rud)
            rudder_mesh = rud.data
        else:
            rud.data = rudder_mesh.copy()
        for o in bpy.context.view_layer.objects: o.select_set(False)
        for o in coll.objects: o.hide_set(False); o.select_set(True)
        dst = os.path.join(project_root, rel)
        bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', use_selection=True, export_yup=True,
                                  export_image_format='AUTO', export_animations=False, export_cameras=False, export_lights=False)
        report[prefix] = {"parts": counts, "bytes": os.path.getsize(dst)}
    return report
