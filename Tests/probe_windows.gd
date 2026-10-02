extends SceneTree

## Gera, para cada ilha, uma imagem da textura base com os pixels que o shader
## de janelas acenderia pintados de magenta (para calibrar a máscara).

const FILES := ["island_sobre", "island_experiencia", "island_formacao", "island_projetos", "island_contato"]

func _initialize() -> void:
	for name in FILES:
		var tex := load("res://Assets/Optimized/%s_0.jpg" % name) as Texture2D
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.resize(512, 512)
		var count := 0
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c := img.get_pixel(x, y)
				if _window(c):
					img.set_pixel(x, y, Color(1, 0, 1))
					count += 1
		img.save_png(ProjectSettings.globalize_path("res://Documentation/Previews/winmask_%s.png" % name))
		print("WINMASK ", name, " ", count)
	quit()

func _window(c: Color) -> bool:
	return c.b > c.r + 0.18 and c.b > c.g + 0.02 and c.v < 0.75 and c.v > 0.2
