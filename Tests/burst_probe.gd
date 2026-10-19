extends SceneTree

## Velocidade do barco: cruzeiro (sempre 15 m/s para a frente) e o BURST do IMPULSO com recarga.
## Uso: Godot.exe --path . --headless --script res://Tests/burst_probe.gd

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
	var ship: Node3D = world.ship
	ship.controls_override = true
	ship.test_controls = Vector3(1.0, 0.0, 0.0)
	var t := 0.0
	var log := []
	while t < 14.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		# Aperta o impulso em 4 s (dispara), de novo em 6 s (recarregando: não dispara) e em 10,5 s (pronto).
		var press := (t > 4.0 and t < 4.3) or (t > 6.0 and t < 6.3) or (t > 10.5 and t < 10.8)
		ship.test_controls.z = 1.0 if press else 0.0
		if log.size() < int(t * 2.0):
			log.append("%.1fs %.1f m/s%s" % [t, ship.drive_speed, " (recarga %.1f)" % ship.burst_ready_in if ship.burst_ready_in > 0.0 else ""])
	print("BURST ", " | ".join(log))
	quit()
