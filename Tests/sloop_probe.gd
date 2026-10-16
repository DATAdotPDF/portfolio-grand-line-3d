extends SceneTree

## Confere a chalupa em partes: proa sem a Jolly Roger vazando, velas/bandeira com vento e o leme girando.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/sloop_probe.gd
## Saída: Builds/SloopProbe/*.jpg

var world: Node3D
var cam: Camera3D

func _initialize() -> void:
	call_deferred("run")

## Câmera presa ao barco (offset no espaço do barco: x = boreste, y = cima, z = popa).
func shot(name: String, offset: Vector3, look: Vector3) -> void:
	for i in 12:
		var t: Transform3D = world.ship.get_global_transform_interpolated()
		cam.global_position = t * offset
		cam.look_at(t * look, t.basis.y)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/SloopProbe/%s.jpg" % name), 0.85)

## Centro da pá do leme no espaço do barco (x = boreste). Comparado com o leme reto: > 0 = pá foi para a direita.
var blade_rest := Vector3.ZERO
func blade_local() -> Vector3:
	var mesh := world.rudder as MeshInstance3D
	if mesh == null:
		mesh = world.rudder.find_children("*", "MeshInstance3D", true, false)[0]
	return world.ship.global_transform.affine_inverse() * (mesh.global_transform * mesh.mesh.get_aabb().get_center())

func blade_side() -> float:
	return blade_local().x - blade_rest.x

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/SloopProbe"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.clock.set_time(0.40, true)
	world.select_time("day")
	await create_timer(2.0).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1, 0, 0)
	await create_timer(3.0).timeout
	cam = Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.make_current()
	var parts := []
	for n in ["Hull", "Sail_Main", "Sail_Stern", "Flag", "Rudder"]:
		parts.append("%s=%s" % [n, world.sail_model.find_child(n, true, false) != null])
	print("SLOOP parts ", " ".join(parts), " cloth=", world.sail_materials.size(), " rudder=", world.rudder != null)
	blade_rest = blade_local()
	await shot("bow", Vector3(-3.0, 1.6, -6.5), Vector3(0, 1.0, -1.5))
	await shot("side", Vector3(-7.5, 2.0, 0.5), Vector3(0, 1.4, 0))
	world.ship.test_controls = Vector3(1, 1, 0)
	await create_timer(1.5).timeout
	print("SLOOP right turn_input=%.2f blade_to_starboard=%.3f" % [world.ship.turn_input, blade_side()])
	await shot("stern_turning", Vector3(3.5, 1.2, 6.0), Vector3(0, 0.3, 1.8))
	world.ship.test_controls = Vector3(1, -1, 0)
	await create_timer(1.5).timeout
	print("SLOOP left turn_input=%.2f blade_to_starboard=%.3f" % [world.ship.turn_input, blade_side()])
	await shot("stern_turning_other", Vector3(-3.5, 1.2, 6.0), Vector3(0, 0.3, 1.8))
	# Velas cheias em velocidade (boost) x quase paradas: mesma câmera de lado/proa.
	world.ship.test_controls = Vector3(1, 0, 1)
	await create_timer(4.0).timeout
	print("SLOOP fast speed=", world.ship.measured_speed)
	await shot("sails_fast", Vector3(-6.0, 2.4, -3.0), Vector3(0, 2.0, 0.6))
	world.ship.test_controls = Vector3(0, 0, 0)
	await create_timer(6.0).timeout
	print("SLOOP slow speed=", world.ship.measured_speed)
	await shot("sails_slow", Vector3(-6.0, 2.4, -3.0), Vector3(0, 2.0, 0.6))
	quit()
