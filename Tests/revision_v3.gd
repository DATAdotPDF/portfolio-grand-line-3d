extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run_checks")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
func run_checks() -> void:
	root.size = Vector2i(1280,720)
	var world = load("res://MainWorld.tscn").instantiate()
	root.add_child(world)
	var boat = world.ship
	boat.controls_override = true
	await ticks(180)
	check(absf(boat.position.length()-90.0)<0.65,"buoyancy at rest")
	check(boat.measured_speed<0.04,"no drift at rest")
	check(world.islands[0].position.normalized().y>0.9,"About near north pole")
	check(world.islands[4].position.normalized().y < -0.9,"Contact near south pole")
	for i in [1,2,3]:
		check(absf(world.islands[i].position.normalized().y)<0.3,"island %d near equator" % i)
	boat.position = Vector3.UP*90.0
	boat.reset_physics_interpolation()
	boat.heading = Vector3.RIGHT
	boat.test_controls = Vector3(1,0,1)
	await ticks(240)
	check(boat.measured_speed>12.0 and boat.measured_speed<13.0,"Shift reaches 12.5 m/s")
	check(absf(boat.position.length()-90.0)<0.7,"buoyancy with Shift")
	check(world.ocean.wake.size()>0,"moving wake")
	boat.test_controls = Vector3.ZERO
	await ticks(1100)
	check(boat.measured_speed<0.05 and world.ocean.wake.is_empty(),"wake fades at rest")
	for island in world.islands:
		var safe_radius: float = island.get_meta("navigation_radius")
		var normal: Vector3 = island.position.normalized()
		var all_blocked := true
		for direction in range(4):
			var tangent: Vector3 = island.basis.x.rotated(normal,direction*PI*0.5)
			var start: Vector3 = normal*cos((safe_radius+5.0)/90.0)+tangent*sin((safe_radius+5.0)/90.0)
			boat.position = start*90.0
			boat.heading = (island.position-boat.position).slide(start).normalized()
			boat.drive_speed = 12.5
			boat.radial_speed = 0.0
			boat.test_controls = Vector3(1,0,1)
			var blocked := false
			for i in range(150):
				await physics_frame
				blocked = blocked or boat.get_slide_collision_count()>0
				var distance := acos(clampf(boat.position.normalized().dot(normal),-1.0,1.0))*90.0
				all_blocked = all_blocked and distance>1.0 and absf(boat.position.length()-90.0)<0.9
			all_blocked = all_blocked and blocked
		check(all_blocked,"cannot climb or cross island %s from four sides at full Shift" % island.name)
	boat.test_controls = Vector3.ZERO
	boat.enabled = false
	world.ocean.ripples.clear()
	var point := Vector3.UP*90.0
	world.ocean.touch(point)
	world.ocean.ripples[0].w = 0.4
	var disturbed: float = world.ocean.height_at(point)
	world.ocean.ripples.clear()
	check(absf(disturbed-world.ocean.height_at(point))>0.01,"touch displaces water height")
	world.ship.position = point
	world.ship.heading = Vector3.FORWARD
	world.ship.basis = Basis.IDENTITY
	world.ship.reset_physics_interpolation()
	world._update_camera(1.0,true)
	world.camera_hold = true
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = Vector2(500,500)
	press.pressed = true
	world._unhandled_input(press)
	# Exercise the time-driven held-input path deterministically.
	for i in range(8):
		world._process(0.25)
	check(world.ocean.ripples.size()>=6,"holding mouse sustains waves")
	var previous: Vector4 = world.ocean.ripples.back()
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(700,500)
	world._unhandled_input(drag)
	world._process(0.25)
	var current: Vector4 = world.ocean.ripples.back()
	check(Vector3(previous.x,previous.y,previous.z).distance_to(Vector3(current.x,current.y,current.z))>0.5,"drag moves disturbance center")
	press.pressed = false
	world._unhandled_input(press)
	await ticks(260)
	check(world.ocean.ripples.is_empty(),"water disturbance dissipates after release")
	world.clock.set_time(0.5,true)
	world._update_day(0.0)
	var day: float = world.sun.light_energy
	world.clock.set_time(0.0,true)
	world._update_day(0.0)
	check(day>1.0 and world.sun.light_energy<0.01,"day and night change lighting")
	check(world.playlist.size()>1 and not world.music.stream.loop and world.music.playing,"random playlist playing without single-track loop")
	var mute := InputEventKey.new()
	mute.physical_keycode = KEY_M
	mute.pressed = true
	world._unhandled_input(mute)
	check(world.music.stream_paused,"M pauses music")
	boat.position = Vector3.DOWN.rotated(Vector3.FORWARD,0.6)*90.0
	boat.heading = Vector3.FORWARD
	boat.drive_speed = 0.0
	boat.radial_speed = 0.0
	boat.enabled = true
	boat.test_controls = Vector3(1,0.5,0)
	await ticks(180)
	check(boat.basis.is_finite() and absf(boat.basis.determinant()-1.0)<0.001 and boat.basis.y.dot(boat.position.normalized())>0.999,"orientation follows southern hemisphere")
	world.ocean.phase = Vector3.ONE*(TAU-0.001)
	await ticks(2)
	check(world.ocean.phase.x<0.2,"wave phase wraps for long sessions")
	check(world.clock.night_at(Vector3.UP)>0.99 and world.clock.night_at(Vector3.DOWN)<0.01,"opposite hemispheres have local night and day")
	var effects = world.islands[2].get_node("IslandEffects")
	check(effects.cube != null,"Poneglyph isolated")
	if effects.cube:
		var before: Transform3D = effects.cube.transform
		effects._process(0.5)
		check(not effects.cube.transform.is_equal_approx(before),"Poneglyph floats and rotates")
	var lighthouse = world.islands[4].get_node("IslandEffects")
	world.clock.set_time(0.5,true)
	lighthouse._process(3.0)
	check(lighthouse.beam.light_energy>6.0,"south lighthouse lights at local night")
	world.clock.set_time(0.0,true)
	lighthouse._process(3.0)
	check(lighthouse.beam.light_energy<0.1,"south lighthouse switches off at local day")
	boat.enabled = false
	boat.position = Vector3.UP*90.0
	boat.reset_physics_interpolation()
	world._process(0.1)
	check(world.lantern.light_energy>1.5,"boat lamp receives night factor")
	var lamp_key := InputEventKey.new()
	lamp_key.physical_keycode = KEY_L
	lamp_key.pressed = true
	world._unhandled_input(lamp_key)
	world._process(0.1)
	check(not world.lantern.visible,"L disables boat lamp")
	world.select_time("day")
	world._update_day(0.0)
	check(world.sun.light_energy>1.0,"manual day follows boat hemisphere")
	world.select_time("night")
	world._update_day(0.0)
	check(world.sun.light_energy<0.01,"manual night follows boat hemisphere")
	world.select_time("auto")
	check(not world.clock.paused,"automatic cycle resumes")
	var played: Array[String] = [world.current_track]
	for i in range(world.playlist.size()-1):
		world.next_track()
		check(not played.has(world.current_track),"playlist does not repeat track %d"%i)
		played.append(world.current_track)
	check(world.naval.targets.size()==21,"21 targets generated")
	for island_index in range(5):
		var count := 0
		for target in world.naval.targets:
			if target.island==island_index: count+=1
		check(count==3,"three targets near island %d"%island_index)
	var game = world.naval
	game.cooldown=0.0
	boat.velocity=Vector3(2,0,0)
	check(game.fire(),"cannon fires")
	check(not game.fire(),"cannon cooldown prevents spam")
	var ball = game.balls.back()
	check(absf((ball.velocity-boat.velocity).length()-25.0)<0.01,"projectile inherits boat velocity")
	var before_score: int=game.score
	var target: Area3D=game.targets[0].node
	var hit_point: Vector3=target.global_position+target.global_basis.y*0.8
	ball.node.position=hit_point+target.global_basis.z*1.2
	ball.velocity=-target.global_basis.z*25.0
	await ticks(8)
	check(game.score==before_score+1,"swept projectile hits target and scores once")
	game.hit_target(0,hit_point)
	check(game.score==before_score+1,"target hit debounce")
	game.cooldown=0.0
	game.fire()
	ball=game.balls.back()
	ball.node.position=Vector3.UP*92.0
	ball.velocity=Vector3.DOWN*15.0
	var previous_splashes: int=game.splash_count
	await ticks(20)
	check(game.splash_count>previous_splashes,"projectile water impact splashes")
	for island in world.islands:
		check(island.has_node("IslandTitleSign"),"island has parchment title")
	var fort = world.islands[1].get_node("IslandEffects")
	check(fort.decorative_cannons.size()==2,"two fort cannon pieces separated")
	world.camera_hold=true
	world.camera.position=world.islands[1].position+world.islands[1].basis.y*8.0+world.islands[1].basis.z*20.0
	fort.cannon_timer=0.0
	fort._process(0.02)
	await ticks(6)
	var recoiled:=false
	for cannon in fort.decorative_cannons:
		recoiled = recoiled or absf(cannon.node.position.z-cannon.base_z)>0.0001
	check(recoiled,"decorative cannon recoil runs")
	var lighthouse_fx = world.islands[4].get_node("IslandEffects")
	check(lighthouse_fx.snail!=null,"Den Den Mushi separated")
	var treasure_fx = world.islands[3].get_node("IslandEffects")
	check(treasure_fx.treasure_sparks.size()==2,"treasure spark emitters exist")
	var sign=world.islands[0].get_node("IslandTitleSign")
	boat.position=world.islands[0].position+world.islands[0].basis.z*25.0
	await ticks(70)
	check(sign.visible and sign.reveal_amount>0.95,"parchment reveals near coast")
	boat.position=-world.islands[0].position
	await ticks(70)
	check(not sign.visible,"parchment hides far from coast")
	print("REVISION_TESTS failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
