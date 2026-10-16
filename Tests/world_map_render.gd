extends SceneTree

## Mapa do mundo para aprovar o layout (Tests/world_map_canvas.gd desenha): lê o mundo de verdade
## (ilhas, rotas, WorldDecor) e calcula de onde o barco vê algo no horizonte.
## Uso: Godot.exe --path . --resolution 2400x1420 --script res://Tests/world_map_render.gd
## Saída: Builds/WorldMap/mapa_mundo.png

const EYE := 6.0          # altura do olho (câmera atrás do barco), m
const ISLAND_NAMES := ["Sobre", "Experiência", "Formação", "Projetos", "Contato"]
## Fator de escala testado para os marcos (proposta "ilhas maiores").
const BIGGER := 1.6
## Altura acima d'água (m, por baixo) dos bichos grandes: um ponto conta como "vê o bicho" só se ele
## aparece de QUALQUER ponto do circuito (o bicho pode estar do outro lado da volta).
const BEAST_HEIGHT := {"turtle": 58.0, "timber_whale": 40.0, "abyssal_behemoth": 60.0, "abyssal_obsidian": 106.0}

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func _ll(p: Vector3) -> Vector2:
	var n := p.normalized()
	return Vector2(rad_to_deg(asin(clampf(n.y, -1.0, 1.0))), fposmod(rad_to_deg(atan2(n.z, n.x)), 360.0))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/WorldMap"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	await process_frame
	await process_frame
	var decor: Node = world.world_decor
	var R: float = world.planet_radius
	var data := {"eye": EYE, "m_per_deg": R * PI / 180.0, "island_clear": decor.ISLAND_CLEARANCE, "route_clear": decor.ROUTE_CLEAR}
	# Ilhas: altura e raio a partir das malhas.
	var islands := []
	var dirs: Array[Vector3] = []
	for i in world.islands.size():
		var island: Node3D = world.islands[i]
		var c := island.global_position.normalized()
		dirs.append(c)
		var top := 0.0
		var rad := 10.0
		for mesh in island.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh as MeshInstance3D
			if mi.mesh == null:
				continue
			if not mi.is_visible_in_tree():
				continue
			var box: AABB = mi.global_transform * mi.mesh.get_aabb()
			var mesh_rad := 0.0
			for k in 8:
				mesh_rad = maxf(mesh_rad, c.angle_to(box.get_endpoint(k)) * R)
			# Fachos de luz e afins (malhas enormes) não contam como ilha.
			if mesh_rad > 60.0:
				continue
			for k in 8:
				var corner := box.get_endpoint(k)
				top = maxf(top, corner.length() - R)
			rad = maxf(rad, mesh_rad)
		var ll := _ll(c)
		islands.append({"name": ISLAND_NAMES[i] if i < ISLAND_NAMES.size() else str(i), "lat": ll.x, "lon": ll.y, "height": minf(top, 120.0), "radius": minf(rad, 120.0), "dir": c})
	data.islands = islands
	# Rotas.
	var routes := []
	for i in dirs.size() - 1:
		var pts := []
		for k in 121:
			pts.append(_ll(dirs[i].slerp(dirs[i + 1], k / 120.0)))
		routes.append(pts)
	data.routes = routes
	# Itens.
	var items := []
	for it in decor.items:
		var ll := _ll(it.dir)
		items.append({"kind": it.kind, "lat": ll.x, "lon": ll.y, "sector": it.sector, "radius": it.radius, "marker": bool(it.get("marker", false)),
			"height": float(it.height) + float(it.hover), "dir": (it.dir as Vector3).normalized()})
	data.items = items
	var beasts := {}
	for name in decor.patrol_paths:
		if name == "shark_fin":
			continue
		var pts := []
		for q in decor.patrol_paths[name]:
			pts.append(_ll(q))
		beasts[name] = pts
	data.beasts = beasts
	data.sector_names = [decor.sector_name(0), decor.sector_name(1), decor.sector_name(2), decor.sector_name(3)]
	var shark := []
	for p in decor.patrol_paths.get("shark_fin", []):
		shark.append(_ll(p))
	data.shark_path = shark
	# Cobertura do horizonte.
	var objects := []
	for isl in islands:
		objects.append([isl.dir, float(isl.height), false])
	for it in items:
		objects.append([it.dir, float(it.height), it.kind not in ["spectral_lantern", "cargo_crates", "bell_buoy", "palm_atoll", "coral_reef", "broken_megalithic_quay"]])
	var cells := []
	var gaps := []
	var blind := []
	var totals := {}
	var step := 1.5
	var lat := -90.0 + step * 0.5
	while lat < 90.0:
		var ring := maxi(1, int(round(360.0 * cos(deg_to_rad(lat)) / step)))
		for j in ring:
			var lon := (j + 0.5) * 360.0 / ring
			var p: Vector3 = decor._lat_lon(lat, lon)
			var on_island := false
			for isl in islands:
				if p.angle_to(isl.dir) * R < float(isl.radius):
					on_island = true
			if on_island:
				continue
			var seen := false
			var seen_big := false
			var beast_seen := false
			for name in BEAST_HEIGHT:
				var far := 0.0
				for q in decor.patrol_paths.get(name, []):
					far = maxf(far, p.angle_to(q) * R)
				if far > 0.0 and far < _reach(R, BEAST_HEIGHT[name], true):
					beast_seen = true
			var nearest := INF
			for o in objects:
				nearest = minf(nearest, p.angle_to(o[0]) * R)
			gaps.append(nearest)
			for o in objects:
				var d: float = p.angle_to(o[0]) * R
				var h: float = o[1]
				if d < _reach(R, h, not bool(o[2]) or true):
					seen = true
				if d < _reach(R, h * (BIGGER if o[2] else 1.0), true):
					seen_big = true
				if seen and seen_big:
					break
			seen = seen or beast_seen
			seen_big = seen_big or beast_seen
			if not seen:
				blind.append(Vector2(lat, lon))
				var best := INF
				var best_h := 0.0
				for o in objects:
					var d: float = p.angle_to(o[0]) * R
					if d - _reach(R, o[1], true) < best:
						best = d - _reach(R, o[1], true)
						best_h = o[1]
				print("CEGO_DEBUG falta %.0f m (altura %.0f) rota=%.0f bicho=%.0f" % [best, best_h, decor._route_distance(p), decor._beast_distance(p)])
			var sector: int = decor.sector_of(p)
			var t: Array = totals.get(sector, [0, 0, 0])
			t[0] += 1
			t[1] += int(seen)
			t[2] += int(seen_big)
			totals[sector] = t
			cells.append([lat, lon, step, seen])
		lat += step
	data.coverage = cells
	var names := ["Norte", "Leste", "Sul", "Oeste"]
	var stats := []
	var all := [0, 0, 0]
	for s in 4:
		var t: Array = totals.get(s, [1, 0, 0])
		stats.append("%s: %d%% hoje · %d%% com marcos ×%.1f" % [names[s], 100 * t[1] / t[0], 100 * t[2] / t[0], BIGGER])
		for k in 3:
			all[k] += t[k]
	stats.append("Mundo: %d%% hoje · %d%% com marcos ×%.1f" % [100 * all[1] / all[0], 100 * all[2] / all[0], BIGGER])
	gaps.sort()
	stats.append("Distância até a coisa mais próxima: mediana %d m · 95%% dos pontos ≤ %d m · pior %d m" % [
		int(gaps[gaps.size() / 2]), int(gaps[int(gaps.size() * 0.95)]), int(gaps[gaps.size() - 1])])
	for b in blind:
		print("CEGO lat=%.1f lon=%.1f" % [b.x, b.y])
	data.stats = stats
	for line in stats:
		print("COBERTURA ", line)
	# Desenha por cima de tudo.
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var canvas := Control.new()
	canvas.set_script(load("res://Tests/world_map_canvas.gd"))
	canvas.set("data", data)
	canvas.size = root.get_visible_rect().size
	layer.add_child(canvas)
	for f in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://Builds/WorldMap/mapa_mundo.png"))
	print("MAPA salvo")
	quit()

## Até onde algo de altura h aparece no horizonte (m), com o limite de desenho dos itens.
func _reach(R: float, h: float, _capped: bool) -> float:
	return minf(sqrt(2.0 * R * EYE) + sqrt(2.0 * R * maxf(h, 0.5)), 600.0)
