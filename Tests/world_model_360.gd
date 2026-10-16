extends SceneTree

## Vídeo 360 de UM modelo do mapa (WorldDecor), com a luz do jogo e gráficos no Alto, sem HUD.
## O barco fica parado perto (o mar detalhado e as animações do Blender ficam ativos ali).
## - <tipo>: primeiro exemplar daquele modelo (spectral_lantern = uma lanterna da borda do Mar Sombrio);
## - turtle_island: a câmera acompanha a ilha-tartaruga nadando (velocidade acelerada no vídeo);
## Imprime START_FRAME=<n> (quadro em que a volta começa) para cortar o começo do vídeo.
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie Builds/Videos/Modelos/x.avi
##          --script res://Tests/world_model_360.gd -- <tipo> [dia|noite]

const SECONDS := 9.0

var world: Node3D
var decor: Node3D
var camera: Camera3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var kind: String = args[0] if args.size() > 0 else "bell_buoy"
	var time: String = "night" if (args.size() > 1 and args[1] == "noite") else "day"
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time(time)
	await create_timer(1.5).timeout
	world._start_sailing()
	world.graphics.set_mode("alto")
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	world.sea_life.sea_shadows.timer = 9999.0
	world.sea_life.dolphin_timer = 9999.0
	world.ghost_ship.timer = 9999.0
	decor = world.world_decor
	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = 50.0
	root.add_child(camera)
	if kind == "turtle_island":
		await _turtle()
	else:
		await _model(kind)
	quit()

func _hide_ui() -> void:
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = false

func _park(at: Vector3) -> void:
	var pos: Vector3 = world.ocean.surface_at(at.normalized() * world.planet_radius)
	var up := pos.normalized()
	var forward := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	world.ship.heading = forward
	world.ship.global_transform = Transform3D(Basis(forward.cross(up).normalized(), up, -forward), pos)
	world.ship.drive_speed = 0.0

## Tamanho do modelo (largura, altura) e centro, no espaço do item.
func _size(root_node: Node3D) -> Array:
	var box := AABB()
	var first := true
	for mesh in root_node.find_children("*", "MeshInstance3D", true, false):
		if not (mesh as MeshInstance3D).mesh or mesh.name.begins_with("Lava") or mesh.name == "BoilingWater":
			continue
		var b: AABB = root_node.global_transform.affine_inverse() * (mesh as Node3D).global_transform * (mesh as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return [maxf(box.size.x, box.size.z), box.end.y, box.get_center().y]

func _settle(seconds: float, eye_fn: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		_hide_ui()
		eye_fn.call(0.0)
		await process_frame

func _model(kind: String) -> void:
	var item: Dictionary = {}
	for it in decor.items:
		if it.kind == kind and (kind != "spectral_lantern" or float(it.hover) > 0.0):
			item = it
			break
	if item.is_empty():
		push_error("sem item %s" % kind)
		return
	var target: Node3D = item.root
	var up := target.global_position.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	_park(target.global_position + side * 60.0)
	var dims := _size(target)
	var width: float = dims[0]
	var tall: float = dims[1]
	var radius := maxf(maxf(width, tall) * 1.25, 6.5)
	var height := maxf(tall * 0.45 + width * 0.15, 3.0)
	var look := maxf(float(dims[2]), tall * 0.4)
	var orbit := func(k: float) -> void:
		var center := target.global_position
		var u := center.normalized()
		var dir := side.rotated(u, PI * 0.75 + TAU * k)
		camera.make_current()
		camera.look_at_from_position(center + dir * radius + u * height, center + u * look, u)
	await _settle(1.0, orbit)
	print("START_FRAME=%d" % Engine.get_frames_drawn())
	var frames := int(SECONDS * 30.0)
	for i in frames:
		_hide_ui()
		orbit.call(float(i) / frames)
		await process_frame
	print("ORBIT %s" % kind)

## Tartaruga: nada mais rápido só no vídeo; a câmera dá a volta enquanto acompanha.
func _turtle() -> void:
	var item: Dictionary = decor.turtle.item
	var target: Node3D = item.root
	var dims := _size(target)
	var width: float = dims[0]
	var tall: float = dims[1]
	var speed := 0.5
	var follow := func(k: float) -> void:
		var center := target.global_position
		var u := center.normalized()
		var ahead := -target.global_basis.z
		var dir := ahead.rotated(u, PI * 0.35 + TAU * k)
		camera.make_current()
		camera.look_at_from_position(center + dir * width * 1.5 + u * (tall * 0.55), center + u * tall * 0.3, u)
		_park(center + target.global_basis.x * 70.0)
	await _settle(1.0, follow)
	print("START_FRAME=%d" % Engine.get_frames_drawn())
	var frames := int(SECONDS * 1.5 * 30.0)
	for i in frames:
		_hide_ui()
		decor.turtle.angle = float(decor.turtle.angle) + speed * 0.0024
		follow.call(float(i) / frames)
		await process_frame
	print("ORBIT turtle angle=%.2f" % decor.turtle.angle)
