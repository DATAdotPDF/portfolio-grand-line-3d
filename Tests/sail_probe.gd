extends SceneTree

## Vela de perto, de vários ângulos (procura defeito de textura).
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/sail_probe.gd

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/SailProbe/%s.jpg" % name), 0.9)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/SailProbe"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(2.0).timeout
	world._start_sailing()
	world.hud.visible = false
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1, 0, 1)
	await create_timer(5.0).timeout  # ganha velocidade (vela cheia)
	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.make_current()
	var views := {"side_r": Vector3(6, 3, 0), "side_l": Vector3(-6, 3, 0), "front": Vector3(0, 3, -7), "back": Vector3(0, 3, 7), "front_r": Vector3(4, 4, -5)}
	for name in views:
		for f in 30:
			var t: Transform3D = world.ship.get_global_transform_interpolated()
			cam.global_position = t * views[name]
			cam.look_at(t * Vector3(0, 2.2, 0), t.basis.y)
			await process_frame
		await still(name)
	quit()
