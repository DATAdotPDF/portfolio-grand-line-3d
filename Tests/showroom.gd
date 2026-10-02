extends SceneTree

## Vídeo-vitrine para o LinkedIn: tour roteirizado gravado pelo Movie Maker do Godot.
## Uso (1080p, 30 fps, quadros sem engasgo porque o tempo é fixo):
##   Godot.exe --path . --write-movie Builds/Showroom/showroom.avi --fixed-fps 30 --resolution 1920x1080 --script res://Tests/showroom.gd

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

## Quadro de conferência (fora do vídeo): Builds/Showroom/review_NN.png
var review := 0
func still() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/Showroom/review_%02d.jpg" % review), 0.8)
	review += 1

## Gira o globo do mapa aos poucos (como alguém arrastando).
func spin_globe(seconds: float, speed: Vector2) -> void:
	var end := seconds
	while end > 0.0:
		await process_frame
		world.camera.drag_orbit(speed)
		end -= 1.0 / 30.0

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = true
	root.add_child(world)
	world.clock.set_time(0.40, true)
	world.select_time("day")
	# 1. Abertura: cartão de apresentação com a câmera orbitando a ilha.
	await wait(5.0)
	await still()
	await wait(1.0)
	# 2. Zarpar e navegar rumo à primeira ilha.
	world._start_sailing()
	await wait(1.5)
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1, 0.12, 0)
	await wait(5.0)
	await still()
	world.ship.test_controls = Vector3(1, -0.2, 1)
	await wait(4.0)
	world.ship.test_controls = Vector3(1, 0, 1)
	await wait(2.0)
	# 3. Mapa 3D: o globo gira.
	world.toggle_map()
	await wait(3.0)
	# Giro medido em Tests/map_probe.gd: termina com 3 ilhas à vista ao mesmo tempo.
	world.camera.overview_direction = world.ship.global_position.normalized()
	await spin_globe(4.27, Vector2(-9, 6))
	await wait(1.0)
	await still()
	await wait(0.5)
	# 4. As cinco ilhas, cada uma com o painel aberto.
	world.ship.test_controls = Vector3.ZERO
	for index in range(5):
		world.hud.island_pressed.emit(index)
		await wait(2.5)
		# A câmera saindo do mapa nem sempre dispara a visita: abre o painel na mão.
		if not world.hud.island_panel.visible:
			world.hud.show_island(index, false)
		await wait(1.5 if index < 4 else 0.5)
		await still()
		await wait(1.0)
	# 5. A noite cai na última ilha: luzes, farol, fogueira.
	world.select_time("night")
	await wait(4.5)
	await still()
	# 6. De volta ao mar à noite, e fim.
	world._return_to_navigation()
	world.ship.test_controls = Vector3(1, 0.1, 1)
	await wait(4.0)
	await still()
	await wait(1.0)
	quit()
