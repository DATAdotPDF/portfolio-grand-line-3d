extends SceneTree

## Vídeo da entrada no jogo: abertura (órbita na ilha) → "começar a navegar" → a câmera dá a volta
## no barco (lado → frente → outro lado → popa) e assume a câmera de terceira pessoa.
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie Builds/Videos/entrada.avi
##      --script res://Tests/intro_camera_video.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = true
	root.add_child(world)
	world.select_time("day")
	for i in 90:
		await process_frame
	print("INTRO start_sailing")
	world._start_sailing()
	for i in 270:
		await process_frame
	print("INTRO done state=%d" % int(world.camera.state))
	quit()
