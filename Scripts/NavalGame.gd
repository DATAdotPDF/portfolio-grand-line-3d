extends Node3D

signal time_attack_finished(completed: bool, hits: int, total: int, seconds_used: float, hit_events: Array[Dictionary])

const TARGET = preload("res://Assets/Optimized/naval_target.glb")
const BALL = preload("res://Assets/Optimized/cannonball.glb")
const DOPPLER_SFX = preload("res://Assets/Sound/SFX/CANON BALL DOPPLER SFX.wav")
const EXPLOSION_SFX = preload("res://Assets/Sound/SFX/EXPLOSION SFX.wav")
const SPLASH_SFX = preload("res://Assets/Sound/SFX/WATER SPLASH CANON BALL SFX.wav")
const Shore = preload("res://Scripts/Shoreline.gd")
const Scale = preload("res://Scripts/WorldScale.gd")
var OCEAN_RADIUS := Scale.radius()
var world: Node3D
var targets: Array[Dictionary] = []
var balls: Array[Dictionary] = []
var debris: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var cannon
var cannon_pitch: Node3D
var muzzle: Marker3D
const Parts = preload("res://Scripts/MeshParts.gd")
@export var fuse_duration := 1.0
@export var target_respawn_seconds := 20.0
@export var time_attack_duration := 180.0
var fuse_remaining := 0.0
var fuse_light: OmniLight3D
var fuse_audio: AudioStreamPlayer3D
var barrel: Node3D
var barrel_base := Vector3.ZERO
var shot_audio: AudioStreamPlayer3D
var aim_elevation := deg_to_rad(12.0)
var aim_azimuth := 0.0
var cooldown := 0.0
var score := 0
var elapsed := 0.0
var hud: Label
var rng := RandomNumberGenerator.new()
var drop_mesh: SphereMesh
var wood_mesh: BoxMesh
var splash_count := 0
var shots_fired := 0
var time_attack_mode := false
var time_attack_running := false
var time_attack_remaining := 0.0
var time_attack_hits: Dictionary = {}
var time_attack_events: Array[Dictionary] = []
## Mira vinda dos controles de toque (x = giro, y = inclinação).
var virtual_aim := Vector2.ZERO

func start_time_attack() -> void:
	time_attack_mode = true
	time_attack_running = true
	time_attack_remaining = time_attack_duration
	time_attack_hits.clear()
	time_attack_events.clear()
	# Durante a regata só as boias do percurso ficam na água.
	for target in targets:
		_set_target_active(target, is_course_target(target))

func leave_time_attack() -> void:
	time_attack_mode = false
	time_attack_running = false
	time_attack_remaining = 0.0
	time_attack_hits.clear()
	time_attack_events.clear()
	for target in targets:
		_set_target_active(target, true)

func _set_target_active(target: Dictionary, active: bool) -> void:
	target.active = active
	target.node.visible = active
	target.node.collision_layer = 4 if active else 0
	target.blocker.collision_layer = 8 if active else 0

func _finish_time_attack(completed: bool) -> void:
	if not time_attack_running:
		return
	time_attack_running = false
	time_attack_finished.emit(
		completed,
		time_attack_hits.size(),
		course_count,
		time_attack_duration - time_attack_remaining,
		time_attack_events.duplicate(true)
	)

func _ready() -> void:
	process_physics_priority = -10
	rng.seed = 20260930
	_build_cannon()
	_build_targets()
	_build_particles()
	# O HUD do portfólio fornece o painel do canhão; sem ele, cai no rótulo simples.
	var portfolio_hud: Variant = world.get("hud")
	if portfolio_hud != null and portfolio_hud.get("cannon_label") != null:
		hud = portfolio_hud.cannon_label
	else:
		hud = Label.new()
		hud.position = Vector2(24,124)
		world.get_node("NavigationHUD").add_child(hud)

func fit(model: Node3D, size: float, axis: int, floor_fraction: float=0.0) -> AABB:
	var bounds: AABB = world._model_bounds(model)
	var factor := size/bounds.size[axis]
	model.scale = Vector3.ONE*factor
	model.position = -Vector3(bounds.get_center().x,bounds.position.y+bounds.size.y*floor_fraction,bounds.get_center().z)*factor
	return bounds

