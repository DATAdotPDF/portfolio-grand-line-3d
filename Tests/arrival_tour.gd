extends SceneTree

## Vídeo do barco CHEGANDO em cada ilha/modelo (luz do jogo, gráficos no Alto, som ligado, câmera do
## jogo): o barco começa a ~60 m, vem com impulso, reduz perto e passa por dentro do vão quando o
## modelo tem canal navegável (arcos, pináculos, stonehenge: testado nos contornos de colisão do
## WorldDecor) ou passa rente ao lado. Piloto automático pelos controles de teste do barco.
## Grupos: ilhas (as 5 principais), north, east, south, west (um exemplar de cada modelo do bioma),
## cidades (as 3 cidades grandes, passando ao lado; salva um print de cada em Builds/Videos/Cidades).
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie Builds/Videos/Chegadas/x.avi
##          --script res://Tests/arrival_tour.gd -- <grupo> [noite] [curto]
## Imprime START_FRAME=<n> (começo da primeira chegada) para cortar o menu.

const SECTORS := {"north": 0, "east": 1, "south": 2, "west": 3}
const CITIES := ["runestone_citadel", "driftwood_merchant", "coral_paradise"]
const ISLAND_NAMES := ["Sobre", "Experiência", "Formação", "Projetos", "Contato"]

