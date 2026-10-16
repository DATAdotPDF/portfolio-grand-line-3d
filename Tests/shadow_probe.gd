extends SceneTree

## Sombra dos modelos altos com sol baixo (WorldDecor.limit_shadows): antes/depois com o monólito
## rúnico partido. Sol ~ELEV° acima do horizonte no rochedo; barco a 170 m do lado da sombra; uma foto
## olhando ao longo da sombra (como o print do Pedro) e outra olhando para o rochedo.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/shadow_probe.gd
## Saída: Builds/ShadowProbe/{antes,depois}_{sombra,rochedo}.jpg

var world: Node3D
const ELEV := 14.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/ShadowProbe"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	await create_timer(1.5).timeout
	world._start_sailing()
	world.select_time("auto")
	world.graphics.set_mode("alto")
	world.ship.controls_override = true
	var decor: Node = world.world_decor
	var item: Dictionary = {}
	for it in decor.items:
		if it.kind == "split_monolith_runes":
			item = it
	var rock: Vector3 = (item.root as Node3D).global_position
	var up := rock.normalized()
	# Hora em que o sol está ~ELEV° acima do horizonte ali (subindo).
	var best := 0.0
	var best_err := INF
	for k in 2000:
		var t := 0.15 + 0.2 * k / 2000.0
		world.clock.set_time(t, true)
		var elev := rad_to_deg(asin(up.dot(world.clock.sun_direction)))
		if absf(elev - ELEV) < best_err:
			best_err = absf(elev - ELEV)
			best = t
	world.clock.set_time(best, true)
	var sun: Vector3 = world.clock.sun_direction
	var away := (-sun).slide(up).normalized()
	var boat: Vector3 = world.ocean.surface_at(rock + away * 95.0)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 3000.0
	root.add_child(cam)
	print("SHADOW hora=%.3f sol=%.1f°" % [best, rad_to_deg(asin(up.dot(sun)))])
	for mode in ["antes", "depois"]:
		decor.limit_shadows = mode == "depois"
		for it in decor.items:
			if it.get("casts", false):
				it.shadow_on = mode == "antes"
				for mesh in (it.model as Node3D).find_children("*", "MeshInstance3D", true, false):
					(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if mode == "antes" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.ship.global_position = boat
		world.clock.set_time(best, true)
		var b_up := boat.normalized()
		for view in ["sombra", "rochedo"]:
			for f in 300:
				for layer in world.find_children("*", "CanvasLayer", true, false):
					layer.visible = false
				world.clock.set_time(best, true)
				cam.make_current()
				if view == "sombra":
					cam.look_at_from_position(boat + b_up * 6.0 - away * 8.0, boat + away * 120.0, b_up)
				else:
					cam.look_at_from_position(boat + b_up * 6.0 + away * 10.0, rock + up * 25.0, b_up)
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/ShadowProbe/%s_%s.jpg" % [mode, view]), 0.88)
			print("PRINT %s_%s" % [mode, view])
	quit()