func _build_cannon() -> void:
	cannon = world.ship.float_visual.get_node_or_null("DeckCannon")
	if cannon == null:
		cannon = (load("res://Scenes/DeckCannon.tscn") as PackedScene).instantiate() as Node3D
		cannon.name = "DeckCannon"
		cannon.position = Vector3(-0.4, 0.204, 0.4)
		world.ship.float_visual.add_child(cannon)
	cannon_pitch = cannon.pitch_pivot
	barrel = cannon.barrel
	barrel_base = barrel.position
	muzzle = cannon.muzzle
	fuse_audio = cannon.fuse_audio
	shot_audio = cannon.shot_audio
	fuse_light = cannon.fuse_light
	_update_aim()

func _update_aim() -> void:
	cannon.set_target_pitch(aim_elevation)
	cannon.set_target_yaw(aim_azimuth)

## Regata do Time Attack: slalom de 20 boias em volta da ilha de spawn (IDs
## buoy_00..buoy_19, os mesmos do contrato do placar). Uma volta tem ~1,3 km,
## possível em 180 s mesmo com o globo de 800 m.
@export var course_island := 0
@export var course_count := 20
@export var course_radius_inner := 170.0
@export var course_radius_outer := 230.0
## Boias livres perto de cada ilha (distâncias da costa medida).
@export var island_buoy_distances: Array[float] = [25.0, 40.0, 55.0, 70.0]

func _build_targets() -> void:
	var center: Node3D = world.islands[clampi(course_island, 0, world.islands.size() - 1)]
	var center_normal := center.position.normalized()
	var center_basis := Scale.surface_basis(center_normal)
	for i in range(course_count):
		var angle := TAU * float(i) / float(course_count)
		var radius := course_radius_inner if i % 2 == 0 else course_radius_outer
		var tangent := center_basis.x * cos(angle) + center_basis.z * sin(angle)
		var direction := center_normal * cos(radius / OCEAN_RADIUS) + tangent * sin(radius / OCEAN_RADIUS)
		_add_target(direction, -2, "buoy_%02d" % i)
	for i in range(world.islands.size()):
		var island: Node3D = world.islands[i]
		for j in range(island_buoy_distances.size()):
			var a := j * TAU / float(island_buoy_distances.size()) + 0.4
			var tangent: Vector3 = island.basis * Vector3(cos(a), 0, sin(a))
			var normal := island.position.normalized()
			var direction := normal
			var desired: float = island_buoy_distances[j]
			# Walk outward until the requested distance from the measured coast is reached.
			for distance in range(8, 140):
				direction = normal * cos(distance / OCEAN_RADIUS) + tangent * sin(distance / OCEAN_RADIUS)
				if Shore.distance_to_coast(island, direction * OCEAN_RADIUS) >= desired: break
			_add_target(direction, i, "free_%d_%d" % [i, j])
	print("NAVAL_TARGETS total=", targets.size(), " course=", course_count)

func is_course_target(target: Dictionary) -> bool:
	return int(target.island) == -2

func course_targets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for target in targets:
		if is_course_target(target):
			result.append(target)
	return result

func _add_target(normal: Vector3, island_index: int, target_id: String) -> void:
	normal = normal.normalized()
	var body := Area3D.new()
	body.name = "NavalTarget_%02d"%targets.size()
	body.collision_layer = 4
	body.collision_mask = 0
	body.add_to_group("naval_target")
	body.set_meta("target_index",targets.size())
	body.set_meta("target_id",target_id)
	add_child(body)
	var visual := TARGET.instantiate() as Node3D
	body.add_child(visual)
	fit(visual,2.2,1,0.16)
	var shape := CylinderShape3D.new()
	shape.radius = 1.2
	shape.height = 2.0
	var collision := CollisionShape3D.new()
	collision.position.y = 0.75
	collision.shape = shape
	body.add_child(collision)
	var blocker := AnimatableBody3D.new()
	blocker.name = "BoatContact"
	blocker.sync_to_physics = false
	blocker.collision_layer = 8
	blocker.collision_mask = 2
	body.add_child(blocker)
	var boat_shape := CollisionShape3D.new()
	boat_shape.shape = shape
	boat_shape.position.y = 0.75
	blocker.add_child(boat_shape)
	targets.append({"id":target_id,"blocker":blocker,"drift":Vector3.ZERO,"anchor":normal,"node":body,"visual":visual,"normal":normal,"island":island_index,"hit_time":-10.0,"spin":rng.randf()*TAU,"active":true,"respawn_at":0.0})

func _build_particles() -> void:
	drop_mesh = SphereMesh.new()
	drop_mesh.radius = 0.045
	drop_mesh.height = 0.09
	drop_mesh.radial_segments = 6
	drop_mesh.rings = 3
	var water := StandardMaterial3D.new()
	water.albedo_color = Color("d1edf0")
	water.roughness = 0.65
	drop_mesh.material = water
	wood_mesh = BoxMesh.new()
	wood_mesh.size = Vector3(0.07,0.13,0.035)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("80502b")
	wood_mesh.material = wood

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_SPACE:
		fire()

