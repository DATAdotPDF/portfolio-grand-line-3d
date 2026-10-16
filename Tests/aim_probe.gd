extends SceneTree

## Mira do canhão: segura a mira e confere se a linha (pontos da parábola) aparece e onde ela está.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/aim_probe.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.ship.controls_override = true
	var night := "night" in OS.get_cmdline_user_args()
	if night:
		world.select_time("night")
	# Navegando a toda (a linha some em movimento?).
	world.ship.test_controls = Vector3(1.0, 0.0, 1.0) if "moving" in OS.get_cmdline_user_args() else Vector3.ZERO
	await create_timer(5.0).timeout
	var naval: Node = world.naval
	var kraken: Node = world.get("kraken_event")
	print("AIM kraken_action=%s" % [kraken.call("action_active") if kraken else "none"])
	naval.begin_aim()
	for i in 10:
		await process_frame
	var preview: MultiMeshInstance3D = naval.preview
	var mm := preview.multimesh
	var first := mm.get_instance_transform(0).origin
	var last := mm.get_instance_transform(mm.instance_count - 1).origin
	print("AIM aiming=%s visible=%s in_tree=%s first=%s last=%s muzzle=%s aabb=%s" % [naval.aiming, preview.visible, preview.is_visible_in_tree(), first, last, naval.muzzle.global_position, mm.get_aabb()])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/Encounters/aim_probe_%s.jpg" % "_".join(OS.get_cmdline_user_args())), 0.85)
	print("PRINT aim_probe")
	quit()
