extends SceneTree

## Velocidade do barco: cruzeiro (sempre 11 m/s para a frente) e o BURST do IMPULSO: carga de 1,5 s,
## arranque e recarga de 30 s.
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
	while t < 42.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		# Aperta o impulso em 4 s (carrega e dispara em 5,5 s), de novo em 12 s (recarregando: nada) e
		# em 36 s (pronto: 5,5 + 30).
		var press := (t > 4.0 and t < 4.1) or (t > 12.0 and t < 12.1) or (t > 36.0 and t < 36.1)
		ship.test_controls.z = 1.0 if press else 0.0
		if log.size() < int(t * 2.0):
			log.append("%.1fs %.1f m/s%s" % [t, ship.drive_speed, (" (carga)" if ship.burst_charge > 0.0 else (" (recarga %.0f)" % ship.burst_ready_in if ship.burst_ready_in > 0.0 else ""))])
	print("BURST ", " | ".join(log))
	quit()
