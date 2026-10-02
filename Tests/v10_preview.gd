extends SceneTree

## Capturas de verificação visual da Fase 3 (renderer Compatibility).
## Uso: Godot.exe --path . --rendering-method gl_compatibility --script res://Tests/v10_preview.gd [-- shots=boat,islands,overview]

const OUT := "res://Documentation/Previews/v10_%s.png"
var world: Node3D
var only := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			only = arg.trim_prefix("shots=")
	call_deferred("run")

func wants(name: String) -> bool:
	return only == "" or only.split(",").has(name)

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT % name)
	var error := root.get_texture().get_image().save_png(path)
	print("V10_PREVIEW ", name, " error=", error, " fps=", Engine.get_frames_per_second())

func run() -> void:
	root.size = Vector2i(1280, 720)
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = wants("intro") and only != ""
	root.add_child(world)
	world.clock.set_time(0.42, true)
	await wait(1.5)
	if world.show_intro_on_start:
		await wait(2.5)
		await shot("intro")
		for child in world.hud.intro_column.get_children():
			print("INTRO_CHILD ", child.get_class(), " ", child.get_combined_minimum_size(), " pos=", child.position)
		print("INTRO_PANEL ", world.hud.intro_panel.position, " ", world.hud.intro_panel.size)
		world.hud.island_pressed.emit(0)
		await wait(3.0)
		await shot("tour_sobre")
		quit()
		return
	if wants("boat"):
		await shot("boat_rest")
		world.ship.controls_override = true
		world.ship.test_controls = Vector3(1, 0.25, 1)
		await wait(7.0)
		await shot("boat_sailing")
		world.ship.test_controls = Vector3(1, 0, 1)
		world.camera.yaw = PI * 0.5
		world.camera.pitch = 1.0
		await wait(2.0)
		await shot("boat_side")
		world.camera.yaw = 0.0
		world.camera.pitch = 0.0
		world.ship.test_controls = Vector3.ZERO
	if wants("route"):
		world.camera.yaw = -world.log_pose.target_angle_rad
		world.camera.follow_height = 14.0
		world.camera.follow_distance = 22.0
		await wait(2.0)
		await shot("route")
		world.camera.yaw = 0.0
		world.camera.follow_height = 5.0
		world.camera.follow_distance = 12.0
	if wants("close"):
		world.ship.controls_override = true
		world.ship.test_controls = Vector3(1, 0.1, 1)
		world.camera.follow_distance = 7.0
		world.camera.follow_height = 1.6
		world.camera.yaw = 0.75
		await wait(6.0)
		await shot("close_bow")
		world.camera.yaw = 2.6
		await wait(1.5)
		await shot("close_stern")
		world.clock.set_time(0.02, true)
		world.camera.yaw = 0.0
		world.camera.follow_distance = 12.0
		world.camera.follow_height = 5.0
		await wait(2.5)
		await shot("night")
		world.clock.set_time(0.42, true)
		world.ship.test_controls = Vector3.ZERO
	if wants("ripple"):
		await wait(4.0)
		var ahead: Vector3 = world.ship.global_position - world.ship.global_basis.z * 14.0
		var side: Vector3 = world.ship.global_basis.x
		for i in range(8):
			world.ocean.touch(ahead + side * (float(i) - 3.5) * 1.4, 0.35, 3.0)
			await wait(0.08)
		world.ocean.touch(ahead + side * 6.0, 0.55, 3.0)
		await wait(1.1)
		await shot("ripple")
	if wants("hud"):
		world.camera.focus_island(world.islands[3])
		await wait(2.8)
		await shot("hud_island_panel")
		world.clock.set_time(0.02, true)
		await wait(1.0)
		await shot("hud_island_panel_night")
		world.clock.set_time(0.42, true)
		world._return_to_navigation()
		await wait(2.5)
		world._start_time_attack()
		await wait(3.5)
		await shot("hud_race")
		world._return_to_navigation()
	if wants("islands"):
		for i in range(world.islands.size()):
			world.camera.focus_island(world.islands[i])
			await wait(2.8)
			await shot("island_%d" % (i + 1))
	if wants("mobile"):
		world.camera.return_to_boat()
		root.size = Vector2i(390, 844)
		world.get_node("TouchControls").enable()
		world.hud.touch = true
		world.hud.hide_island()
		world.hud.show_island(0)
		await wait(2.8)
		await shot("mobile")
		root.size = Vector2i(1280, 720)
	if wants("overview"):
		world.camera.show_overview()
		await wait(2.8)
		await shot("overview")
	quit()
