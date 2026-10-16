# Procedural ghost galleon prototype (stand-in until Meshy is available again).
# Three parts, like a Meshy request would be: GhostShip_Hull (hull, castles, masts, yards, rigging),
# GhostShip_Sails (tattered), GhostShip_Flag. Blender axes: -X = bow, +X = stern, +Z = up. Length ~6 m.
import bpy, bmesh, math, random
from mathutils import Vector, Matrix, noise

L, BEAM, DEPTH = 6.0, 1.9, 1.15
rng = random.Random(11)


def new_obj(name, bm, coll):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    return o


def half_width(t):
    # t: 0 = bow tip, 1 = stern. Sharp bow, full middle, wide transom.
    if t < 0.4:
        return BEAM * 0.5 * math.sin(t / 0.4 * math.pi / 2) ** 1.25
    return BEAM * 0.5 * (1.0 - 0.18 * ((t - 0.35) / 0.65) ** 2)


def sheer(t):
    # Deck line: rises at the bow and much more at the stern castle.
    return DEPTH + 0.35 * (1 - t) ** 3 + 0.25 * t ** 2


def build_hull(bm):
    stations, ring_n = 26, 12
    rings = []
    for i in range(stations + 1):
        t = i / stations
        x = -L / 2 + t * L
        hw = half_width(t)
        top = sheer(t)
        # Keel line: sweeps up into a curved stem at the bow and a little at the stern.
        keel = 0.95 * max(0.0, 1.0 - t / 0.3) ** 2.2 + 0.3 * max(0.0, (t - 0.8) / 0.2) ** 2
        ring = []
        for j in range(ring_n + 1):
            a = j / ring_n                      # 0 keel -> 1 rail (one side)
            ang = a * math.pi / 2
            y = hw * math.sin(ang) ** 0.7 * (1.0 - 0.08 * a ** 6)  # slight tumblehome near the rail
            z = keel + (top - keel) * (1 - math.cos(ang)) if a < 1 else top
            # Rotting planks: small bumps.
            z += 0.015 * noise.noise(Vector((x * 3, a * 4, 0.3)))
            ring.append((x, y, z))
        full = [bm.verts.new((x, -y, z)) for (x, y, z) in reversed(ring)] + [bm.verts.new(p) for p in ring[1:]]
        rings.append(full)
    for i in range(stations):
        a, b = rings[i], rings[i + 1]
        for j in range(len(a) - 1):
            bm.faces.new([a[j], a[j + 1], b[j + 1], b[j]])
    # Transom (stern wall) and deck.
    bm.faces.new(rings[-1])
    deck_l = [r[0] for r in rings]; deck_r = [r[-1] for r in rings]
    for i in range(stations):
        bm.faces.new([deck_l[i], deck_l[i + 1], deck_r[i + 1], deck_r[i]][::-1])


def add_box(bm, center, size, rot_z=0.0, rot_y=0.0):
    m = Matrix.Translation(center) @ Matrix.Rotation(rot_z, 4, 'Z') @ Matrix.Rotation(rot_y, 4, 'Y') @ Matrix.Diagonal((*size, 1))
    res = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    edges = list({e for v in res["verts"] for e in v.link_edges})
    bmesh.ops.bevel(bm, geom=edges, offset=0.04, segments=2, affect='EDGES', clamp_overlap=True)


def add_cyl(bm, a, b, r, seg=8):
    a, b = Vector(a), Vector(b)
    d = b - a
    m = Matrix.Translation((a + b) / 2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r * 0.85, depth=d.length, matrix=m)


