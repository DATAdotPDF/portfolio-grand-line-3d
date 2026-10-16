extends SceneTree

## Céu: flare do sol (olhando perto do sol e com o sol de lado) e nuvens do céu.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/sky_probe.gd
## Saída: Builds/SkyProbe/*.jpg

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/SkyProbe/%s.jpg" % name), 0.85)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/SkyProbe"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(2.0).timeout
	world._start_sailing()
	world.hud.visible = false
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.far = 4000.0
	world.add_child(cam)
	cam.make_current()
	var to_sun: Vector3 = world.clock.sun_direction
	var up: Vector3 = world.ship.global_position.normalized()
	var flat_sun := to_sun.slide(up).normalized() if to_sun.slide(up).length() > 0.05 else up.cross(Vector3.RIGHT).normalized()
	var side := up.cross(flat_sun).normalized()
	var shots := {
		"sun_center": to_sun,
		"sun_side": to_sun.rotated(up, deg_to_rad(25.0)).rotated(side, deg_to_rad(-8.0)),
		"clouds_horizon": flat_sun.rotated(up, deg_to_rad(120.0)) + up * 0.25,
		"clouds_up": flat_sun.rotated(up, deg_to_rad(-100.0)) + up * 0.8,
	}
	print("SKY sun_elev=%.2f" % to_sun.dot(up))
	for name in shots:
		for f in 30:
			var eye: Vector3 = world.ship.global_position + up * 5.0
			cam.global_position = eye
			cam.look_at(eye + (shots[name] as Vector3).normalized() * 50.0, up)
			await process_frame
		await still(name)
	quit()
