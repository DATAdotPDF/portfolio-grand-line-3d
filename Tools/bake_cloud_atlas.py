# Gera o atlas de tufos de nuvem (técnica de "cartões" do Sea of Thieves, textura nossa).
# Cada tufo é um volume procedural renderizado no Cycles, três vezes, com o sol vindo da
# direita, de cima e da esquerda. O atlas guarda: R = luz da direita, G = luz de cima,
# B = luz da esquerda, A = densidade (alfa). O shader do jogo mistura R/G/B conforme o sol.
#
# Uso (fora do Godot, Blender 5.x):
#   D:\Blender\blender.exe -b --factory-startup -P Tools/bake_cloud_atlas.py -- <saida.png> [celula] [amostras] [variantes]
# Padrão: Assets/Clouds/cloud_atlas.png, células de 512 px, 4x4 = 16 variantes.
import bpy, math, random, sys, os, time
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else "Assets/Clouds/cloud_atlas.png")
CELL = int(argv[1]) if len(argv) > 1 else 512
SAMPLES = int(argv[2]) if len(argv) > 2 else 48
COUNT = int(argv[3]) if len(argv) > 3 else 16
GRID = int(math.ceil(math.sqrt(COUNT)))
TMP = os.path.join(os.path.dirname(OUT), "_bake_tmp")
os.makedirs(TMP, exist_ok=True)

# Tipos de tufo: 0..7 couve-flor (torre), 8..11 lâmina (bigorna), 12..15 fiapo (bordas e braços).
def kind_of(i):
    return "billow" if i < 8 else ("sheet" if i < 12 else "wisp")

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.volume_bounces = 2
    scene.cycles.volume_step_rate = 1.0
    scene.cycles.volume_max_steps = 256
    scene.render.film_transparent = True
    scene.render.resolution_x = CELL
    scene.render.resolution_y = CELL
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("Black")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scene.world = world
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scene.cycles.device = "GPU"
    except Exception:
        scene.cycles.device = "CPU"
    return scene

