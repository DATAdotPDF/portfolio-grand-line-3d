extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures.append(message)

func run() -> void:
	root.size = Vector2i(1280, 720)
	var world: Node3D = load("res://MainWorld.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var radius: float = world.OCEAN_RADIUS
	check(is_equal_approx(radius, 200.0), "raio do globo 200 m")
	check(is_equal_approx(world.ocean.RADIUS, radius), "raio da simulacao de agua")
	check(is_equal_approx((world.get_node("PlanetCore").get_child(0) as CollisionShape3D).shape.radius, 196.0), "leito a 196 m")
	var anchors := world.get_node("IslandAnchors") as Node3D
	check(anchors.get_child_count() == 5 and world.islands.size() == 5, "cinco marcadores e ilhas")
	var nearest_arc := INF
	for i in range(5):
		var anchor := anchors.get_child(i) as Node3D
		var island := world.islands[i] as Node3D
		check(is_equal_approx(anchor.position.length(), radius), "marcador %d na casca" % i)
		check(island.global_transform.is_equal_approx(anchor.global_transform), "ilha %d preserva transformacao do marcador" % i)
		check(island.global_basis.y.normalized().dot(island.position.normalized()) > 0.999, "ilha %d alinhada a gravidade" % i)
		check(island.get_node_or_null("CoastWall") != null and island.get_child(0) != null, "ilha %d conserva modelo e costa" % i)
		var expected_angle := TAU * float(i) / 5.0
		check(absf(wrapf(atan2(anchor.position.z, anchor.position.x) - expected_angle, -PI, PI)) < 0.01, "ilha %d segue rota de 72 graus" % i)
		var sign := island.get_node("IslandTitleSign")
		check(sign.get_node("NameplateMesh").scene_file_path.begins_with("res://Assets/Optimized/"), "placa 3D leve da ilha %d" % i)
		check(not sign.label.visible, "sem texto duplicado na placa %d" % i)
		for j in range(i + 1, 5):
			nearest_arc = minf(nearest_arc, anchor.position.angle_to((anchors.get_child(j) as Node3D).position) * radius)
	check(nearest_arc > 245.0 and nearest_arc < 255.0, "distancia de arco da rota pentagonal")
	check(world.ship.position.length() > radius - 2.0, "chalupa na superficie ampliada")
	check(world.naval.targets.size() == 20, "15 alvos costeiros e cinco em mar aberto")
	for i in range(5):
		for j in range(3):
			var coast: float = load("res://Scripts/Shoreline.gd").distance_to_coast(world.islands[i], world.naval.targets[i * 3 + j].normal * radius)
			check(coast >= [20.0, 35.0, 50.0][j] and coast <= [20.0, 35.0, 50.0][j] + 2.0, "alvo costeiro %d/%d acompanha ilha" % [i, j])
	check(world.wind_streaks.name == "WindRibbonSystem" and world.wind_streaks.get_child_count() == 7, "quatro fitas em laco e tres brisas")
	for ribbon in world.wind_streaks.get_children():
		check(ribbon is MeshInstance3D and ribbon.material_override is ShaderMaterial, "fita de vento por shader")
	var config := ConfigFile.new()
	check(config.load("res://export_presets.cfg") == OK and str(config.get_value("preset.0", "exclude_filter")).contains("Meshy_AI_title_plate"), "placas originais fora do pacote Web")
	check(world.camera.far > radius * 4.0, "camera alcanca o globo")
	var compass: Node3D = world.log_pose
	check(compass != null and compass.player_sloop == world.ship, "Log Pose ligado a chalupa")
	check(compass.islands_parent == world.get_node("Islands"), "Log Pose ligado as ilhas")
	check(compass.get_node_or_null("Base_Mesh") != null, "base do Log Pose")
	check(compass.get_node_or_null("GlassDome_Mesh") != null, "cupula do Log Pose")
	check(compass.get_node_or_null("Needle_Pivot/Needle_Mesh") != null, "agulha separada")
	check(compass.get_parent() is SubViewport and (compass.get_parent() as SubViewport).transparent_bg, "HUD 3D transparente")
	compass._update_nearest_island()
	check(compass.nearest_island == world.islands[0], "Log Pose aponta a ilha mais proxima")
	var ship_position: Vector3 = world.ship.position
	var ship_basis: Basis = world.ship.basis
	var boat_up := ship_position.normalized()
	var toward_first: Vector3 = (world.islands[0] as Node3D).position.normalized().slide(boat_up).normalized()
	world.ship.basis = Basis(toward_first.cross(boat_up), boat_up, -toward_first).orthonormalized()
	check(absf(compass.heading_to((world.islands[0] as Node3D).position)) < 0.01, "agulha marca proa quando alinhada")
	world.ship.basis = world.ship.basis.rotated(boat_up, PI * 0.5)
	check(absf(compass.heading_to((world.islands[0] as Node3D).position)) > 1.5, "agulha muda com o rumo do navio")
	world.ship.position = (world.islands[1] as Node3D).position.normalized() * radius
	compass._update_nearest_island()
	check(compass.nearest_island == world.islands[1], "Log Pose troca de ilha durante navegacao")
	world.ship.position = ship_position
	world.ship.basis = ship_basis
	compass._update_nearest_island()
	var model_transform: Transform3D = (world.islands[0].get_child(0) as Node3D).transform
	anchors.distribute_islands()
	check((world.islands[0].get_child(0) as Node3D).transform.is_equal_approx(model_transform), "redistribuicao nao altera modelo interno")
	check(world.sail_materials.size() > 0, "vela preservada")
	check(world.bow_wave_meshes.size() == 2, "ondas da proa preservadas")
	for frame in range(70):
		await process_frame
	await RenderingServer.frame_post_draw
	(compass.get_parent() as SubViewport).get_texture().get_image().save_png("res://Documentation/Previews/v8_logpose.png")
	root.get_texture().get_image().save_png("res://Documentation/Previews/v8_world.png")
	world.camera.set_process(false)
	world.ship.enabled = false
	world.ship.position = Vector3.UP * radius
	world.ship.basis = Basis.IDENTITY
	world.camera.position = world.ship.position + Vector3(-4.0, 2.4, -4.2)
	world.camera.look_at(world.ship.position + Vector3(0, 0.2, -0.6), Vector3.UP)
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://Documentation/Previews/v8_sail.png")
	var navigation_start: Vector3 = world.ship.position
	world.ship.enabled = true
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1, 0, 1)
	for frame in range(180):
		await physics_frame
	world.ship.test_controls = Vector3.ZERO
	var sailed: float = navigation_start.angle_to(world.ship.position) * radius
	check(sailed > 4.0, "chalupa navega no globo ampliado")
	check(absf(world.ship.position.length() - radius) < 2.0, "chalupa acompanha a superficie ampliada")
	print("CHECKS=", checks, " FAILURES=", failures.size())
	quit(0 if failures.is_empty() else 1)