def build_rig(bm):
    # Stern castle and forecastle (tilted a bit: the ship is old).
    add_box(bm, Vector((L * 0.36, 0, sheer(0.9) + 0.32)), (L * 0.26, BEAM * 0.86, 0.65), rot_y=0.02)
    add_box(bm, Vector((L * 0.40, 0, sheer(0.9) + 0.72)), (L * 0.14, BEAM * 0.8, 0.18))
    add_box(bm, Vector((-L * 0.36, 0, sheer(0.1) + 0.2)), (L * 0.14, BEAM * 0.55, 0.4))
    # Gunwale rails: posts + a top rail along both sides (between the castles).
    for side in (-1, 1):
        prev = None
        for i in range(15):
            t = 0.2 + i * (0.55 / 14)
            x = -L / 2 + t * L
            base = Vector((x, side * half_width(t) * 0.97, sheer(t)))
            add_cyl(bm, base, base + Vector((0, 0, 0.22)), 0.02, 5)
            if prev is not None:
                add_cyl(bm, prev + Vector((0, 0, 0.22)), base + Vector((0, 0, 0.22)), 0.025, 5)
            prev = base
    # Bowsprit.
    add_cyl(bm, (-L * 0.45, 0, sheer(0.05) + 0.1), (-L * 0.72, 0, sheer(0.0) + 0.75), 0.06)
    masts = {}
    # Main mast (tall, top snapped and leaning), fore mast (broken short), mizzen (intact, small).
    deck = DEPTH
    base_main = Vector((-0.1, 0, deck))
    add_cyl(bm, base_main, base_main + Vector((0, 0, 3.3)), 0.09)
    snap = base_main + Vector((0, 0, 3.3))
    add_cyl(bm, snap, snap + Vector((0.55, 0.25, 0.9)), 0.075)   # broken top hanging sideways
    masts["main"] = (base_main, 3.3)
    base_fore = Vector((-L * 0.27, 0, deck + 0.05))
    add_cyl(bm, base_fore, base_fore + Vector((0.05, -0.04, 1.6)), 0.08)
    masts["fore"] = (base_fore, 1.6)
    base_miz = Vector((L * 0.30, 0, sheer(0.85) + 0.65))
    add_cyl(bm, base_miz, base_miz + Vector((0, 0, 2.1)), 0.06)
    masts["mizzen"] = (base_miz, 2.1)
    # Crow's nest on the main mast.
    bmesh.ops.create_cone(bm, cap_ends=False, segments=12, radius1=0.32, radius2=0.38, depth=0.28,
                          matrix=Matrix.Translation(base_main + Vector((0, 0, 2.75))))
    # Yards (one of them skewed, half fallen).
    yards = [
        (base_main + Vector((0, 0, 2.45)), 1.5, 0.0),
        (base_main + Vector((0, 0, 1.45)), 1.75, 0.18),
        (base_fore + Vector((0, 0, 1.35)), 1.2, -0.35),
        (base_miz + Vector((0, 0, 1.75)), 1.0, 0.0),
    ]
    for c, half, tilt in yards:
        a = c + Vector((0, -half, half * math.sin(tilt)))
        b = c + Vector((0, half, -half * math.sin(tilt)))
        add_cyl(bm, a, b, 0.045, 6)
    # Rigging (shrouds) from mast tops to the rails.
    for key, (base, h) in masts.items():
        top = base + Vector((0, 0, h * 0.92))
        t = (base.x + L / 2) / L
        for side in (-1, 1):
            for k in range(3):
                rail = Vector((base.x - 0.35 + k * 0.35, side * half_width(t) * 0.98, sheer(t)))
                add_cyl(bm, top, rail, 0.012, 4)
    # Stays (mast to mast / bowsprit).
    add_cyl(bm, masts["main"][0] + Vector((0, 0, 3.2)), (-L * 0.70, 0, sheer(0.0) + 0.7), 0.012, 4)
    add_cyl(bm, masts["main"][0] + Vector((0, 0, 3.0)), masts["mizzen"][0] + Vector((0, 0, 2.0)), 0.012, 4)
    return yards


def ragged_sheet(bm, origin, width, height, holes=0.12, bulge=0.12, seed=0, along=Vector((0, 1, 0))):
    # Grid hanging down from `origin` (top centre), across `along`, with holes and a ragged bottom.
    nx, ny = 30, 24
    down = Vector((0, 0, -1))
    fwd = along.cross(down).normalized()   # belly direction
    verts = {}
    for i in range(nx + 1):
        for j in range(ny + 1):
            u, v = i / nx, j / ny
            p = origin + along * (u - 0.5) * width + down * v * height
            p += fwd * bulge * math.sin(u * math.pi) * math.sin(v * math.pi * 0.9)
            p += fwd * 0.04 * noise.noise(Vector((u * 5 + seed, v * 5, seed)))
            verts[(i, j)] = bm.verts.new(p)
    for i in range(nx):
        for j in range(ny):
            u, v = (i + 0.5) / nx, (j + 0.5) / ny
            n = noise.noise(Vector((u * 3.2 + seed * 1.7, v * 3.2, seed * 0.3))) + 0.35 * noise.noise(Vector((u * 9, v * 9, seed)))
            edge = 0.66 + 0.2 * (0.5 + 0.5 * math.sin(u * 13 + seed)) + 0.1 * noise.noise(Vector((u * 11, seed, 0.5)))
            ragged_bottom = v > edge
            if n > 0.55 - holes * 2 or ragged_bottom:
                continue
            bm.faces.new([verts[(i, j)], verts[(i + 1, j)], verts[(i + 1, j + 1)], verts[(i, j + 1)]])


def build(scene_name="GhostShip"):
    scene = bpy.data.scenes.get(scene_name) or bpy.data.scenes.new(scene_name)
    bpy.context.window.scene = scene
    for o in list(scene.collection.all_objects):
        bpy.data.objects.remove(o, do_unlink=True)
    coll = scene.collection
    bm = bmesh.new(); build_hull(bm); yards = build_rig(bm)
    hull = new_obj("GhostShip_Hull", bm, coll)
    bm = bmesh.new()
    for k, (c, half, tilt) in enumerate(yards):
        drop = 0.95 if k < 2 else 0.8
        ragged_sheet(bm, c + Vector((0.03, 0, -0.05)), half * 1.8, drop, seed=k * 3 + 1)
    sails = new_obj("GhostShip_Sails", bm, coll)
    bm = bmesh.new()
    top = Vector((L * 0.30, 0, sheer(0.85) + 0.65 + 2.05))
    ragged_sheet(bm, top + Vector((0.32, 0, 0)), 0.6, 0.38, holes=0.05, bulge=0.04, seed=9, along=Vector((1, 0, 0)))
    flag = new_obj("GhostShip_Flag", bm, coll)
    for o in (hull, sails, flag):
        for p in o.data.polygons: p.use_smooth = False
    return hull, sails, flag
