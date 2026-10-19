extends SceneTree

## Peso do barco: navega reto 40 s na velocidade de cruzeiro (mar aberto, depois tempestade) e mede
## quanto tempo fica no ar, o maior salto (altura acima da água) e quantos saltos.
## Uso: Godot.exe --path . --headless --script res://Tests/hull_weight_probe.gd

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.hud._set_carta_open(false)
	var ship: Node3D = world.ship
	ship.controls_override = true
	for sea in ["mar aberto", "burst", "tempestade"]:
		var p: Vector3 = world.weather.open_sea[(world.weather.open_sea.size() / 4) * (2 if sea == "tempestade" else 1)]
		var up := p.normalized()
		var f := Vector3.FORWARD.slide(up).normalized()
		ship.heading = f
		ship.drive_speed = ship.cruise_speed
		ship.burst_ready_in = 0.0
		ship.global_transform = Transform3D(Basis(f.cross(up).normalized(), up, -f), world.ocean.surface_at(p * world.planet_radius))
		ship.reset_physics_interpolation()
		if sea == "tempestade":
			world.weather.call("force_storm") if world.weather.has_method("force_storm") else null
		var air := 0.0
		var jumps := 0
		var high := 0.0
		var was := false
		var t := 0.0
		var frame := 0
		while t < 40.0:
			await physics_frame
			frame += 1
			var dt := 1.0 / Engine.physics_ticks_per_second
			t += dt
			ship.test_controls = Vector3(1, 0, 1.0 if sea == "burst" and frame % 2 == 0 else 0.0)
			var a: bool = ship.airborne
			if a:
				air += dt
				var water: float = world.ocean.surface_at(ship.global_position).length()
				high = maxf(high, ship.global_position.length() - water)
			if a and not was:
				jumps += 1
			was = a
		print("WEIGHT %s: no ar %.1f%% do tempo, %d saltos, maior %.2f m acima da água" % [sea, air / t * 100.0, jumps, high])
	quit()
