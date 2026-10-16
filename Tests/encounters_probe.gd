extends SceneTree

## Encontros com a câmera do jogo: cada espécie de silhueta (grupos), arraias brilhando à noite,
## evento do kraken (subida, redemoinho e cartão do naufrágio), perseguição do navio fantasma até o
## Baú do Davy Jones, sol/lua no HUD e o mapa com o sol e o lado da noite.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/encounters_probe.gd

var world: Node3D
var out_dir := "res://Builds/Encounters"

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
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(2.0).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	world.hud.call("set_carta_open", false) if world.hud.has_method("set_carta_open") else null
	# Mar aberto (longe das ilhas) para os encontros.
	var p: Vector3 = world.weather.open_sea[world.weather.open_sea.size() / 3]
	place(p * world.planet_radius, Vector3.FORWARD.slide(p).normalized())
	await create_timer(3.0).timeout
	await _species()
	await _kraken()
	await _ghost()
	await _map()
	quit()

func _species() -> void:
	var shadows: Node = world.sea_life.sea_shadows
	var ship: Node3D = world.ship
	for species in ["tubarao", "arraia", "foca", "jubarte", "tubarao_baleia"]:
		for g in shadows.groups:
			shadows._free_group(g)
		shadows.groups.clear()
		var up: Vector3 = ship.global_position.normalized()
		var right: Vector3 = ship.heading.cross(up).normalized()
		var big: bool = species in ["jubarte", "tubarao_baleia"]
		var at: Vector3 = ship.global_position + ship.heading * (16.0 if big else 11.0) - right * (8.0 if big else 4.0)
		var g: Dictionary = shadows.spawn(species, at, ship.heading.rotated(up, 0.6))
		g.age = float(g.fade) + 0.5
		await frames(40)
		await still("species_%s" % species)
	# Arraias à noite (bioluminescência).
	world.select_time("night")
	await frames(30)
	for g in shadows.groups:
		shadows._free_group(g)
	shadows.groups.clear()
	var up2: Vector3 = ship.global_position.normalized()
	var g2: Dictionary = shadows.spawn("arraia", ship.global_position + ship.heading * 11.0, ship.heading.rotated(up2, 0.6))
	g2.age = 4.0
	await frames(40)
	await still("species_arraia_noite")
	for g in shadows.groups:
		shadows._free_group(g)
	shadows.groups.clear()
	world.select_time("day")
	await frames(20)

func _kraken() -> void:
	var kraken: Node = world.kraken_event
	print("KRAKEN can_start=", kraken.can_start())
	kraken.start()
	await create_timer(4.0).timeout
	await still("kraken_rise")
	await create_timer(4.0).timeout
	await still("kraken_whirlpool")
	# Perde: barco no miolo.
	place(kraken.center + world.ship.heading * 2.0, world.ship.heading)
	await frames(10)
	await still("kraken_card")
	world.easter_egg.close_card()
	await create_timer(6.5).timeout
	print("KRAKEN phase_after=", kraken.phase)

func _ghost() -> void:
	world.select_time("night")
	await frames(40)
	var ghost: Node3D = world.ghost_ship
	ghost.require_night = false
	if ghost.model == null:
		ghost._build()
	var ship: Node3D = world.ship
	var up: Vector3 = ship.global_position.normalized()
	var right: Vector3 = ship.heading.cross(up).normalized()
	ghost.position = (ship.global_position + ship.heading * 45.0 + right * 10.0).normalized() * world.planet_radius
	ghost.heading = -ship.heading
	ghost.active = true
	ghost.leaving = false
	ghost.presence = 0.95
	ghost.visible = true
	await create_timer(1.5).timeout
	print("GHOST chasing=", ghost.chasing)
	await still("ghost_chase")
	var t0 := Time.get_ticks_msec()
	while not world.easter_egg.visible and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	await frames(5)
	await still("ghost_davy_jones")
	world.easter_egg.close_card()
	await frames(10)

func _map() -> void:
	world.select_time("auto")
	await frames(10)
	await still("hud_sky")
	world.toggle_map()
	await create_timer(3.0).timeout
	await still("map_sun_night_side")
