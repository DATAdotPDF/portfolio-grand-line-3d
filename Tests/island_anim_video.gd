extends SceneTree

## Vídeo curto das animações de uma ilha (feitas no Blender, Tools/animate_islands_blender.py), câmera
## parada de perto, luz do jogo no Alto, sem HUD. Cenários: ilha0..ilha4.
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie Builds/Videos/X.avi
##      --script res://Tests/island_anim_video.gd -- ilhaN

var world: Node3D
var camera: Camera3D
var scenario := "ilha0"
var view_from := Vector3.ZERO
var view_at := Vector3.ZERO
var night := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		scenario = args[0]
	night = "night" in args
	call_deferred("run")

func hold(seconds: float) -> void:
	for i in int(seconds * 30.0):
		for layer in world.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		camera.make_current()
		camera.look_at_from_position(view_from, view_at, view_at.normalized())
		await process_frame

## Câmera olhando `at`, vinda de fora da ilha `index` (girada `turn` graus), a `distance` e `height` m.
func frame(index: int, at: Vector3, distance: float, height: float, turn := 0.0) -> void:
	var mount: Node3D = world.islands[index]
	var up := at.normalized()
	var out := (at - mount.global_position).slide(up)
	if out.length() < 0.5:
		out = mount.global_basis.z.slide(up)
	out = out.normalized().rotated(up, deg_to_rad(turn))
	view_at = at
	view_from = at + out * distance + up * height

## Câmera olhando `at` pela frente da ilha (+Z da âncora, girado `turn` graus).
func frame_front(index: int, at: Vector3, distance: float, height: float, turn := 0.0) -> void:
	var mount: Node3D = world.islands[index]
	var up := at.normalized()
	var out := mount.global_basis.z.slide(up).normalized().rotated(up, deg_to_rad(turn))
	view_at = at
	view_from = at + out * distance + up * height

func park_ship(index: int, distance: float) -> void:
	var mount: Node3D = world.islands[index]
	var up := mount.global_position.normalized()
	var side := mount.global_basis.z.slide(up).normalized().rotated(up, PI)
	var pos: Vector3 = world.ocean.surface_at(mount.global_position + side * distance)
	var forward := side.cross(up).normalized()
	var ship: Node3D = world.ship
	ship.heading = forward
	ship.global_transform = Transform3D(Basis(forward.cross(pos.normalized()).normalized(), pos.normalized(), -forward), pos)
	ship.drive_speed = 0.0

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("night" if night else "day")
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
	var index := int(scenario.trim_prefix("ilha"))
	var fx: Node = world.islands[index].get_node("IslandEffects")
	var mount: Node3D = world.islands[index]
	var up := mount.global_position.normalized()
	park_ship(index, 150.0)
	match index:
		0:
			frame_front(0, fx.chimney.global_position + up * 1.5, 16.0, 5.0, 35.0)
		1:
			frame(1, mount.global_position + up * 8.0, 30.0, 10.0, 20.0)
		2:
			frame_front(2, fx.cube.global_position - up * 2.0, 24.0, 6.0, 0.0)
		3:
			frame(3, fx.part_mesh("ChestLid").global_position, 6.5, 3.0, 0.0)
		4:
			# Topo do farol inteiro: sala da lanterna (parada, a luz gira lá dentro) + Den Den Mushi.
			var top: Vector3 = (fx.snail.global_position + fx.part_mesh("LanternRoom").global_position) * 0.5
			frame(4, top, 18.0, 1.5, 200.0)
	await hold(0.5)
	print("ANIM_START %.3f" % (Engine.get_process_frames() / 30.0))
	match index:
		1:
			for k in 6:
				fx._fire_cannon(fx.decorative_cannons[(k * 3) % fx.decorative_cannons.size()])
				await hold(1.4)
		3:
			# O baú abre com a câmera a menos de 45 m da ilha (ou o barco a 60 m): longe, perto, longe.
			var lid: Vector3 = fx.part_mesh("ChestLid").global_position
			frame(3, lid, 75.0, 25.0, 0.0)
			await hold(2.0)
			frame(3, lid, 6.5, 3.0, 0.0)
			await hold(4.0)
			frame(3, lid, 75.0, 25.0, 0.0)
			await hold(2.5)
		4:
			await hold(2.0)
			park_ship(4, 30.0)
			await hold(8.0)
		_:
			await hold(10.0)
	quit()