func fire() -> bool:
	if cooldown>0.0 or fuse_remaining>0.0 or balls.size()>=8: return false
	fuse_remaining=fuse_duration
	fuse_light.visible=true
	fuse_audio.play()
	return true

func _launch() -> void:
	var visual := BALL.instantiate() as Node3D
	var node := Node3D.new()
	node.name = "Cannonball"
	node.add_to_group("cannonball")
	add_child(node)
	node.add_child(visual)
	fit(visual,0.22,0,0.5)
	node.global_position = muzzle.global_position
	var direction := (-muzzle.global_basis.z).normalized()
	var launch_velocity: Vector3 = direction*25.0+world.ship.velocity
	var flyby := AudioStreamPlayer3D.new()
	flyby.name = "CannonballDoppler"
	flyby.stream = DOPPLER_SFX
	flyby.volume_db = -13.0
	flyby.unit_size = 12.0
	flyby.max_distance = 85.0
	node.add_child(flyby)
	flyby.play()
	balls.append({"node":node,"velocity":launch_velocity,"age":0.0})
	cooldown = 1.0
	shots_fired += 1
	shot_audio.play()
	_emit_gun_smoke(direction)
	cannon.recoil()

func hit_target(index: int, point: Vector3) -> void:
	if index < 0 or index >= targets.size(): return
	var target := targets[index]
	if not target.active: return
	target.hit_time = elapsed
	target.respawn_at=elapsed+target_respawn_seconds
	_set_target_active(target, false)
	var hit_manager := get_node_or_null("/root/HitSoundManager")
	if hit_manager != null:
		hit_manager.call("play_hit", point)
	else:
		_play_impact("wood", point)
	score += 1
	if time_attack_running and is_course_target(target):
		time_attack_hits[index] = true
		time_attack_events.append({
			"target_id": target.id,
			"at_seconds": time_attack_duration - time_attack_remaining
		})
		if time_attack_hits.size() == course_count:
			_finish_time_attack(true)
	burst(point,true)
	world.ocean.touch(point)

func splash(point: Vector3) -> void:
	splash_count += 1
	_play_impact("splash",point)
	world.ocean.touch(point)
	burst(world.ocean.surface_at(point),false)
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.88
	mesh.outer_radius = 1.0
	mesh.rings = 24
	mesh.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("e1f1e8")
	mat.roughness = 1.0
	mesh.material = mat
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	rings.append({"node":node,"normal":point.normalized(),"age":0.0})

func burst(point: Vector3, wood: bool) -> void:
	var up := point.normalized()
	var tangent := up.cross(Vector3.RIGHT if absf(up.x)<0.9 else Vector3.UP).normalized()
	for i in range(12):
		var a := rng.randf()*TAU
		var velocity := up*rng.randf_range(1.4,3.8)+tangent.rotated(up,a)*rng.randf_range(0.5,2.4)
		add_drop(point+up*0.1,velocity,wood and i%2==0)

func add_drop(point: Vector3, velocity: Vector3, wood: bool=false) -> void:
	if debris.size()>=160: return
	var node := MeshInstance3D.new()
	if wood: node.mesh = wood_mesh
	else: node.mesh = drop_mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = point
	debris.append({"node":node,"velocity":velocity,"age":0.0})

