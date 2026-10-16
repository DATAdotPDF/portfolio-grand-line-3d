extends SceneTree

## Carregamento por proximidade: roda o pacote exportado (sem os modelos dos setores), põe a câmera
## perto de um marco do Norte e tira um print antes e depois de os pacotes chegarem.
## Uso (na pasta do build): Godot.exe --main-pack index.pck --resolution 1280x720
##   --script <projeto>/Tests/packs_probe.gd -- --packs=<pasta>/packs --out=<pasta dos prints>

var world: Node3D
var out_dir := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	call_deferred("run")

func shot(name: String) -> void:
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out_dir.path_join(name + ".jpg"), 0.88)
	print("PROBE print ", name)

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await process_frame
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	var decor: Node = world.world_decor
	var target: Node3D = null
	for item in decor.items:
		if item.kind == "runestone_citadel":
			target = item.root
	var cam := Camera3D.new()
	cam.far = 4000.0
	root.add_child(cam)
	var up := target.global_position.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	cam.look_at_from_position(target.global_position + side * 230.0 + up * 45.0, target.global_position + up * 20.0, up)
	cam.make_current()
	print("PROBE esperando=%d" % decor.pending.size())
	await shot("pacotes_antes")
	while not decor.pending.is_empty():
		await process_frame
	await create_timer(1.0).timeout
	print("PROBE esperando=%d" % decor.pending.size())
	await shot("pacotes_depois")
	quit()
