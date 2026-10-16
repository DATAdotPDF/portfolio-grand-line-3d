extends SceneTree

## Mapa: sol no canto e lado da noite. Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/map_sun_probe.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	await create_timer(2.0).timeout
	world._start_sailing()
	world.select_time("auto")
	await create_timer(1.0).timeout
	world.toggle_map()
	await create_timer(3.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/Encounters/map_sun.jpg"), 0.85)
	quit()
