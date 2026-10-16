extends SceneTree

## Antes × depois das ilhas no jogo (luz do jogo, gráficos no Alto): as mesmas câmeras para a versão
## que o MainWorld.tscn estiver usando. Rodar uma vez com as ilhas antigas e outra com as novas.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/island_before_after.gd -- <antes|depois>

var world: Node3D
var camera: Camera3D
var tag := "depois"
var out_dir := "res://Builds/IslandBeforeAfter"

# Por ilha: [raio, altura e ponto olhado] da foto rente à água e da foto de perto.
const SHOTS := [
	{"agua": [34.0, 1.5, 3.0], "perto": [17.0, 9.0, 4.0]},
	{"agua": [44.0, 1.5, 5.0], "perto": [24.0, 14.0, 8.0]},
	{"agua": [36.0, 1.5, 4.0], "perto": [18.0, 10.0, 6.0]},
	{"agua": [36.0, 1.5, 3.0], "perto": [16.0, 8.0, 2.0]},
	{"agua": [50.0, 1.5, 8.0], "perto": [20.0, 6.0, 4.0]},
]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		tag = args[0]
	call_deferred("run")

func shoot(name: String, index: int, radius: float, height: float, look: float, bearing := 0.0) -> void:
	var mount: Node3D = world.islands[index]
	var up := mount.global_position.normalized()
	var side := mount.global_basis.z.slide(up).normalized().rotated(up, deg_to_rad(bearing))
	var at := mount.global_position + up * look
	var from := mount.global_position + side * radius + up * height
	for i in 45:
		for layer in world.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		camera.make_current()
		camera.look_at_from_position(from, at, up)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("%s/%s_%s.jpg" % [out_dir, name, tag]), 0.9)
	print("SHOT ", name, " ", tag)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.graphics.set_mode("alto")
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	world.sea_life.sea_shadows.timer = 9999.0
	world.sea_life.dolphin_timer = 9999.0
	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = 50.0
	root.add_child(camera)
	var names := ["sobre", "experiencia", "formacao", "projetos", "contato"]
	for i in names.size():
		var shot: Dictionary = SHOTS[i]
		await shoot(names[i] + "_agua", i, shot.agua[0], shot.agua[1], shot.agua[2])
		await shoot(names[i] + "_perto", i, shot.perto[0], shot.perto[1], shot.perto[2], 35.0)
	world.select_time("night")
	await create_timer(1.0).timeout
	await shoot("formacao_noite", 2, 22.0, 6.0, 5.0)
	quit()
