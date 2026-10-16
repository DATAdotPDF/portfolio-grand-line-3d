extends SceneTree

## Antes/depois do ajuste de metal dos modelos do Meshy (main_world._tame_meshy_metal): tartaruga e
## baleia colosso de dia, mesma câmera; "antes" volta metallic = 1 só para o print.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/metal_fix_compare.gd

var world: Node3D
var cam: Camera3D

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/Encounters/%s.jpg" % name), 0.88)
	print("PRINT ", name)

func materials_of(node: Node3D) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.get_active_material(s) as StandardMaterial3D
			if m and m.metallic_texture and not out.has(m):
				out.append(m)
	return out

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.make_current()
	for kind in ["turtle_island", "timber_whale"]:
		var target: Node3D = null
		for item in world.world_decor.items:
			if str(item.kind).contains(kind.split("_")[1]) or str(item.kind) == kind:
				target = item.root
				break
		if target == null:
			print("METAL no ", kind)
			continue
		var up := target.global_position.normalized()
		var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		cam.look_at_from_position(target.global_position + side * 170.0 + up * 25.0, target.global_position + up * 15.0, up)
		await create_timer(1.0).timeout
		await shot("metal_%s_depois" % kind)
		var mats := materials_of(target)
		for m in mats:
			m.metallic = 1.0
			m.metallic_specular = 0.5
		await shot("metal_%s_antes" % kind)
		for m in mats:
			m.metallic = 0.08
			m.metallic_specular = 0.3
		# Suspeitos do "lavado" na tela toda: flare do sol (véu na tela) e glow/ajustes do ambiente.
		var env: Environment = world.get("environment")
		print("ENV glow=%s glow_intensity=%.2f glow_bloom=%.2f adjust=%s bright=%.2f contrast=%.2f sat=%.2f tonemap=%d white=%.2f exposure=%.2f fog=%s" % [env.glow_enabled, env.glow_intensity, env.glow_bloom, env.adjustment_enabled, env.adjustment_brightness, env.adjustment_contrast, env.adjustment_saturation, env.tonemap_mode, env.tonemap_white, env.tonemap_exposure, env.fog_enabled])
		var flares: Array = []
		for node in world.find_children("*", "", true, false):
			if node.get_script() and str(node.get_script().resource_path).contains("SunFlare"):
				flares.append(node)
		for f in flares:
			(f as Node).set_process(false)
			for c in (f as Node).find_children("*", "CanvasItem", true, false):
				(c as CanvasItem).visible = false
		await shot("metal_%s_sem_flare" % kind)
		var glow := env.glow_enabled
		env.glow_enabled = false
		await shot("metal_%s_sem_flare_sem_glow" % kind)
		env.glow_enabled = glow
		print("FOG density=%.4f aerial=%.2f sky_affect=%.2f color=%s height=%.2f" % [env.fog_density, env.fog_aerial_perspective, env.fog_sky_affect, env.fog_light_color, env.fog_height_density])
		var fog := env.fog_enabled
		env.fog_enabled = false
		world.set_process(false)
		await shot("metal_%s_sem_nevoa" % kind)
		env.fog_enabled = fog
		world.set_process(true)
	quit()
