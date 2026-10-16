extends SceneTree

## Tornado camada por camada (como no estudo do Thiago): fotografa cada parte sozinha e o conjunto.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/tornado_layers_probe.gd

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/Encounters/%s.jpg" % name), 0.85)
	print("PRINT ", name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/Encounters"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.hud.visible = false
	var cyclone: Node3D = world.weather.cyclones[0]
	var c: Vector3 = cyclone.center
	var up := c.normalized()
	var t := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var cam := Camera3D.new()
	cam.fov = 55.0
	world.add_child(cam)
	cam.global_position = c * world.planet_radius - t * 190.0 + up * 55.0
	cam.look_at(c * world.planet_radius + up * 55.0, up)
	cam.make_current()
	var swirl: Node3D = cyclone.get_node("Swirl")
	var parts := {
		"1_storm_cloud": [cyclone.cloud],
		"2_cloud_ring": [cyclone.ring],
		"3a_core": [cyclone.layer_nodes[0]],
		"3b_middle": [cyclone.layer_nodes[1]],
		"3c_outer": [cyclone.layer_nodes[2]],
		"3d_ribbons": [cyclone.ribbons],
		"4_water_ring": [swirl, cyclone.splash],
	}
	var all: Array = [cyclone.cloud, cyclone.ring, cyclone.ribbons, swirl, cyclone.splash] + cyclone.layer_nodes
	for key in parts:
		for n in all:
			n.visible = parts[key].has(n)
		await create_timer(0.6).timeout
		await still("tl_" + key)
	for n in all:
		n.visible = true
	await create_timer(0.6).timeout
	await still("tl_5_all")
	quit()
