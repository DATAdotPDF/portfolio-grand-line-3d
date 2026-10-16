extends SceneTree

## Ondinhas de contato: anéis saindo de onde as coisas encostam na água (shader) e ondinhas das
## coisas que se mexem (ocean.touch): um POI fixo, uma boia e a tartaruga. Câmera parada perto.
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie Builds/Videos/ondinhas.avi
##      --script res://Tests/contact_ripples_video.gd

var world: Node3D
var cam: Camera3D

func _initialize() -> void:
	call_deferred("run")

func park(target: Node3D, distance: float) -> void:
	var up := target.global_position.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var pos: Vector3 = world.ocean.surface_at(target.global_position + side * distance)
	var fwd := side.cross(pos.normalized()).normalized()
	world.ship.heading = fwd
	world.ship.global_transform = Transform3D(Basis(fwd.cross(pos.normalized()).normalized(), pos.normalized(), -fwd), pos)
	world.ship.drive_speed = 0.0

func show(target: Node3D, radius: float, seconds: float, follow := false) -> void:
	park(target, radius + 60.0)
	var up := target.global_position.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var offset := side.rotated(up, 0.9) * (radius * 1.6 + 6.0) + up * (radius * 0.35 + 3.0)
	for i in int(seconds * 30.0):
		for layer in world.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		var c := target.global_position
		cam.look_at_from_position(c + (offset if not follow else target.global_basis * Vector3(radius * 1.4, radius * 0.4 + 3.0, radius * 1.2)), c, c.normalized())
		await process_frame

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.graphics.set_mode("alto")
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.make_current()
	var fixed: Dictionary = {}
	var floating: Dictionary = {}
	for item in world.world_decor.items:
		if fixed.is_empty() and item.kind == "stepped_basalt_reef":
			fixed = item
		if floating.is_empty() and bool(item.get("float", false)):
			floating = item
	if not fixed.is_empty():
		print("RIPPLE fixed ", fixed.kind)
		await show(fixed.root, float(fixed.radius), 8.0)
	if not floating.is_empty():
		print("RIPPLE floating ", floating.kind)
		await show(floating.root, 3.0, 7.0)
	var turtle: Dictionary = world.world_decor.turtle
	if not turtle.is_empty():
		print("RIPPLE turtle")
		await show(turtle.item.root, float(turtle.item.radius), 9.0, true)
	quit()