def cloud_material(rng, kind):
    mat = bpy.data.materials.new("Cloud")
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial")
    vol = nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (1, 1, 1, 1)
    vol.inputs["Anisotropy"].default_value = 0.25
    links.new(vol.outputs["Volume"], out.inputs["Volume"])
    coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    # Lâmina: achata na vertical; fiapo: estica na horizontal.
    squash = {"billow": (1.0, 1.0, 1.0), "sheet": (1.0, 1.0, 2.2), "wisp": (0.9, 1.0, 1.6)}[kind]
    mapping.inputs["Scale"].default_value = squash
    links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    # Deformação do espaço por ruído (domain warp): as esferas viram gomos irregulares.
    warp_noise = nodes.new("ShaderNodeTexNoise"); warp_noise.inputs["Scale"].default_value = 2.2
    warp_noise.inputs["Detail"].default_value = 3.0
    links.new(mapping.outputs["Vector"], warp_noise.inputs["Vector"])
    warp_center = nodes.new("ShaderNodeVectorMath"); warp_center.operation = "SUBTRACT"
    warp_center.inputs[1].default_value = (0.5, 0.5, 0.5)
    links.new(warp_noise.outputs["Color"], warp_center.inputs[0])
    warp_scale = nodes.new("ShaderNodeVectorMath"); warp_scale.operation = "SCALE"
    warp_scale.inputs["Scale"].default_value = {"billow": 0.35, "sheet": 0.3, "wisp": 0.45}[kind]
    links.new(warp_center.outputs["Vector"], warp_scale.inputs[0])
    warped = nodes.new("ShaderNodeVectorMath"); warped.operation = "ADD"
    links.new(mapping.outputs["Vector"], warped.inputs[0])
    links.new(warp_scale.outputs["Vector"], warped.inputs[1])
    # Campo de esferas: max(1 - d/r).
    count = {"billow": rng.randint(16, 22), "sheet": rng.randint(12, 16), "wisp": rng.randint(5, 8)}[kind]
    field = None
    for k in range(count):
        if kind == "billow":
            # Couve-flor: bolotas empilhadas, maiores embaixo.
            # Couve-flor: base larga e reta, gomos menores subindo.
            y = rng.uniform(-0.3, 0.5)
            spread = 0.55 - (y + 0.3) * 0.35
            c = (rng.uniform(-spread, spread), rng.uniform(-0.15, 0.15), y)
            r = rng.uniform(0.15, 0.3) * (1.1 - (y + 0.3) * 0.3)
        elif kind == "sheet":
            c = (rng.uniform(-0.55, 0.55), rng.uniform(-0.2, 0.2), rng.uniform(-0.12, 0.12))
            r = rng.uniform(0.28, 0.42)
        else:
            t = k / max(count - 1, 1)
            c = (-0.55 + 1.1 * t, rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1) + 0.15 * math.sin(t * 3.0))
            r = rng.uniform(0.26, 0.36) * (1.0 - 0.45 * t)
        d = nodes.new("ShaderNodeVectorMath"); d.operation = "DISTANCE"
        d.inputs[1].default_value = c
        links.new(warped.outputs["Vector"], d.inputs[0])
        div = nodes.new("ShaderNodeMath"); div.operation = "DIVIDE"; div.inputs[1].default_value = r
        links.new(d.outputs["Value"], div.inputs[0])
        one = nodes.new("ShaderNodeMath"); one.operation = "SUBTRACT"; one.inputs[0].default_value = 1.0
        links.new(div.outputs["Value"], one.inputs[1])
        if field is None:
            field = one
        else:
            mx = nodes.new("ShaderNodeMath"); mx.operation = "MAXIMUM"
            links.new(field.outputs["Value"], mx.inputs[0])
            links.new(one.outputs["Value"], mx.inputs[1])
            field = mx
    # Ruído em duas escalas: gomos (couve-flor) e erosão fina das bordas.
    seed_offset = (rng.uniform(0, 100), rng.uniform(0, 100), rng.uniform(0, 100))
    add_offset = nodes.new("ShaderNodeVectorMath"); add_offset.operation = "ADD"
    add_offset.inputs[1].default_value = seed_offset
    links.new(mapping.outputs["Vector"], add_offset.inputs[0])
    big = nodes.new("ShaderNodeTexNoise"); big.inputs["Scale"].default_value = {"billow": 3.2, "sheet": 2.4, "wisp": 3.0}[kind]
    big.inputs["Detail"].default_value = 4.0; big.inputs["Roughness"].default_value = 0.55
    links.new(add_offset.outputs["Vector"], big.inputs["Vector"])
    fine = nodes.new("ShaderNodeTexNoise"); fine.inputs["Scale"].default_value = 9.0
    fine.inputs["Detail"].default_value = 8.0; fine.inputs["Roughness"].default_value = 0.65
    links.new(add_offset.outputs["Vector"], fine.inputs["Vector"])
    mix_noise = nodes.new("ShaderNodeMath"); mix_noise.operation = "MULTIPLY_ADD"
    links.new(fine.outputs["Fac"], mix_noise.inputs[0]); mix_noise.inputs[1].default_value = 0.35
    links.new(big.outputs["Fac"], mix_noise.inputs[2])
    centered = nodes.new("ShaderNodeMath"); centered.operation = "SUBTRACT"
    links.new(mix_noise.outputs["Value"], centered.inputs[0]); centered.inputs[1].default_value = 0.67
    amount = {"billow": 1.0, "sheet": 0.9, "wisp": 1.2}[kind]
    scaled = nodes.new("ShaderNodeMath"); scaled.operation = "MULTIPLY"
    links.new(centered.outputs["Value"], scaled.inputs[0]); scaled.inputs[1].default_value = amount
    total = nodes.new("ShaderNodeMath"); total.operation = "ADD"
    links.new(field.outputs["Value"], total.inputs[0]); links.new(scaled.outputs["Value"], total.inputs[1])
    ramp = nodes.new("ShaderNodeMapRange")
    ramp.inputs["From Min"].default_value = 0.0
    ramp.inputs["From Max"].default_value = {"billow": 0.35, "sheet": 0.4, "wisp": 0.55}[kind]
    links.new(total.outputs["Value"], ramp.inputs["Value"])
    dens = nodes.new("ShaderNodeMath"); dens.operation = "MULTIPLY"
    links.new(ramp.outputs["Result"], dens.inputs[0])
    dens.inputs[1].default_value = {"billow": 14.0, "sheet": 9.0, "wisp": 5.0}[kind]
    # Base reta (fundo plano do cúmulo): corta a densidade abaixo de z = -0.4.
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(mapping.outputs["Vector"], sep.inputs[0])
    floor_cut = nodes.new("ShaderNodeMapRange")
    floor_cut.inputs["From Min"].default_value = -0.46 if kind == "billow" else -0.25
    floor_cut.inputs["From Max"].default_value = -0.36 if kind == "billow" else -0.15
    links.new(sep.outputs["Z"], floor_cut.inputs["Value"])
    cut = nodes.new("ShaderNodeMath"); cut.operation = "MULTIPLY"
    links.new(dens.outputs["Value"], cut.inputs[0]); links.new(floor_cut.outputs["Result"], cut.inputs[1])
    links.new(cut.outputs["Value"], vol.inputs["Density"])
    return mat

