extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "D:/Blender/Projects/Portifolio/godot_work/v9_%s.png" % name
	var error := root.get_texture().get_image().save_png(path)
	print("V9_PREVIEW ", name, " error=", error)

func run() -> void:
	root.size = Vector2i(1280, 720)
	var world := (load("res://MainWorld.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in range(8): await process_frame
	await shot("boat")
	world.camera.focus_island(world.islands[0])
	world.camera._process(2.5)
	for i in range(3): await process_frame
	await shot("island")
	world.camera.show_overview()
	world.camera._process(2.5)
	for i in range(3): await process_frame
	await shot("overview")
	quit()
