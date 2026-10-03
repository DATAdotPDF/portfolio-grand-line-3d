extends SceneTree

## Cartão de abertura (atalhos "Ir direto para") no PC e em retrato.
## Uso: Godot.exe --path . --script res://Tests/intro_probe.gd [-- portrait]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var portrait := OS.get_cmdline_user_args().has("portrait")
	root.size = Vector2i(390, 844) if portrait else Vector2i(1600, 900)
	var world := (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = true
	root.add_child(world)
	world.clock.set_time(0.42, true)
	await create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/intro_%s.jpg" % ("mobile" if portrait else "desktop")), 0.85)
	print("INTRO_PROBE ok")
	quit()
