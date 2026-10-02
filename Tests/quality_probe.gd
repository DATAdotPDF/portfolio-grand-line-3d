extends SceneTree

## Simula uma máquina fraca (carga artificial por quadro) e confere se o modo Auto
## desce de nível sozinho e avisa no HUD.

var heavy := false

func _initialize() -> void:
	process_frame.connect(func():
		if heavy:
			var end := Time.get_ticks_usec() + 60000
			while Time.get_ticks_usec() < end:
				pass)
	call_deferred("run")

func run() -> void:
	var world := (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	await create_timer(2.0).timeout
	print("QUALITY start tier=", world.graphics.tier)
	world.graphics.tier_changed.connect(func(tier, automatic): print("QUALITY changed tier=", tier, " automatic=", automatic, " fps=", Engine.get_frames_per_second()))
	heavy = true
	await create_timer(30.0).timeout
	heavy = false
	print("QUALITY end tier=", world.graphics.tier, " toast=", world.hud.toast != null and world.hud.toast.visible)
	world.graphics.set_mode("alto")
	print("QUALITY forced tier=", world.graphics.tier, " note=", world.hud.graphics_note.text)
	quit()
