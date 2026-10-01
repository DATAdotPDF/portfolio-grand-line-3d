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
	check(is_equal_approx(radius, 280.0), "raio do globo 280 m")
	check(is_equal_approx(world.ocean.RADIUS, radius), "raio da simulacao de agua")
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
		for j in range(i + 1, 5):
			nearest_arc = minf(nearest_arc, anchor.position.angle_to((anchors.get_child(j) as Node3D).position) * radius)
	check(nearest_arc > 200.0, "ilhas separadas em todo o globo")
	check(world.ship.position.length() > radius - 2.0, "chalupa na superficie ampliada")
	check(world.naval.targets.size() == 21, "alvos preservados")
	for i in range(5):
		var coast: float = load("res://Scripts/Shoreline.gd").distance_to_coast(world.islands[i], world.naval.targets[i * 3].normal * radius)
		check(coast >= 14.0 and coast <= 26.0, "alvo costeiro %d acompanha ilha" % i)
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
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	(compass.get_parent() as SubViewport).get_texture().get_image().save_png("res://Documentation/Previews/v7_logpose.png")
	root.get_texture().get_image().save_png("res://Documentation/Previews/v7_world.png")
	world.camera_hold = true
	world.ship.enabled = false
	world.ship.position = Vector3.UP * radius
	world.ship.basis = Basis.IDENTITY
	world.camera.position = world.ship.position + Vector3(-4.0, 2.4, -4.2)
	world.camera.look_at(world.ship.position + Vector3(0, 0.2, -0.6), Vector3.UP)
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://Documentation/Previews/v7_sail.png")
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
