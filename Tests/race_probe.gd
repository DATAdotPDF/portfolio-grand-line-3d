extends SceneTree

## Desafio: rota até a boia mais próxima, tela de resultado com ranking e carta recolhível.
## Uso: Godot.exe --path . --script res://Tests/race_probe.gd

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/race_%s%s.jpg" % [name, "_mobile" if root.size.x < 600 else ""]), 0.85)
	print("RACE_PROBE ", name)

func run() -> void:
	var portrait := OS.get_cmdline_user_args().has("portrait")
	root.size = Vector2i(390, 844) if portrait else Vector2i(1600, 900)
	var world := (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.clock.set_time(0.42, true)
	await create_timer(2.0).timeout
	world.hud.challenge_confirmed.emit()
	await create_timer(3.0).timeout
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1, 0, 1)
	await create_timer(2.0).timeout
	print("RACE_PROBE route_target=", world.route_line.target.name if world.route_line.target else "none", " cannon=", world.hud.cannon_label.text)
	await shot("running")
	world.naval._finish_time_attack(false)
	await create_timer(4.0).timeout
	await shot("result")
	world.hud.race_result.visible = false
	world.hud._set_carta_open(false)
	await create_timer(0.5).timeout
	await shot("carta_closed")
	quit()
