extends SceneTree

## Mapa com tempestade: o barco dentro de uma tempestade (chuva pessoal, véu, trovões) e então o
## mapa aberto. No mapa não pode aparecer nada colado na câmera (riscos de chuva sobre o globo).
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/map_effects_probe.gd

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/Encounters/%s.jpg" % name), 0.85)
	print("PRINT ", name)

func run() -> void:
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	# Leva a tempestade até o barco e a deixa no máximo.
	var storm: Node3D = world.weather.storms[0]
	storm.center = world.ship.global_position.normalized()
	storm.set("surge", 2.0)
	await create_timer(4.0).timeout
	print("MAP_FX before badness=%.2f rain=%s veil=%s" % [world.weather.badness, world.weather.personal_rain.emitting, world.weather.overlay.visible])
	await shot("mapfx_1_storm")
	world.toggle_map()
	await create_timer(4.0).timeout
	print("MAP_FX map space_view=%.2f rain_visible=%s veil=%s" % [world.space_view, world.weather.personal_rain.visible, world.weather.overlay.visible])
	await shot("mapfx_2_map")
	quit()
