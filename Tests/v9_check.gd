extends SceneTree

const Camera = preload("res://Scripts/PortfolioCameraController.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, name: String) -> void:
	print(("PASS " if condition else "FAIL ") + name)
	if not condition: failures += 1

func run() -> void:
	var world := (load("res://MainWorld.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var camera = world.camera
	check(camera.state == Camera.CameraState.BOAT_FOLLOW, "camera segue a chalupa")
	check(camera.global_position.length() > 200.0, "camera acima da agua")
	camera.focus_island(world.islands[2])
	camera._process(1.1)
	check(camera.state == Camera.CameraState.FLYING and camera.global_position.length() > 206.0, "voo acima da esfera")
	camera._process(1.3)
	check(camera.state == Camera.CameraState.ISLAND_ORBIT, "orbita da ilha")
	camera.show_overview()
	camera._process(2.4)
	check(camera.state == Camera.CameraState.PLANET_OVERVIEW and camera.global_position.length() > 500.0, "visao completa do globo")
	camera.return_to_boat()
	camera._process(2.4)
	check(camera.state == Camera.CameraState.BOAT_FOLLOW, "retorno a chalupa")
	var config := JSON.parse_string(FileAccess.get_file_as_string("res://Export/world_config.json")) as Dictionary
	check(config.get("schema_version", 0) == 1 and is_equal_approx(config.planet.water_radius, 200.0), "JSON usa raio do mundo atual")
	check(config.islands.size() == 5 and config.naval_targets.size() == 20, "JSON inclui ilhas e alvos")
	for i in range(5):
		var item: Dictionary = config.islands[i]
		check(item.id != "" and item.mount.position.size() == 3 and item.mount.quaternion_xyzw.size() == 4, "ilha %d possui pose exportada" % i)
	print("V9_CHECK failures=", failures)
	quit(0 if failures == 0 else 1)