func _physics_process(delta: float) -> void:
	elapsed += delta
	if time_attack_running:
		time_attack_remaining = maxf(0.0, time_attack_remaining - delta)
		if time_attack_remaining <= 0.0:
			_finish_time_attack(false)
	cooldown = maxf(0.0,cooldown-delta)
	if fuse_remaining>0.0:
		fuse_remaining=maxf(0.0,fuse_remaining-delta)
		fuse_light.light_energy=0.8+0.3*sin(elapsed*45.0)
		if fuse_remaining<=0.0:
			fuse_light.visible=false
			fuse_audio.stop()
			_launch()
	var pitch_axis := clampf(float(Input.is_physical_key_pressed(KEY_R)) - float(Input.is_physical_key_pressed(KEY_F)) + virtual_aim.y, -1.0, 1.0)
	# Só eixo vertical: o cano inclina nos munhões; não há giro horizontal.
	aim_elevation = clampf(aim_elevation + pitch_axis * delta * 0.5, deg_to_rad(float(cannon.get("min_pitch"))), deg_to_rad(float(cannon.get("max_pitch"))))
	aim_azimuth = 0.0
	_update_aim()
	for target in targets:
		var node: Node3D = target.node
		if not target.active:
			if time_attack_mode: continue
			if elapsed<float(target.respawn_at): continue
			_set_target_active(target, true)
		_push_target(target,delta)
		var home: Vector3=target.normal*OCEAN_RADIUS
		var up: Vector3 = target.normal
		var right := up.cross(Vector3.RIGHT if absf(up.x)<0.9 else Vector3.UP).normalized()
		var forward := up.cross(right)
		var impact := elapsed-float(target.hit_time)
		var kick := sin(impact*20.0)*exp(-impact*3.0) if impact<2.0 else 0.0
		# Fora do trecho de mar com ondas reais (patch), a água desenhada é lisa: a boia fica
		# nela e não precisa avaliar as ondas (era metade do tempo de física por quadro).
		var patch: Node3D = world.ocean_patch
		var flat := is_instance_valid(patch) and home.distance_to(patch.global_position) > float(patch.patch_radius) * 0.85
		var surface: Vector3 = home
		var wave_up := up
		if not flat:
			var field: Vector4=world.ocean.field_at(home)
			var point: Vector3=(home+Vector3(field.x,field.y,field.z)).normalized()*OCEAN_RADIUS
			var dx: Vector3 = world.ocean.surface_at(point+right*0.5)-world.ocean.surface_at(point-right*0.5)
			var dz: Vector3 = world.ocean.surface_at(point+forward*0.5)-world.ocean.surface_at(point-forward*0.5)
			wave_up = dx.cross(dz).normalized()
			if wave_up.dot(up)<0.0: wave_up=-wave_up
			surface = world.ocean.surface_at(point)
		node.position = surface+up*absf(kick)*0.15
		var front := forward.rotated(up,float(target.spin)+elapsed*0.10+0.20*sin(elapsed*0.6+float(target.spin))).slide(wave_up).normalized()
		node.basis = Basis(front.cross(wave_up),wave_up,-front).orthonormalized()
		node.rotate_object_local(Vector3.FORWARD,kick*0.35+sin(elapsed*1.2+float(target.spin))*0.035)
	for i in range(balls.size()-1,-1,-1):
		var ball := balls[i]
		var node: Node3D = ball.node
		var start := node.position
		ball.velocity -= start.normalized()*9.8*delta
		var end: Vector3 = start+ball.velocity*delta
		ball.age += delta
		var query := PhysicsRayQueryParameters3D.create(start,end,5)
		query.collide_with_areas = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		var remove := false
		if not hit.is_empty():
			if hit.collider.is_in_group("naval_target"): hit_target(int(hit.collider.get_meta("target_index")),hit.position)
			else:
				_play_impact("explosion",hit.position)
				burst(hit.position,true)
			remove = true
		elif end.length()<=OCEAN_RADIUS+float(world.ocean.height_at(end)):
			splash(end)
			remove = true
		elif ball.age>10.0: remove=true
		if remove:
			node.queue_free()
			balls.remove_at(i)
		else: node.position=end
	for i in range(debris.size()-1,-1,-1):
		var d := debris[i]
		var node: Node3D = d.node
		d.velocity -= node.position.normalized()*9.8*delta
		node.position += d.velocity*delta
		d.age += delta
		if d.age>1.5 or node.position.length()<OCEAN_RADIUS+float(world.ocean.height_at(node.position)):
			node.queue_free()
			debris.remove_at(i)
	for i in range(rings.size()-1,-1,-1):
		var ring := rings[i]
		ring.age += delta
		var node: MeshInstance3D = ring.node
		node.position = world.ocean.surface_at(ring.normal*OCEAN_RADIUS)+ring.normal*0.045
		var tangent: Vector3 = ring.normal.cross(Vector3.RIGHT if absf(ring.normal.x)<0.9 else Vector3.UP).normalized()
		node.basis = Basis(tangent,ring.normal,tangent.cross(ring.normal)).scaled(Vector3.ONE*(0.1+ring.age*1.7))
		node.transparency = clampf(ring.age/0.6,0.0,1.0)
		if ring.age>0.6:
			node.queue_free()
			rings.remove_at(i)

