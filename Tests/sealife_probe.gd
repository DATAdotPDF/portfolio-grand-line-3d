extends SceneTree

## Golfinhos e peixes com a câmera do jogo (barco andando em mar calmo).
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/sealife_probe.gd
## Saída: Builds/SeaLifeProbe/*.jpg

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/SeaLifeProbe/%s.jpg" % name), 0.85)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/SeaLifeProbe"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.clock.set_time(0.40, true)
	world.select_time("day")
	await create_timer(2.0).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1, 0, 0)
	# Sem forçar: o primeiro grupo deve vir sozinho em ~25 s navegando.
	var waited := 0.0
	while world.sea_life.dolphins.is_empty() and waited < 45.0:
		await create_timer(1.0).timeout
		waited += 1.0
	print("SEALIFE natural_pod_after=%.0fs count=%d" % [waited, world.sea_life.dolphins.size()])
	if world.sea_life.dolphins.is_empty():
		world.sea_life.spawn_pod(3)
	for i in 6:
		await create_timer(1.3).timeout
		await still("dolphins_%d" % i)
	print("SEALIFE pod=%d ship_speed=%.1f nearest=%.1f m" % [world.sea_life.dolphins.size(), world.ship.measured_speed, world.ship.global_position.distance_to(world.sea_life.dolphins[0].position)])
	world.sea_life.spawn_school(10)
	for i in 3:
		await create_timer(0.6).timeout
		await still("fish_%d" % i)
	print("SEALIFE fish_live=%d" % world.sea_life.fish.size())
	quit()