def build_variant(i):
    scene = reset_scene()
    rng = random.Random(1000 + i * 77)
    kind = kind_of(i)
    bpy.ops.mesh.primitive_cube_add(size=2.4)
    domain = bpy.context.active_object
    domain.data.materials.append(cloud_material(rng, kind))
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.4
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (0, -6, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 7.0
    sun_data.angle = math.radians(8)
    sun = bpy.data.objects.new("Sun", sun_data)
    scene.collection.objects.link(sun)
    return scene, sun

# Direção em que a luz VIAJA (o sol do Blender aponta para -Z local). Um pouco de frente
# (+Y, vindo do lado da câmera) para não virar só contraluz.
from mathutils import Vector
TRAVEL = {"right": Vector((-1.0, 0.35, -0.25)), "top": Vector((0.0, 0.35, -1.0)), "left": Vector((1.0, 0.35, -0.25))}

def sun_rotation(name):
    return TRAVEL[name].normalized().to_track_quat("-Z", "Y").to_euler()

atlas = np.zeros((GRID * CELL, GRID * CELL, 4), dtype=np.float32)
start = time.time()
for i in range(COUNT):
    scene, sun = build_variant(i)
    channels = {}
    alpha = None
    for name in ("right", "top", "left"):
        sun.rotation_mode = "XYZ"
        sun.rotation_euler = sun_rotation(name)
        path = os.path.join(TMP, f"v{i:02d}_{name}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(path)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(CELL, CELL, 4)
        bpy.data.images.remove(img)
        lum = px[..., 0] * 0.3 + px[..., 1] * 0.59 + px[..., 2] * 0.11
        # Desfaz o pré-multiplicado do alfa para a luz ficar "por dentro" do tufo.
        a = px[..., 3]
        channels[name] = np.where(a > 0.001, lum / np.maximum(a, 0.001), 0.0)
        alpha = a if alpha is None else np.maximum(alpha, a)
    gx, gy = i % GRID, i // GRID
    # pixels do Blender começam embaixo; o atlas é montado de cima para baixo depois.
    cell = np.stack([channels["right"], channels["top"], channels["left"], alpha], axis=-1)
    atlas[(GRID - 1 - gy) * CELL:(GRID - gy) * CELL, gx * CELL:(gx + 1) * CELL] = cell
    print(f"CLOUD_ATLAS variant {i} ({kind_of(i)}) done in {time.time() - start:.0f}s", flush=True)

atlas = np.clip(atlas, 0.0, 1.0)
img = bpy.data.images.new("cloud_atlas", GRID * CELL, GRID * CELL, alpha=True)
img.colorspace_settings.name = "Non-Color"
img.pixels = atlas.ravel()
img.filepath_raw = OUT
img.file_format = "PNG"
img.save()
print(f"CLOUD_ATLAS saved {OUT} {GRID * CELL}px total {time.time() - start:.0f}s", flush=True)
