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
	report=FileAccess.open("res://Documentation/v6_check.log",FileAccess.WRITE)
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
	check(game.cannon.position.is_equal_approx(Vector3(-0.4,0.204,0.4)),"modular cannon mount")
	check(is_zero_approx(game.cannon.rotation.y),"cannon yaw fixed at zero")
	check(is_equal_approx(game.cannon.pitch_pivot.rotation.y,PI*0.5),"fixed port orientation inside cradle")
	check(game.cannon.carriage!=game.cannon.barrel,"separate carriage and barrel")
	check(game.cannon.barrel.get_parent().name=="RecoilPivot","barrel under independent recoil pivot")
	check(game.cannon.pitch_pivot.position.y>0.1,"pitch pivot at U cradle")
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
	var ambience=world.sea_ambience
	check(ambience.ocean_bed.playing and ambience.ocean_bed.stream is AudioStreamMP3 and ambience.ocean_bed.stream.loop,"ocean ambience loops separately from music")
	check(ambience.gull_call.stream.resource_path.ends_with("SEAGULLS OPEN SEA SFX 1.mp3"),"open-sea gull calls loaded")
	check(ambience.boat_creak.stream is AudioStreamMP3 and ambience.boat_creak.stream.loop,"boat creak loaded as loop")
	check(ambience.bow_crash.stream.resource_path.ends_with("OCEAN WAVE CRASH SFX.mp3"),"bow wave crash loaded")
	check(world.bow_wave_meshes.size()==2,"two continuous bow sheets")
	for mesh in world.bow_wave_meshes:
		check(mesh.get_parent()==world.ship.float_visual and mesh.mesh is PlaneMesh,"bow sheet attached to sloop")
	check(world.water_droplets.amount==12 and is_equal_approx(world.water_droplets.lifetime,0.4),"rare short-lived crest droplets")
	check(not world.water_droplets.emitting,"droplets stop at rest")
	check(game.fuse_audio.stream.resource_path.ends_with("FUSE SFX.wav"),"new fuse recording")
	check(game.shot_audio.stream.resource_path.ends_with("CANNON SHOT SFX.wav"),"new cannon recording")
	check(world.playlist.size()>=20,"new ambient tracks discovered")
	var previous_track:String=world.current_track
	world.music_button.emit_signal("pressed")
	check(world.current_track!=previous_track,"music skip button changes track")
	world.music.stream_paused=true
	world.next_track()
	check(world.music.stream_paused,"music skip preserves pause")
	world.music.stream_paused=false
	await capture("v6_cannon")
	report.store_line("CANNON_GLOBAL="+str(game.cannon.global_position)+" MUZZLE="+str(game.muzzle.global_position)+" CARRIAGE="+str(game.cannon.carriage.global_position))
	world.camera.position=world.ship.position+Vector3(0,8,3)
	world.camera.look_at(world.ship.position,Vector3.UP)
	await ticks(15)
	await capture("v6_deck_top")
	world.camera.position=world.ship.position+Vector3(-4.0,2.4,-4.2)
	world.camera.look_at(world.ship.position+Vector3(0,0.2,-0.6),Vector3.UP)
	world.ship.measured_speed=6.0
	await ticks(35)
	check(world.bow_wave_meshes[0].visible and world.bow_wave_meshes[1].visible,"bow sheets visible while sailing")
	check(world.water_droplets.emitting,"crest droplets start above 3 m/s")
	check(ambience.boat_creak.playing,"wooden hull audio starts with movement")
	check(game.debris.is_empty(),"no CPU droplet cloud follows the ship")
	await capture("v6_bow_wave_port")
	world.ship.measured_speed=0.0
	await ticks(5)
	for i in range(3): await process_frame
	report.store_line("BOW_REST speed="+str(world.ship.measured_speed)+" mesh="+str(world.bow_wave_meshes[0].visible)+" droplets="+str(world.water_droplets.emitting))
	check(not world.bow_wave_meshes[0].visible and not world.water_droplets.emitting,"bow wave fades at rest")
	var carriage_before:Transform3D=game.cannon.carriage.transform
	game.aim_elevation=deg_to_rad(30.0)
	game._update_aim()
	await ticks(50)
	check(game.cannon.carriage.transform.is_equal_approx(carriage_before),"pitch leaves wheels on deck")
	check(absf(rad_to_deg(game.cannon.pitch_pivot.rotation.x))>12.0,"barrel elevates")
	await capture("v6_cannon_elevated")
	check(game.fire(),"fuse starts")
	await ticks(65)
	check(game.shots_fired==1,"cannon fires after fuse")
	check(not game.balls.is_empty() and game.balls[0].node.has_node("CannonballDoppler"),"projectile plays Doppler SFX")
	check(game.cannon.carriage.transform.is_equal_approx(carriage_before) and is_zero_approx(game.cannon.rotation.y),"fire keeps carriage fixed")
	var target:Dictionary=game.targets[0]
	game.hit_target(0,target.node.global_position)
	check(not target.active and not target.node.visible,"target destroyed")
	check(hit_manager.bell.playing,"hitmarker sounds")
	check(root.get_node_or_null("WoodHit3D")!=null or world.get_node_or_null("WoodHit3D")!=null,"positional wood hit sounds")
	var wood_hit:AudioStreamPlayer3D=root.get_node_or_null("WoodHit3D") if root.get_node_or_null("WoodHit3D") else world.get_node_or_null("WoodHit3D")
	check(wood_hit.stream.resource_path.ends_with("WOOD IMPACT CANON BALL SFX.wav"),"new wood impact recording")
	game._play_impact("explosion",world.ship.global_position)
	game.splash(world.ship.global_position+Vector3.RIGHT*5.0)
	var explosion_found:=false
	var splash_found:=false
	for child in game.get_children():
		if child is AudioStreamPlayer3D and child.stream:
			explosion_found=explosion_found or child.stream.resource_path.ends_with("EXPLOSION SFX.wav")
			splash_found=splash_found or child.stream.resource_path.ends_with("WATER SPLASH CANON BALL SFX.wav")
	check(explosion_found and splash_found,"new explosion and water splash recordings")
	check(failures.is_empty(),"all checks")
	report.store_line("FAILURES="+str(failures.size()))
	report.flush()
	quit(0 if failures.is_empty() else 1)
