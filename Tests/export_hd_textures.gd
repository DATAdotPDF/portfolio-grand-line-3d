extends SceneTree

## Texturas originais dos modelos para o site (carregadas no jogo perto do barco: Scripts/HDTextures.gd).
## Para cada modelo da lista que tem textura acima da base do site, abre a cena ORIGINAL (este
## projeto usa os GLBs do Meshy), pega as imagens-fonte de cada material (cor, metal/rugosidade,
## normal) na resolução original e grava, já no formato da placa de vídeo, com mipmaps:
##   desktop: S3TC (DXT), até 4096   ·   celular: ETC2, até 2048
## Saída: <out>/<perfil>/<id>/<n>.res (no manifesto, "file" é <id>/<n>.res) e <out>/hd_<perfil>.json (chave = caminho do GLB no jogo;
## materiais pelo nome, igual nas variantes do site).
## Uso: Godot.exe --headless --path . --script res://Tests/export_hd_textures.gd -- --list=<arquivo> --out=<pasta>

const PROFILES := {"desktop": {"max": 4096, "base": 2048, "compress": Image.COMPRESS_S3TC},
	"mobile": {"max": 2048, "base": 1024, "compress": Image.COMPRESS_ETC2}}
const PROPS := ["albedo_texture", "normal_texture", "metallic_texture", "roughness_texture"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var list_file := ""
	var out_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--list="):
			list_file = arg.trim_prefix("--list=")
		elif arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	var models := FileAccess.get_file_as_string(list_file).split("\n", false)
	var manifests := {"desktop": {}, "mobile": {}}
	var done := {}
	var total := {"desktop": 0, "mobile": 0}
	for rel in models:
		var res_path := "res://" + rel.strip_edges()
		if not ResourceLoader.exists(res_path):
			continue
		var scene: Node = (load(res_path) as PackedScene).instantiate()
		var id := rel.get_file().get_basename().md5_text().substr(0, 10)
		var entries := {"desktop": [], "mobile": []}
		var seen := {}
		for mesh in scene.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s) as StandardMaterial3D
				if mat == null:
					continue
				for prop in PROPS:
					var tex := mat.get(prop) as Texture2D
					if tex == null or tex.resource_path.is_empty():
						continue
					var key: String = mat.resource_name + "|" + prop
					if seen.has(key):
						continue
					seen[key] = true
					var src := ProjectSettings.globalize_path(tex.resource_path)
					var image := Image.load_from_file(src)
					if image == null or image.is_empty():
						continue
					var side := maxi(image.get_width(), image.get_height())
					for profile in PROFILES:
						var spec: Dictionary = PROFILES[profile]
						# Só vale a pena se a original passa da base do site nesse perfil.
						if side <= int(spec.base):
							continue
						var file: String = "%s/%s.res" % [id, tex.resource_path.get_file().get_basename().md5_text().substr(0, 8)]
						var disk: String = out_dir.path_join(profile).path_join(file)
						if not done.has(profile + file):
							var img := image.duplicate() as Image
							if side > int(spec.max):
								var k: float = float(spec.max) / side
								img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
							img.convert(Image.FORMAT_RGB8 if prop != "albedo_texture" or not img.detect_alpha() else Image.FORMAT_RGBA8)
							img.generate_mipmaps()
							img.compress(spec.compress, Image.COMPRESS_SOURCE_SRGB if prop == "albedo_texture" else Image.COMPRESS_SOURCE_GENERIC)
							DirAccess.make_dir_recursive_absolute(disk.get_base_dir())
							ResourceSaver.save(img, disk, ResourceSaver.FLAG_COMPRESS)
							done[profile + file] = FileAccess.get_file_as_bytes(disk).size()
							total[profile] += int(done[profile + file])
						(entries[profile] as Array).append({"material": mat.resource_name, "prop": prop, "file": file,
							"size": done[profile + file], "v": FileAccess.get_md5(disk).substr(0, 10)})
		scene.free()
		for profile in entries:
			if not (entries[profile] as Array).is_empty():
				manifests[profile][res_path] = entries[profile]
		print("HD %s: desktop %d, celular %d texturas" % [rel.get_file(), (entries.desktop as Array).size(), (entries.mobile as Array).size()])
	for profile in manifests:
		var f := FileAccess.open(out_dir.path_join("hd_%s.json" % profile), FileAccess.WRITE)
		f.store_string(JSON.stringify({"dir": "hd/" + profile, "models": manifests[profile]}, "\t"))
		print("HD_TOTAL %s: %d modelos, %.1f MB" % [profile, (manifests[profile] as Dictionary).size(), total[profile] / 1048576.0])
	quit()