var world: Node3D
var decor: Node
var ship: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var group: String = args[0] if args.size() > 0 else "ilhas"
	var night := "noite" in args
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("night" if night else "day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.graphics.set_mode("alto")
	world.ghost_ship.timer = 9999.0
	# Sem kraken nem tornado puxando o barco no meio da filmagem.
	world.kraken_event.cooldown = 1e9
	for n in world.find_children("*", "", true, false):
		if n.get("capture_radius") != null and n.get("pull_radius") != null:
			n.set("pull_radius", 0.0)
			n.set("capture_radius", 0.0)
	decor = world.world_decor
	ship = world.ship
	ship.controls_override = true
	# Vento contra deixava o barco a 2 m/s perto dos alvos: no vídeo a velocidade é a do jogo sem vento.
	ship.set("ignore_wind", true)
	var targets := []
	if group == "ilhas":
		for i in world.islands.size():
			targets.append({"name": ISLAND_NAMES[i], "root": world.islands[i], "radius": 34.0, "pieces": []})
	elif group == "cidades":
		for kind in CITIES:
			for item in decor.items:
				if item.kind == kind:
					targets.append({"name": kind, "root": item.root, "radius": float(item.radius), "pieces": [], "still": true})
					break
	else:
		var sector: int = SECTORS.get(group, 0)
		var seen := {}
		for item in decor.items:
			if int(item.sector) != sector or seen.has(item.kind):
				continue
			seen[item.kind] = true
			targets.append({"name": item.kind, "root": item.root, "radius": float(item.radius), "pieces": item.pieces,
				"moving": item.kind == "turtle_island", "hover": float(item.hover)})
	# "curto": só os 3 maiores do setor (vídeo curto do bioma).
	if "curto" in args and group in SECTORS:
		targets.sort_custom(func(a, b): return float(a.radius) > float(b.radius))
		targets = targets.slice(0, 3)
	print("ARRIVAL grupo=%s alvos=%d" % [group, targets.size()])
	var first := true
	for t in targets:
		await _arrive(t, first)
		first = false
	print("ARRIVAL_DONE")
	quit()

func _hide_ui() -> void:
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = false

## Linha reta no plano do item (xz local) que cruza o modelo sem tocar nenhum contorno (com folga)
## e com rocha dos dois lados: é um canal. Devolve [direção, deslocamento] ou [] se não houver.
func _channel(pieces: Array, radius: float) -> Array:
	if pieces.size() < 2:
		return []
	var fat := []
	for hull in pieces:
		var grown := Geometry2D.offset_polygon(hull, 1.2)
		if not grown.is_empty():
			fat.append(grown[0])
	var best := []
	var best_off := INF
	for step in 72:
		var a := PI * step / 72.0
		var d := Vector2(cos(a), sin(a))
		var n := Vector2(-d.y, d.x)
		for k in 21:
			var off := float((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0)
			if absf(off) >= best_off:
				continue
			var clear := true
			var s := -(radius + 15.0)
			while s <= radius + 15.0 and clear:
				var p: Vector2 = d * s + n * off
				for poly in fat:
					if Geometry2D.is_point_in_polygon(p, poly):
						clear = false
						break
				s += 1.0
			if not clear:
				continue
			# Rocha dos dois lados da linha, perto dela (senão é só passar por fora).
			var left := false
			var right := false
			for hull in pieces:
				for q in hull:
					var side: float = (q - n * off).dot(n)
					if absf((q as Vector2).dot(d)) < radius and absf(side) < 14.0:
						if side > 0.0:
							left = true
						else:
							right = true
			if left and right:
				best = [d, off]
				best_off = absf(off)
	return best

func _arrive(t: Dictionary, first: bool) -> void:
	var target: Node3D = t.root
	var r: float = t.radius
	var xf := target.global_transform
	var up := xf.origin.normalized()
	var waypoints: Array[Vector3] = []
	var channel := _channel(t.pieces, r) if not t.get("moving", false) else []
	var start: Vector3
	if not channel.is_empty():
		var d: Vector2 = channel[0]
		var n := Vector2(-d.y, d.x)
		var off: float = channel[1]
		var local := func(p: Vector2) -> Vector3: return xf * Vector3(p.x, 0.0, p.y)
		start = local.call(-d * (r + 70.0) + n * off)
		waypoints = [local.call(-d * (r + 18.0) + n * off), local.call(d * (r + 25.0) + n * off), local.call(d * (r + 45.0) + n * off)]
		print("ARRIVAL %s pelo canal (desvio %.0f m)" % [t.name, off])
	else:
		var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		var along := side.cross(up).normalized()
		var lane := r + (14.0 if r < 30.0 else 20.0)
		start = xf.origin - along * (r + 70.0) + side * lane
		waypoints = [xf.origin - along * (r * 0.4) + side * lane, xf.origin + along * (r + 25.0) + side * lane, xf.origin + along * (r + 45.0) + side * (lane + 6.0)]
		print("ARRIVAL %s pelo lado" % t.name)
	var pos: Vector3 = world.ocean.surface_at(start.normalized() * world.planet_radius)
	var p_up := pos.normalized()
	var fwd := (waypoints[0] - pos).slide(p_up).normalized()
	ship.heading = fwd
	ship.global_transform = Transform3D(Basis(fwd.cross(p_up).normalized(), p_up, -fwd), pos)
	ship.drive_speed = 9.0
	for f in 3:
		_hide_ui()
		await process_frame
	if first:
		print("START_FRAME=%d" % Engine.get_frames_drawn())
	var index := 0
	var t0 := Time.get_ticks_msec()
	# Tempo de jogo com --fixed-fps: conta quadros, não relógio.
	var frames := 0
	while index < waypoints.size() and frames < 30 * 90:
		_hide_ui()
		var here: Vector3 = ship.global_position
		var h_up := here.normalized()
		var wp: Vector3 = waypoints[index].normalized() * world.planet_radius
		var to_wp := (wp - here).slide(h_up)
		if to_wp.length() < 7.0:
			index += 1
			if index == 1 and t.get("still", false):
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/Videos/Cidades"))
				root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/Videos/Cidades/%s.jpg" % t.name), 0.9)
				print("ARRIVAL print %s" % t.name)
			continue
		var angle: float = (ship.heading as Vector3).signed_angle_to(to_wp.normalized(), h_up)
		var near := target.global_position.distance_to(here) < r + 25.0
		ship.test_controls = Vector3(1.0, clampf(-angle * 2.2, -1.0, 1.0), 0.0 if near else 1.0)
		frames += 1
		if frames % 60 == 0 and OS.get_cmdline_user_args().has("debug"):
			print("ARRIVAL trace %s f=%d ponto=%d dist=%.1f ang=%.2f drive=%.1f measured=%.1f held=%s" % [t.name, frames, index, to_wp.length(), angle, ship.drive_speed, ship.measured_speed, ship.get("held")])
		if ship.get_slide_collision_count() > 0 and not t.has("hit"):
			var col: KinematicCollision3D = ship.get_slide_collision(0)
			var local_hit: Vector3 = target.global_transform.affine_inverse() * col.get_position()
			t.hit = true
			print("ARRIVAL colisão em %s com %s, ponto local=%s" % [t.name, (col.get_collider() as Node).get_path(), local_hit.snapped(Vector3.ONE * 0.1)])
		await process_frame
	ship.test_controls = Vector3.ZERO
	var left_to_go := -1.0
	if index < waypoints.size():
		left_to_go = (waypoints[index].normalized() * world.planet_radius).distance_to(ship.global_position)
	print("ARRIVAL %s %s em %.1f s de jogo (ponto %d/%d, faltando %.0f m, vel %.1f)" % [t.name, "ok" if index >= waypoints.size() else "PAROU",
		frames / 30.0, index, waypoints.size(), left_to_go, float(ship.drive_speed)])
