extends SceneTree

## Pontos de interesse (WorldDecor): fotografa cada tipo com a câmera do jogo, chegando de barco,
## e o mapa. Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/world_decor_probe.gd

var world: Node3D
var out_dir := "res://Builds/WorldDecor"

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("%s/%s.jpg" % [out_dir, name]), 0.85)
	print("PRINT ", name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.hud._set_carta_open(false)
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	var decor: Node = world.world_decor
	var counts := {}
	for item in decor.items:
		counts[item.kind] = int(counts.get(item.kind, 0)) + 1
	print("DECOR ", counts)
	var done := {}
	for item in decor.items:
		if done.has(item.kind):
			continue
		done[item.kind] = true
		var dir: Vector3 = item.dir
		var size: float = maxf(float(item.height), 4.0)
		var back := maxf(22.0, size * 1.6)
		var tangent := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
		var pos: Vector3 = (dir * world.planet_radius - tangent * back).normalized() * world.planet_radius
		var surface: Vector3 = world.ocean.surface_at(pos)
		var up := surface.normalized()
		var forward := tangent.slide(up).normalized()
		world.ship.heading = forward
		world.ship.global_transform = Transform3D(Basis(forward.cross(up).normalized(), up, -forward), surface)
		await create_timer(2.5).timeout
		await still("decor_%s" % item.kind)
	world.select_time("night")
	for item in decor.items:
		if item.kind == "volcanic_island":
			var dir: Vector3 = item.dir
			var tangent := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
			var surface: Vector3 = world.ocean.surface_at((dir * world.planet_radius - tangent * 130.0).normalized() * world.planet_radius)
			var up := surface.normalized()
			var forward := tangent.slide(up).normalized()
			world.ship.heading = forward
			world.ship.global_transform = Transform3D(Basis(forward.cross(up).normalized(), up, -forward), surface)
			await create_timer(3.0).timeout
			await still("decor_volcano_night")
			break
	world.select_time("day")
	world.toggle_map()
	await create_timer(3.0).timeout
	await still("decor_map")
	quit()
