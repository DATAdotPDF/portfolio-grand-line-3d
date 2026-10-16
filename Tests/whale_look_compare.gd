extends SceneTree

## Cor da baleia colosso no jogo, mesma câmera (de lado, a ~dist m), dia: névoa como está, névoa de
## profundidade (só começa a begin m) e sem névoa. Para comparar com o modelo no Blender.
## Uso: Godot.exe --path . --resolution 1600x900 --script res://Tests/whale_look_compare.gd -- [--out=<pasta>] [--dist=420]

var world: Node3D
var out_dir := "res://Builds/WhaleLook"
var dist := 420.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--dist="):
			dist = float(arg.trim_prefix("--dist="))
	call_deferred("run")

func shot(name: String) -> void:
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var dir := out_dir if not out_dir.begins_with("res://") else ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_jpg(dir.path_join(name + ".jpg"), 0.9)
	print("WHALE print ", name)

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	var whale: Dictionary = {}
	for beast in world.sea_beasts.beasts:
		if beast.name == "timber_whale":
			whale = beast
	var r: Node3D = whale.root
	# Parada no lugar para as três fotos saírem iguais.
	world.sea_beasts.set_process(false)
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.make_current()
	var up := r.global_position.normalized()
	var side := r.global_transform.basis.x.slide(up).normalized()
	cam.look_at_from_position(r.global_position + side * dist + up * 90.0, r.global_position + up * 40.0, up)
	var env: Environment = world.get("environment")
	await create_timer(1.0).timeout
	await shot("baleia_nevoa_atual")
	# A cada quadro o mundo reescreve a densidade: segura o modo de profundidade só durante a foto.
	world.set_process(false)
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 300.0
	env.fog_depth_end = 1600.0
	env.fog_depth_curve = 1.0
	await shot("baleia_nevoa_a_partir_de_300m")
	# Teste: a densidade vale como teto no modo de profundidade?
	env.fog_density = 1.0
	await shot("baleia_profundidade_densidade_1")
	env.fog_enabled = false
	await shot("baleia_sem_nevoa")
	quit()
