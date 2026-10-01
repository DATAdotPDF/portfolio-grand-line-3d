extends SceneTree
var failures: Array[String] = []
var report: FileAccess
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	report.store_line(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func ticks(count: int) -> void:
	for i in range(count): await physics_frame
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://Documentation/Previews/"+name+".png")
func run() -> void:
	report=FileAccess.open("res://Documentation/v5_check.log",FileAccess.WRITE)
	root.size=Vector2i(1280,720)
	var world=load("res://MainWorld.tscn").instantiate()
	root.add_child(world)
	world.camera_hold=true
	world.ship.enabled=false
	world.ship.position=Vector3.UP*90.0
	world.ship.basis=Basis.IDENTITY
	world.ship.reset_physics_interpolation()
	world.select_time("day")
	world.camera.position=world.ship.position+Vector3(-4.0,3.0,4.0)
	world.camera.look_at(world.ship.position+Vector3(0,0.7,0),Vector3.UP)
	var game=world.naval
	await ticks(90)
	check(game.cannon_yaw.position.is_equal_approx(Vector3(-0.4,0.204,0.4)),"modular cannon mount")
	check(game.cannon_yaw.carriage!=game.cannon_yaw.barrel,"separate carriage and barrel")
	check(game.cannon_yaw.barrel.get_parent().name=="RecoilPivot","barrel under independent recoil pivot")
	check(game.cannon_yaw.pitch_pivot.position.y>0.1,"pitch pivot at U cradle")
	check(game.targets.size()==21,"15 coastal and six open-sea targets")
	for i in range(5):
		var coast:float=load("res://Scripts/Shoreline.gd").distance_to_coast(world.islands[i],game.targets[i*3].normal*90.0)
		check(coast>=14.0 and coast<=26.0,"coastal target spacing island %d"%i)
		var sign=world.islands[i].get_node("IslandTitleSign")
		check(sign.label.text==["SOBRE","EXPERIÊNCIA","FORMAÇÃO","PROJETOS","CONTATO"][i],"concise sign %d"%i)
	var hit_manager=root.get_node("HitSoundManager")
	check(hit_manager.bell.stream!=null,"2D hitmarker ready")
	check(world.sail_materials.size()>0,"sail material with wind and emblem")
	check(world.wind_streaks!=null,"wind streaks created")
	await capture("v5_cannon")
	report.store_line("CANNON_GLOBAL="+str(game.cannon_yaw.global_position)+" MUZZLE="+str(game.muzzle.global_position)+" CARRIAGE="+str(game.cannon_yaw.carriage.global_position))
	world.camera.position=world.ship.position+Vector3(0,8,3)
	world.camera.look_at(world.ship.position,Vector3.UP)
	await ticks(15)
	await capture("v5_deck_top")
	var carriage_before:Transform3D=game.cannon_yaw.carriage.transform
	game.aim_elevation=deg_to_rad(30.0)
	game._update_aim()
	await ticks(50)
	check(game.cannon_yaw.carriage.transform.is_equal_approx(carriage_before),"pitch leaves wheels on deck")
	check(absf(rad_to_deg(game.cannon_yaw.pitch_pivot.rotation.x))>12.0,"barrel elevates")
	await capture("v5_cannon_elevated")
	check(game.fire(),"fuse starts")
	await ticks(90)
	check(game.shots_fired==1,"cannon fires after fuse")
	var target:Dictionary=game.targets[0]
	game.hit_target(0,target.node.global_position)
	check(not target.active and not target.node.visible,"target destroyed")
	check(hit_manager.bell.playing,"hitmarker sounds")
	check(root.get_node_or_null("WoodHit3D")!=null or world.get_node_or_null("WoodHit3D")!=null,"positional wood hit sounds")
	check(failures.is_empty(),"all checks")
	report.store_line("FAILURES="+str(failures.size()))
	report.flush()
	quit(0 if failures.is_empty() else 1)
