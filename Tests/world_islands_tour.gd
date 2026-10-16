extends SceneTree

## Tour de TODAS as ilhas do mundo com a iluminação do jogo e gráficos no Alto, sem HUD:
## - "stills": um print de cada ilha principal (5) e de um exemplar de cada modelo do WorldDecor (12);
## - "orbit": volta de 360° (6 s) em cada modelo do WorldDecor, em sequência (usar com --write-movie).
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/world_islands_tour.gd -- stills
##      Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie Builds/Videos/ilhas_mapa_360.avi
##           --script res://Tests/world_islands_tour.gd -- orbit

const ORBIT_SECONDS := 6.0

var world: Node3D
var camera: Camera3D
var out_dir := "res://Builds/WorldIslands"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var orbit := "orbit" in OS.get_cmdline_user_args()
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.graphics.set_mode("alto")
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	world.sea_life.sea_shadows.timer = 9999.0
	world.sea_life.dolphin_timer = 9999.0
	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = 50.0
	root.add_child(camera)
	var targets := _targets(not orbit)
	print("TOUR alvos=%d" % targets.size())
	for t in targets:
		await _visit(t, orbit)
	quit()

## [nome, nó, raio, altura da câmera, altura olhada]
func _targets(with_main: bool) -> Array:
	var list := []
	if with_main:
		var names := ["sobre", "experiencia", "formacao", "projetos", "contato"]
		var framing := [[30.0, 12.0, 4.0], [44.0, 20.0, 9.0], [34.0, 14.0, 6.0], [34.0, 13.0, 4.0], [50.0, 22.0, 15.0]]
		for i in world.islands.size():
			list.append(["%d_%s" % [i + 1, names[i]], world.islands[i]] + framing[i])
	var decor: Node = world.world_decor
	var seen := {}
	for item in decor.items:
		if seen.has(item.kind): continue
		seen[item.kind] = true
		var root_node: Node3D = item.root
		var box := AABB()
		var first := true
		for mesh in root_node.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = root_node.global_transform.affine_inverse() * mesh.global_transform * mesh.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		# A caixa está no espaço do nó; os modelos são escalados no mundo.
		var k := root_node.global_basis.get_scale().x
		var size := maxf(box.size.x, box.size.z) * k
		var tall := box.size.y * k
		list.append(["mapa_" + str(item.kind), root_node, maxf(maxf(size, tall) * 1.5, 7.0), maxf(tall * 0.6 + size * 0.2, 4.0), box.get_center().y * k])
	return list

func _visit(t: Array, orbit: bool) -> void:
	var target: Node3D = t[1]
	var up := target.global_position.normalized()
	var side := target.global_basis.z.slide(up).normalized()
	# Barco a ~70 m: o mar detalhado (patch), as ondas e o balanço das boias ficam ativos ali perto.
	var pos: Vector3 = world.ocean.surface_at(target.global_position + side.rotated(up, PI * 0.5) * 70.0)
	var forward := side.cross(pos.normalized()).normalized()
	world.ship.heading = forward
	world.ship.global_transform = Transform3D(Basis(forward.cross(pos.normalized()).normalized(), pos.normalized(), -forward), pos)
	world.ship.drive_speed = 0.0
	var frames := int(ORBIT_SECONDS * 30.0) if orbit else 20
	for i in frames:
		for layer in world.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		var center := target.global_position
		up = center.normalized()
		var angle := TAU * float(i) / frames if orbit else deg_to_rad(35.0)
		var dir := target.global_basis.z.slide(up).normalized().rotated(up, angle)
		camera.make_current()
		camera.look_at_from_position(center + dir * float(t[2]) + up * float(t[3]), center + up * float(t[4]), up)
		await process_frame
	if not orbit:
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("%s/%s.jpg" % [out_dir, t[0]]), 0.9)
		print("PRINT ", t[0])
	else:
		print("ORBIT ", t[0])
