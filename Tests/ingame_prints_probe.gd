extends SceneTree

## Prints com a câmera do jogo: canhão (mira segurada, tiro, recarga), golfinhos (silhueta
## embaixo d'água e salto) e navio fantasma à noite. Silhuetas e eventos: encounters_probe.gd.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/ingame_prints_probe.gd
## Com "-- touch": liga os controles de toque (prints do layout mobile).

var world: Node3D
var out_dir := "res://Builds/InGamePrints"

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("%s/%s.jpg" % [out_dir, name]), 0.85)
	print("PRINT ", name)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func place(pos: Vector3, heading: Vector3) -> void:
	var ship: Node3D = world.ship
	var surface: Vector3 = world.ocean.surface_at(pos)
	var up := surface.normalized()
	var forward := heading.slide(up).normalized()
	ship.heading = forward
	ship.global_transform = Transform3D(Basis(forward.cross(up).normalized(), up, -forward), surface)
	ship.drive_speed = 0.0

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var touch := "touch" in OS.get_cmdline_user_args()
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(2.0).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	# A câmera do jogo ainda está chegando da abertura: espera assentar atrás do barco.
	await create_timer(3.0).timeout
	if touch:
		var controls: Node = world.find_child("TouchControls", true, false)
		if controls:
			controls.call("enable")
		await frames(20)
		await still("mobile_hud")
	if not "skip_cannon" in OS.get_cmdline_user_args():
		await _cannon()
	if touch:
		quit()
		return
	if not "skip_dolphins" in OS.get_cmdline_user_args():
		await _dolphins()
	await _ghost()
	quit()

## Coloca uma boia de lado (no rumo do cano), acha a elevação que cai nela, segura, solta.
func _cannon() -> void:
	var naval: Node = world.naval
	var buoy: Dictionary = {}
	for t in naval.targets:
		if not naval.is_course_target(t):
			buoy = t
			break
	var buoy_pos: Vector3 = (buoy.normal as Vector3) * world.planet_radius
	var up := buoy_pos.normalized()
	# Rumo qualquer; o lado do canhão sai do cano depois de posicionar.
	var heading := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP).normalized()
	place(buoy_pos, heading)
	await frames(3)
	var side: Vector3 = (-naval.muzzle.global_basis.z).slide(up).normalized()
	place(buoy_pos - side * 26.0, heading)
	await frames(30)
	# Elevação que leva a parábola até a boia (busca simples pela simulação da mira).
	var best := 0.0
	var best_err := INF
	for deg in range(-3, 31):
		naval.aim_elevation = deg_to_rad(float(deg))
		var pos: Vector3 = naval.muzzle.global_position
		var vel: Vector3 = naval._launch_velocity()
		for i in 160:
			vel -= pos.normalized() * 9.8 * 0.05
			pos += vel * 0.05
			if pos.length() <= world.planet_radius + float(world.ocean.height_at(pos)):
				break
		var err := pos.distance_to(buoy_pos)
		if err < best_err:
			best_err = err
			best = float(deg)
	naval.aim_elevation = deg_to_rad(best)
	print("CANNON aim=", best, " landing_err=", snappedf(best_err, 0.1))
	naval.begin_aim()
	await frames(20)
	await still("cannon_aim")
	var hits_before: int = naval.score
	naval.release_aim()
	await frames(8)
	await still("cannon_fired_reload")
	await create_timer(2.5).timeout
	print("CANNON hit=", naval.score > hits_before, " shots=", naval.shots_fired, " cooldown=", naval.cooldown)
	# Segurar durante a recarga e soltar: sai sozinho quando carregar.
	naval.begin_aim()
	naval.release_aim()
	naval.begin_aim()
	naval.cooldown = 1.0
	naval.release_aim()
	var shots: int = naval.shots_fired
	await create_timer(1.3).timeout
	print("CANNON queued_fire_ok=", naval.shots_fired == shots + 1)

func _dolphins() -> void:
	var life: Node = world.sea_life
	world.ship.test_controls = Vector3(1.0, 0.0, 0.0)
	await create_timer(2.0).timeout
	life.spawn_pod(3)
	var under := false
	var jump := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 14000 and not (under and jump):
		await process_frame
		for d in life.dolphins:
			var lift: float = (d.position as Vector3).length() - (world.ocean.surface_at(d.position) as Vector3).length()
			if not under and lift < -1.0 and d.age > 2.5:
				under = true
				await still("dolphin_underwater_silhouette")
				break
			if not jump and lift > 0.9:
				jump = true
				await still("dolphin_jump")
				break
	world.ship.test_controls = Vector3.ZERO

func _ghost() -> void:
	world.select_time("night")
	world.clock.set("paused", false)
	# Noite em volta do barco: o modo manual de hora gira o sol para o lado oposto.
	await frames(60)
	var ghost: Node3D = world.ghost_ship
	ghost.require_night = false
	ghost.vanish_distance = 0.0
	if ghost.model == null:
		ghost._build()
	var ship: Node3D = world.ship
	var up: Vector3 = ship.global_position.normalized()
	var right: Vector3 = ship.heading.cross(up).normalized()
	ghost.position = (ship.global_position + ship.heading * 38.0 + right * 9.0).normalized() * world.planet_radius
	ghost.heading = -right
	ghost.active = true
	ghost.leaving = false
	ghost.presence = 0.0
	ghost.visible = true
	await create_timer(1.6).timeout
	await still("ghost_materializing")
	await create_timer(5.0).timeout
	await still("ghost_full")
