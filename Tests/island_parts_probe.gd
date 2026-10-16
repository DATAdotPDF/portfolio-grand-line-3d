extends SceneTree

## Ilhas segmentadas (Assets/Optimized/Islands/*_parts.glb + IslandEffects): confere se cada peça
## animada foi achada e tira prints de perto (chaminé, canhões, cubo/palmeiras, baús fechados e
## abertos, farol/Den Den Mushi). Com --write-movie vira vídeo das animações.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/island_parts_probe.gd [-- night]

var world: Node3D
var camera: Camera3D
var out_dir := "res://Builds/IslandPrints"
var view_from := Vector3.ZERO
var view_at := Vector3.ZERO

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("%s/%s.jpg" % [out_dir, name]), 0.85)
	print("PRINT ", name)

func hold(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var frames := int(seconds * 30.0)
	for i in frames:
		for layer in world.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		camera.make_current()
		camera.look_at_from_position(view_from, view_at, view_at.normalized())
		await process_frame
	while Time.get_ticks_msec() < end and not Engine.get_write_movie_path():
		await process_frame

## Câmera olhando a ilha de um lado (bearing em graus), a `distance` m e `height` m acima.
func frame_island(index: int, bearing: float, distance: float, height: float, look_height := 4.0) -> void:
	var mount: Node3D = world.islands[index]
	var up := mount.global_position.normalized()
	var side := mount.global_basis.z.slide(up).normalized().rotated(up, deg_to_rad(bearing))
	view_at = mount.global_position + up * look_height
	view_from = mount.global_position + side * distance + up * height

## Câmera num ponto específico (em volta dele, por fora da ilha).
func frame_point(index: int, at: Vector3, distance: float, height: float, turn := 0.0) -> void:
	var mount: Node3D = world.islands[index]
	var up := at.normalized()
	var out := (at - mount.global_position).slide(up).normalized().rotated(up, deg_to_rad(turn))
	view_at = at
	view_from = at + out * distance + up * height

func park_ship(index: int, distance: float) -> void:
	var mount: Node3D = world.islands[index]
	var up := mount.global_position.normalized()
	var side := mount.global_basis.z.slide(up).normalized()
	var pos: Vector3 = world.ocean.surface_at(mount.global_position + side * distance)
	var forward := side.cross(up).normalized()
	var ship: Node3D = world.ship
	ship.heading = forward
	ship.global_transform = Transform3D(Basis(forward.cross(pos.normalized()).normalized(), pos.normalized(), -forward), pos)
	ship.drive_speed = 0.0

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var night := "night" in OS.get_cmdline_user_args()
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("night" if night else "day")
	await create_timer(2.0).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = 50.0
	root.add_child(camera)
	var suffix := "_night" if night else ""
	for i in world.islands.size():
		var fx: Node = world.islands[i].get_node("IslandEffects")
		print("ISLAND_PARTS %d chimney=%s cannons=%d chests=%d cube=%s snail=%s players=%s" % [i, fx.chimney != null, fx.decorative_cannons.size(), fx.chests.size(), fx.cube != null, fx.snail != null, fx.anim_players.keys()])
	# Barco longe de todas (baús fechados).
	park_ship(3, 120.0)
	# Sobre: chaminé (3 puffs).
	frame_island(0, 30.0, 24.0, 12.0, 5.0)
	await hold(1.0)
	await still("sobre" + suffix)
	await hold(5.0)
	# Experiência: força uns tiros.
	frame_island(1, 20.0, 34.0, 18.0, 4.0)
	var fort: Node = world.islands[1].get_node("IslandEffects")
	await hold(0.5)
	await still("experiencia" + suffix)
	for k in 3:
		if fort.decorative_cannons.is_empty(): break
		fort._fire_cannon(fort.decorative_cannons[k * 3 % fort.decorative_cannons.size()])
		await hold(0.12)
		if k == 0: await still("experiencia_tiro" + suffix)
		await hold(1.2)
	# Formação: cubo e palmeiras.
	frame_island(2, 0.0, 30.0, 14.0, 5.0)
	await hold(1.0)
	await still("formacao" + suffix)
	await hold(4.0)
	# Projetos: baús fechados, barco chega, abrem com ouro.
	var middle: Vector3 = (world.islands[3].get_node("IslandEffects").part_mesh("ChestLid") as Node3D).global_position
	frame_point(3, middle, 6.0, 3.0, 0.0)
	await hold(1.0)
	await still("projetos_fechados" + suffix)
	park_ship(3, 28.0)
	await hold(0.35)
	await still("projetos_abrindo" + suffix)
	await hold(2.0)
	await still("projetos_abertos" + suffix)
	# Contato: farol e Den Den Mushi tocando (barco perto).
	park_ship(4, 30.0)
	var lighthouse: Node = world.islands[4].get_node("IslandEffects")
	frame_point(4, lighthouse.snail.global_position, 15.0, 2.0, 200.0)
	await hold(1.0)
	await still("contato" + suffix)
	await hold(4.0)
	quit()
