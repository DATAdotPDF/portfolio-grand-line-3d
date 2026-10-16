"""Folha de comparação original | desktop | celular de cada variante web (Builds/WebVariants/).
Uso: python Tools/compare_web_variants.py   (precisa das variantes de Tools/make_web_variants.py)
"""
import os
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLENDER = os.environ.get("BLENDER", r"D:\Blender\blender.exe")
OUT = os.path.join(ROOT, "Builds", "WebVariants")
RENDER = r'''
import bpy, sys, math
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a[0])
ms = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.context.view_layer.update()
vs = [o.matrix_world @ Vector(c) for o in ms for c in o.bound_box]
mn = Vector([min(v[i] for v in vs) for i in range(3)]); mx = Vector([max(v[i] for v in vs) for i in range(3)])
c = (mn + mx) / 2; size = max(mx - mn)
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.color_type = "TEXTURE"
sc.display.shading.light = "STUDIO"
sc.render.resolution_x = 480; sc.render.resolution_y = 400
cd = bpy.data.cameras.new("c"); cam = bpy.data.objects.new("c", cd); sc.collection.objects.link(cam); sc.camera = cam
cd.type = "ORTHO"; cd.ortho_scale = size * 1.1
d = Vector((math.cos(math.radians(35)), math.sin(math.radians(35)), 0.55)).normalized()
cam.location = c + d * size * 3
cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
sc.render.filepath = a[1]
bpy.ops.render.render(write_still=True)
'''


def main():
	os.makedirs(OUT, exist_ok=True)
	script = os.path.join(OUT, "_render.py")
	open(script, "w", encoding="utf-8").write(RENDER)
	rows = []
	for dirpath, _, files in os.walk(os.path.join(ROOT, "Assets", "WebDesktop")):
		for name in files:
			if not name.endswith(".glb"):
				continue
			rel = os.path.relpath(os.path.join(dirpath, name), os.path.join(ROOT, "Assets", "WebDesktop"))
			key = rel.replace(os.sep, "_")[:-4]
			sources = [os.path.join(ROOT, "Assets", rel), os.path.join(ROOT, "Assets", "WebDesktop", rel), os.path.join(ROOT, "Assets", "WebMobile", rel)]
			pngs = []
			for tag, src in zip(("orig", "desk", "mob"), sources):
				png = os.path.join(OUT, "%s_%s.png" % (key, tag))
				if not os.path.exists(png):
					subprocess.run([BLENDER, "-b", "--factory-startup", "-P", script, "--", src, png], capture_output=True)
				pngs.append(png)
			row = os.path.join(OUT, "%s_row.jpg" % key)
			label = key.replace("Meshy_AI_", "")[:40]
			subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", pngs[0], "-i", pngs[1], "-i", pngs[2], "-filter_complex",
				"[0][1][2]hstack=3", row])
			rows.append(row)
			print("COMPARE", label, flush=True)
	# Folhas de 6 linhas cada.
	for i in range(0, len(rows), 6):
		chunk = rows[i:i + 6]
		args = []
		for r in chunk:
			args += ["-i", r]
		subprocess.run(["ffmpeg", "-y", "-loglevel", "error"] + args + ["-filter_complex", "vstack=%d" % len(chunk) if len(chunk) > 1 else "null",
			os.path.join(OUT, "sheet_%02d.jpg" % (i // 6 + 1))])
	print("SHEETS", (len(rows) + 5) // 6)


if __name__ == "__main__":
	main()