func _process(_delta: float) -> void:
	var state := "PAVIO %.1fs"%fuse_remaining if fuse_remaining>0.0 else ("RECARREGANDO" if cooldown>0.0 else "PRONTO")
	if time_attack_mode:
		var seconds := ceili(time_attack_remaining)
		var result := "EM CURSO" if time_attack_running else ("CONCLUÍDO" if time_attack_hits.size() == course_count else "TEMPO ESGOTADO")
		hud.text = ("%.0f° · %s" if DisplayServer.is_touchscreen_available() else "%.0f°  ·  desafio %s") % [rad_to_deg(aim_elevation), result.to_lower()]
	else:
		var compact := DisplayServer.is_touchscreen_available()
		hud.text = ("%.0f° · %d" if compact else "%.0f°  ·  %d acertos")%[rad_to_deg(aim_elevation),score]

func _play_impact(kind: String, point: Vector3) -> void:
	var sound:=AudioStreamPlayer3D.new()
	if kind == "splash":
		sound.stream = SPLASH_SFX
	elif kind == "wood":
		var wood_path := "res://Assets/Sound/SFX/WOOD IMPACT CANON BALL SFX.wav"
		sound.stream = load(wood_path) if ResourceLoader.exists(wood_path) else EXPLOSION_SFX
	else:
		sound.stream = EXPLOSION_SFX
	sound.unit_size=20.0
	sound.max_distance=100.0
	sound.volume_db=-5.0
	add_child(sound)
	sound.global_position=point
	sound.finished.connect(sound.queue_free)
	sound.play()

func _emit_gun_smoke(direction: Vector3) -> void:
	var smoke:=GPUParticles3D.new()
	smoke.name="CannonSmoke"
	smoke.amount=28
	smoke.lifetime=1.6
	smoke.one_shot=true
	smoke.explosiveness=1.0
	smoke.local_coords=false
	var process:=ParticleProcessMaterial.new()
	process.direction=Vector3.FORWARD
	process.spread=22.0
	process.initial_velocity_min=1.1
	process.initial_velocity_max=3.0
	process.gravity=muzzle.global_position.normalized()*0.45
	process.scale_min=0.4
	process.scale_max=1.3
	var gradient:=Gradient.new()
	gradient.set_color(0,Color(0.8,0.75,0.61,0.75))
	gradient.set_color(1,Color(0.65,0.69,0.72,0))
	var ramp:=GradientTexture1D.new()
	ramp.gradient=gradient
	process.color_ramp=ramp
	smoke.process_material=process
	var puff:=QuadMesh.new()
	puff.size=Vector2(0.65,0.65)
	var mat:=StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo=true
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode=BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var soft:=Gradient.new()
	soft.set_color(0,Color(1,1,1,0.45))
	soft.set_color(1,Color(1,1,1,0))
	var texture:=GradientTexture2D.new()
	texture.gradient=soft
	texture.fill=GradientTexture2D.FILL_RADIAL
	texture.fill_from=Vector2(0.5,0.5)
	texture.fill_to=Vector2(0.5,0.0)
	mat.albedo_texture=texture
	puff.material=mat
	smoke.draw_pass_1=puff
	add_child(smoke)
	smoke.global_position=muzzle.global_position
	smoke.global_basis=Basis.looking_at(direction,muzzle.global_position.normalized())
	smoke.finished.connect(smoke.queue_free)
	smoke.restart()

func _push_target(target: Dictionary, delta: float) -> void:
	var up: Vector3 = (target.normal as Vector3).normalized()
	target.normal = up
	var position_on_water: Vector3 = up*OCEAN_RADIUS
	var ship_position: Vector3 = world.ship.global_position
	var forward: Vector3 = world.ship.heading.slide(up).normalized()
	var predicted: Vector3 = ship_position+forward*world.ship.drive_speed*delta
	var along := clampf((position_on_water-predicted).dot(forward),-1.65,1.65)
	var separation := (position_on_water-predicted-forward*along).slide(up)
	var clearance := 1.85
	if separation.length()<clearance and position_on_water.distance_to(predicted)<5.0:
		var away := separation.normalized() if separation.length()>0.05 else forward.cross(up).normalized()
		position_on_water += away*(clearance-separation.length())
		target.drift = away*minf(absf(world.ship.drive_speed)*0.35+0.3,3.0)
	var drift: Vector3 = target.drift
	position_on_water += drift*delta
	var candidate := position_on_water.normalized()
	var safe := true
	for island in world.islands:
		if candidate.angle_to(island.position.normalized())*OCEAN_RADIUS<45.0 and Shore.distance_to_coast(island,candidate*OCEAN_RADIUS)<2.0:
			safe=false
			break
	if safe: target.normal=candidate
	target.drift=drift.slide(candidate)*exp(-1.6*delta)
