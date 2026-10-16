extends SceneTree

## Vídeo navegando pela BORDA de um bioma (WorldDecor: marcos de borda — caixas no Norte, sinos no
## Leste, lanternas no Sul, corais no Oeste): o barco segue a fileira de marcos por ~MARKERS deles,
## passando 15 m para dentro do bioma. Câmera e som do jogo, gráficos no Alto, sem HUD.
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie Builds/Videos/Bordas/x.avi
##          --script res://Tests/border_tour.gd -- <north|east|south|west> [noite]
## Imprime START_FRAME=<n> para cortar o começo.

const SECTORS := {"north": 0, "east": 1, "south": 2, "west": 3}
const MARKERS := 8
## Centro de cada bioma (lat, lon): o lado "de dentro" da fileira.
const INSIDE := {0: Vector2(90, 0), 1: Vector2(0, 90), 2: Vector2(-90, 0), 3: Vector2(0, 270)}

var world: Node3D
var decor: Node
var ship: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var sector: int = SECTORS.get(args[0] if args.size() > 0 else "east", 1)
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("night" if "noite" in args else "day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.graphics.set_mode("alto")
	world.ghost_ship.timer = 9999.0
	world.kraken_event.cooldown = 1e9
	for n in world.find_children("*", "", true, false):
		if n.get("capture_radius") != null and n.get("pull_radius") != null:
			n.set("pull_radius", 0.0)
			n.set("capture_radius", 0.0)
	decor = world.world_decor
	ship = world.ship
	ship.controls_override = true
	ship.set("ignore_wind", true)
	var markers := []
	for item in decor.items:
		if item.get("marker", false) and int(item.sector) == sector:
			markers.append(item)
	# A fileira já foi criada na ordem do caminho da borda: pega um trecho seguido.
	var stretch := markers.slice(0, MARKERS)
	var inside: Vector3 = decor._lat_lon(INSIDE[sector].x, INSIDE[sector].y)
	var waypoints: Array[Vector3] = []
	for item in stretch:
		var p: Vector3 = (item.root as Node3D).global_position
		var up := p.normalized()
		var toward: Vector3 = (inside * world.planet_radius - p).slide(up).normalized()
		waypoints.append(p + toward * 15.0)
	print("BORDER %s marcos=%d trecho=%d" % [decor.sector_name(sector), markers.size(), stretch.size()])
	# Começa antes do primeiro marco, apontado para o segundo.
	var first := waypoints[0]
	var dir := (first - waypoints[1]).slide(first.normalized()).normalized()
	var pos: Vector3 = world.ocean.surface_at((first + dir * 60.0).normalized() * world.planet_radius)
	var p_up := pos.normalized()
	var fwd := (first - pos).slide(p_up).normalized()
	ship.heading = fwd
	ship.global_transform = Transform3D(Basis(fwd.cross(p_up).normalized(), p_up, -fwd), pos)
	ship.drive_speed = 10.0
	for f in 3:
		_hide_ui()
		await process_frame
	print("START_FRAME=%d" % Engine.get_frames_drawn())
	var index := 0
	var frames := 0
	while index < waypoints.size() and frames < 30 * 240:
		_hide_ui()
		var here: Vector3 = ship.global_position
		var h_up := here.normalized()
		var wp: Vector3 = waypoints[index].normalized() * world.planet_radius
		var to_wp := (wp - here).slide(h_up)
		if to_wp.length() < 10.0:
			index += 1
			continue
		var angle: float = (ship.heading as Vector3).signed_angle_to(to_wp.normalized(), h_up)
		ship.test_controls = Vector3(1.0, clampf(-angle * 2.2, -1.0, 1.0), 1.0)
		frames += 1
		await process_frame
	print("BORDER fim: %d/%d marcos em %.0f s de jogo" % [index, waypoints.size(), frames / 30.0])
	quit()

func _hide_ui() -> void:
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
