extends SceneTree

## Prints do README/docs com o jogo atual: o barco a ~130 m de cada marco (cidades, colossos, vulcão,
## cemitério), câmera atrás do barco olhando o alvo, sem HUD; e um de noite com as runas.
## Uso: Godot.exe --path . --resolution 1600x900 --script res://Tests/docs_shots.gd -- --out=<pasta>

var world: Node3D
var cam: Camera3D
var out_dir := "res://Builds/DocsShots"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	call_deferred("run")

func shot(name: String) -> void:
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.get_texture().get_image().save_jpg(out_dir.path_join(name + ".jpg"), 0.9)
	print("DOCS print ", name)

## Barco a dist m do alvo (na direção do sol de lado), proa para o alvo; câmera atrás e acima do barco.
func frame(target: Vector3, dist: float, height: float, side := 0.0) -> void:
	var up := target.normalized()
	var east := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var away := east.rotated(up, side)
	var boat: Vector3 = world.ocean.surface_at(target + away * dist)
	var boat_up := boat.normalized()
	var fwd := (target - boat).slide(boat_up).normalized()
	world.ship.heading = fwd
	world.ship.global_transform = Transform3D(Basis(fwd.cross(boat_up).normalized(), boat_up, -fwd), boat)
	var eye := boat - fwd * 30.0 + boat_up * height
	cam.look_at_from_position(eye, target + up * height * 0.6, boat_up)

func item_of(kind: String) -> Node3D:
	for item in world.world_decor.items:
		if item.kind == kind:
			return item.root
	return null

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.make_current()
	var shots := [["runestone_citadel", 150.0, 34.0], ["driftwood_merchant", 150.0, 34.0], ["coral_paradise", 140.0, 30.0],
		["basalt_caldera", 140.0, 34.0], ["ship_graveyard", 100.0, 26.0], ["split_monolith_runes", 120.0, 30.0],
		["leviathan_jaw_arch", 95.0, 24.0], ["turtle_island", 230.0, 45.0]]
	for s in shots:
		var target := item_of(s[0])
		if target == null:
			print("DOCS sem ", s[0])
			continue
		frame(target.global_position, s[1], s[2], 0.6)
		await create_timer(1.2).timeout
		await shot("dia_" + s[0])
	var beasts: Array = world.sea_beasts.beasts if world.get("sea_beasts") else []
	for beast in beasts:
		var r: Node3D = beast.root
		frame(r.global_position, 190.0, 40.0, 0.4)
		await create_timer(1.2).timeout
		await shot("colosso_" + str(beast.name))
	world.select_time("night")
	await create_timer(2.0).timeout
	var monolith := item_of("split_monolith_runes")
	if monolith:
		frame(monolith.global_position, 120.0, 30.0, 0.6)
		await create_timer(1.5).timeout
		await shot("noite_split_monolith_runes")
	quit()
