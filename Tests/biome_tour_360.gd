extends SceneTree

## Vídeo de UM bioma (WorldDecor: north / east / south / west), com a luz do jogo e gráficos no
## Alto, sem HUD: abre com uma vista alta do setor e depois dá uma volta de 360° em cada marco e num
## exemplar de cada recheio (no Oeste, também a tartaruga nadando; no Sul, as lanternas da borda).
## O barco fica parado perto de cada alvo (mar detalhado e animações do Blender ativos ali).
## Imprime START_FRAME=<n> para cortar o começo (menu) do vídeo.
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie Builds/Videos/Biomas/sul.avi
##          --script res://Tests/biome_tour_360.gd -- south [noite]

const ORBIT_SECONDS := 6.0
const SECTORS := {"north": 0, "east": 1, "south": 2, "west": 3}

var world: Node3D
var decor: Node3D
var camera: Camera3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var sector: int = SECTORS.get(args[0] if args.size() > 0 else "south", 2)
	var night := args.size() > 1 and args[1] == "noite"
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
	world.ghost_ship.timer = 9999.0
	decor = world.world_decor
	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = 50.0
	root.add_child(camera)
	var targets := _targets(sector)
	print("BIOME %s alvos=%d %s" % [decor.sector_name(sector), targets.size(), targets.map(func(t): return t.kind)])
	var first := true
	for item in targets:
		await _orbit(item, first)
		first = false
	print("BIOME_DONE")
	quit()

## Marcos do setor e um exemplar de cada recheio; a tartaruga no Oeste.
func _targets(sector: int) -> Array:
	var list := []
	var seen := {}
	for item in decor.items:
		if int(item.sector) != sector or seen.has(item.kind):
			continue
		seen[item.kind] = true
		list.append(item)
	return list

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

func _size(root_node: Node3D) -> Array:
	var box := AABB()
	var first := true
	for mesh in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null or mi.name.begins_with("Lava") or mi.name == "BoilingWater" or mi.mesh is QuadMesh:
			continue
		var b: AABB = root_node.global_transform.affine_inverse() * mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return [maxf(box.size.x, box.size.z), box.end.y, box.get_center().y]

func _orbit(item: Dictionary, first: bool) -> void:
	var target: Node3D = item.root
	var up := target.global_position.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	_park(target.global_position + side * 60.0)
	var dims := _size(target)
	var width: float = dims[0]
	var tall: float = dims[1]
	var radius := maxf(maxf(width, tall) * 1.25, 7.0)
	var height := maxf(tall * 0.45 + width * 0.15, 3.0)
	var look := maxf(float(dims[2]), tall * 0.35)
	var is_turtle: bool = item.kind == "turtle_island"
	var orbit := func(k: float) -> void:
		var center := target.global_position
		var u := center.normalized()
		var dir := side.rotated(u, PI * 0.75 + TAU * k)
		if is_turtle:
			_park(center + target.global_basis.x * 70.0)
		camera.make_current()
		camera.look_at_from_position(center + dir * radius + u * height, center + u * look, u)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 900:
		_hide_ui()
		orbit.call(0.0)
		await process_frame
	if first:
		print("START_FRAME=%d" % Engine.get_frames_drawn())
	var frames := int(ORBIT_SECONDS * 30.0)
	for i in frames:
		_hide_ui()
		if is_turtle:
			# Só no vídeo: a tartaruga anda mais rápido para dar para ver que ela nada.
			decor.turtle.angle = float(decor.turtle.angle) + 0.0012
		orbit.call(float(i) / frames)
		await process_frame
	print("ORBIT %s" % item.kind)
