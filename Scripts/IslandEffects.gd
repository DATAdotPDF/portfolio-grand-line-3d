extends Node3D

const Parts = preload("res://Scripts/MeshParts.gd")

var decorative_cannons: Array[Dictionary] = []
var cannon_timer := 8.0
var cannon_rng := RandomNumberGenerator.new()
var snail: Node3D
var treasure_materials: Array[ShaderMaterial] = []
var treasure_sparks: Array[GPUParticles3D] = []
var index := 0
var model: Node3D
var bounds: AABB
var factor := 1.0
var clock: Node
var lamps: Array[OmniLight3D] = []
var lantern_pivot: Node3D
var beam: SpotLight3D
var beam_cone: MeshInstance3D
var cube: Node3D
var cube_base := Vector3.ZERO
var cube_materials: Array[ShaderMaterial] = []
var particles: GPUParticles3D
var elapsed := 0.0
var flash := 0.0
var snail_audio: AudioStreamPlayer3D
var ring_timer := 0.0
var signal_rings: Array[MeshInstance3D] = []

func point(x: float, y: float, z: float) -> Vector3:
	return (bounds.position + bounds.size * Vector3(x, y, z)) * factor + model.position

func lamp(where: Vector3, color: Color, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = where
	light.light_color = color
	light.omni_range = reach
	light.shadow_enabled = false
	add_child(light)
	lamps.append(light)
	var glass := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	glass.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	glass.material_override = material
	light.add_child(glass)
	return light

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	clock = get_node("/root/DayNightCycle")
	match index:
		0:
			pass # Luzes genéricas removidas: ficavam soltas (até sob o píer), sem lanterna no modelo.
		1:
			_build_fort_cannons()
		2:
			_extract_cube()
			var glow := lamp(point(0.5, 0.60, 0.50), Color("00f0ff"), 7.0)
			if cube: glow.global_position = cube.global_position
			particles = GPUParticles3D.new()
			particles.amount = 18
			particles.lifetime = 2.5
			particles.local_coords = true
			particles.position = glow.position
			var process := ParticleProcessMaterial.new()
			process.direction = Vector3.UP
			process.initial_velocity_min = 0.15
			process.initial_velocity_max = 0.45
			process.gravity = Vector3(0, 0.1, 0)
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			process.emission_sphere_radius = 1.2
			particles.process_material = process
			var mote := SphereMesh.new()
			mote.radius = 0.035
			mote.height = 0.07
			mote.radial_segments = 6
			mote.rings = 3
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("00d5e8")
			material.emission_enabled = true
			material.emission = Color("00d5e8")
			mote.material = material
			particles.draw_pass_1 = mote
			add_child(particles)
		3:
			_build_treasure()
		4:
			snail = Parts.extract(model, AABB(Vector3(-0.1, 0.64, -0.50), Vector3(0.58, 0.34, 0.65)), "DenDenMushi")
			lantern_pivot = Node3D.new()
			lantern_pivot.position = Vector3(0.1815, 0.52, -0.204) * factor + model.position
			add_child(lantern_pivot)
			beam = SpotLight3D.new()
			beam.spot_range = 600.0
			beam.distance_fade_enabled = false
			beam.spot_angle = 15.0
			beam.light_color = Color("fff4b8")
			beam.shadow_enabled = false
			lantern_pivot.add_child(beam)
			var glow := lamp(lantern_pivot.position, Color("fff4b8"), 4.0)
			glow.name = "LanternInteriorGlow"
			beam_cone = MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.08
			cone.bottom_radius = 32.0
			cone.height = 140.0
			cone.radial_segments = 24
			cone.cap_top = false
			cone.cap_bottom = false
			beam_cone.mesh = cone
			beam_cone.rotation.x = PI * 0.5
			beam_cone.position.z = -70.0
			beam_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := ShaderMaterial.new()
			mat.shader = load("res://Shaders/beam.gdshader")
			beam_cone.material_override = mat
			lantern_pivot.add_child(beam_cone)
	if snail: _build_snail_signal()
	if index in [0, 2, 4]: _animate_foliage()

func _process(delta: float) -> void:
	elapsed += delta
	var night: float = clock.night_at(global_position)
	var camera := get_viewport().get_camera_3d()
	var nearby := camera and camera.global_position.distance_to(global_position) < 85.0
	
	for i in range(lamps.size()):
		var light := lamps[i]
		light.visible = (nearby or light.name == "LanternInteriorGlow") and (night > 0.05 or index == 2)
		var flicker := 1.0 + 0.10 * sin(elapsed * 8.1 + i * 2.0) + 0.05 * sin(elapsed * 13.7)
		light.light_energy = (lerpf(0.35, 3.2, night) if index == 2 else night * 2.0) * flicker + flash
	
	if cube:
		cube.position = cube_base + Vector3.UP * (sin(elapsed * 1.5) * 0.12 / factor)
		cube.rotate_y(deg_to_rad(6.0) * delta)
		for mat in cube_materials:
			mat.set_shader_parameter("glow", lerpf(0.35, 2.0, night) * (0.85 + 0.15 * sin(elapsed * 3.0)))
	
	if index == 1 and nearby:
		cannon_timer -= delta
		if cannon_timer <= 0.0 and not decorative_cannons.is_empty():
			cannon_timer = cannon_rng.randf_range(8.0, 16.0)
			var cannon: Dictionary = decorative_cannons[cannon_rng.randi_range(0, decorative_cannons.size() - 1)]
			var recoil := create_tween()
			recoil.tween_property(cannon.node, "position:z", cannon.base_z - 0.16 / factor, 0.09)
			recoil.tween_property(cannon.node, "position:z", cannon.base_z, 0.65)
			cannon.smoke.restart()
			cannon.sound.play()
	
	if snail:
		var boat := get_parent().get_parent().get_parent().get_node_or_null("PlayerSloop")
		var ringing: bool = boat != null and boat.global_position.distance_to(global_position) < 40.0
		if camera and camera.global_position.distance_to(snail.global_position) < 85.0:
			var cursor := get_viewport().get_mouse_position()
			var ray_origin := camera.project_ray_origin(cursor)
			var ray_dir := camera.project_ray_normal(cursor)
			var offset := snail.global_position - ray_origin
			ringing = ringing or (offset.dot(ray_dir) > 0.0 and offset.cross(ray_dir).length() < 1.6)
		ring_timer -= delta
		if ringing and ring_timer <= 0.0:
			ring_timer = 4.5
			snail_audio.play()
		for i in range(signal_rings.size()):
			var phase := (4.5 - ring_timer - float(i) * 0.2) / 1.2
			var ring := signal_rings[i]
			ring.visible = phase > 0.0 and phase < 1.0
			if ring.visible:
				ring.global_position = snail.global_position
				ring.scale = Vector3.ONE * (0.3 + phase * 2.6)
				var ring_mat := ring.material_override as StandardMaterial3D
				if ring_mat:
					var color := ring_mat.albedo_color
					color.a = (1.0 - phase) * 0.5
					ring_mat.albedo_color = color
		snail.rotation.z = sin(elapsed * 26.0) * 0.028 if ringing else sin(elapsed * 0.8) * 0.009
	
	for mat in treasure_materials:
		mat.set_shader_parameter("night", night)
	for sparks in treasure_sparks:
		sparks.emitting = nearby
	if particles:
		particles.emitting = nearby
	if beam:
		lantern_pivot.rotate_y(deg_to_rad(18.0) * delta)
		beam.light_energy = lerpf(beam.light_energy, 8.0 * night, 1.0 - exp(-2.0 * delta))
		beam.visible = beam.light_energy > 0.1
		beam_cone.visible = beam.visible
		beam_cone.material_override.set_shader_parameter("energy", night)
	flash = move_toward(flash, 0.0, delta * 5.0)

func open_chest() -> void:
	flash = 5.0

func _extract_cube() -> void:
	for instance in model.find_children("*", "MeshInstance3D", true, false):
		var original: Mesh = instance.mesh
		for surface in range(original.get_surface_count()):
			var material: Material = instance.get_active_material(surface)
			if not material is StandardMaterial3D or not material.albedo_texture: continue
			var arrays := original.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var region := AABB(Vector3(-0.196, 0.034, -0.234), Vector3(0.37, 0.393, 0.36))
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var chosen := PackedInt32Array()
			var kept := PackedInt32Array()
			for i in range(0, indices.size(), 3):
				var center := (vertices[indices[i]] + vertices[indices[i + 1]] + vertices[indices[i + 2]]) / 3.0
				var triangle := PackedInt32Array([indices[i], indices[i + 1], indices[i + 2]])
				if region.has_point(center): chosen.append_array(triangle)
				else: kept.append_array(triangle)
			if chosen.size() < 30: continue
			var base_arrays := arrays.duplicate(true)
			base_arrays[Mesh.ARRAY_INDEX] = kept
			var base_mesh := ArrayMesh.new()
			base_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base_arrays)
			base_mesh.surface_set_material(0, material)
			var base_lod := ImporterMesh.from_mesh(base_mesh)
			base_lod.generate_lods(60.0, 0.0, [])
			instance.mesh = base_lod.get_mesh()
			cube = Node3D.new()
			cube.name = "PoneglyphContainer"
			cube.position = region.get_center()
			cube.position.y += 0.20 / factor
			cube_base = cube.position
			instance.add_child(cube)
			var moved := vertices.duplicate()
			for i in range(moved.size()): moved[i] -= cube.position
			arrays[Mesh.ARRAY_VERTEX] = moved
			arrays[Mesh.ARRAY_INDEX] = chosen
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var floating := MeshInstance3D.new()
			floating.mesh = mesh
			var glow := ShaderMaterial.new()
			glow.shader = load("res://Shaders/runes.gdshader")
			glow.set_shader_parameter("albedo_map", material.albedo_texture)
			floating.material_override = glow
			cube_materials.append(glow)
			cube.add_child(floating)
			print("PONEGLYPH_EXTRACTED triangles=", int(chosen.size() / 3.0), " bounds=", region)
			return
	push_warning("Poneglyph extraction mask needs review; island mesh preserved")

func _build_treasure() -> void:
	for instance in model.find_children("*", "MeshInstance3D", true, false):
		for surface in range(instance.mesh.get_surface_count()):
			var original: Material = instance.get_active_material(surface)
			if original is StandardMaterial3D and original.albedo_texture:
				var mat := ShaderMaterial.new()
				mat.shader = load("res://Shaders/treasure.gdshader")
				mat.set_shader_parameter("albedo_map", original.albedo_texture)
				instance.set_surface_override_material(surface, mat)
				treasure_materials.append(mat)
	for position_on_island in [point(0.28, 0.26, 0.77), point(0.74, 0.26, 0.76)]:
		var sparks := GPUParticles3D.new()
		sparks.position = position_on_island
		sparks.amount = 12
		sparks.lifetime = 2.0
		sparks.local_coords = true
		var motion := ParticleProcessMaterial.new()
		motion.direction = Vector3.UP
		motion.spread = 20.0
		motion.initial_velocity_min = 0.15
		motion.initial_velocity_max = 0.45
		motion.gravity = Vector3(0, 0.04, 0)
		motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		motion.emission_box_extents = Vector3(0.45, 0.1, 0.3)
		sparks.process_material = motion
		var mote := SphereMesh.new()
		mote.radius = 0.025
		mote.height = 0.05
		mote.radial_segments = 6
		mote.rings = 3
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color("ffd74d")
		paint.emission_enabled = true
		paint.emission = Color("ffc638")
		mote.material = paint
		sparks.draw_pass_1 = mote
		add_child(sparks)
		treasure_sparks.append(sparks)

func _build_fort_cannons() -> void:
	cannon_rng.seed = 2002
	for x in [-0.59, 0.14]:
		var region := AABB(Vector3(x, 0.135, 0.54), Vector3(0.30, 0.20, 0.29))
		var part := Parts.extract(model, region, "FortCannon")
		if not part: continue
		var smoke := GPUParticles3D.new()
		smoke.position = region.get_center() * factor + model.position + Vector3(0, 0, 1.3)
		smoke.amount = 14
		smoke.lifetime = 1.7
		smoke.one_shot = true
		smoke.explosiveness = 1.0
		smoke.emitting = false
		smoke.local_coords = true
		var motion := ParticleProcessMaterial.new()
		motion.direction = Vector3(0, 0.3, 1)
		motion.spread = 25.0
		motion.initial_velocity_min = 0.5
		motion.initial_velocity_max = 1.7
		motion.gravity = Vector3(0, 0.2, 0)
		motion.scale_min = 0.3
		motion.scale_max = 1.0
		var fade := Gradient.new()
		fade.set_color(0, Color(0.6, 0.64, 0.65, 0.5))
		fade.set_color(1, Color(0.6, 0.64, 0.65, 0))
		var ramp := GradientTexture1D.new()
		ramp.gradient = fade
		motion.color_ramp = ramp
		smoke.process_material = motion
		var puff := SphereMesh.new()
		puff.radius = 0.25
		puff.height = 0.5
		puff.radial_segments = 8
		puff.rings = 4
		var paint := StandardMaterial3D.new()
		paint.vertex_color_use_as_albedo = true
		paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		paint.roughness = 1.0
		puff.material = paint
		smoke.draw_pass_1 = puff
		add_child(smoke)
		var sound := AudioStreamPlayer3D.new()
		sound.position = smoke.position
		sound.max_distance = 75.0
		sound.unit_size = 15.0
		sound.volume_db = -24.0
		sound.stream = _cannon_sound()
		add_child(sound)
		decorative_cannons.append({"node": part, "base_z": part.position.z, "smoke": smoke, "sound": sound})

func _cannon_sound() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(22050)
	for i in range(11025):
		var time := i / 22050.0
		var boom := sin(TAU * (75.0 * time - 25.0 * time * time)) * exp(-time * 12.0)
		var crack := cannon_rng.randf_range(-1, 1) * exp(-time * 35.0)
		samples.encode_s16(i * 2, int(clampf(boom * 0.5 + crack * 0.35, -1, 1) * 24000.0))
	stream.data = samples
	return stream

func _build_snail_signal() -> void:
	snail_audio = AudioStreamPlayer3D.new()
	snail_audio.name = "SnailTelephoneTrill"
	snail_audio.stream = _telephone_trill()
	snail_audio.max_distance = 55.0
	snail_audio.unit_size = 8.0
	snail_audio.volume_db = -17.0
	add_child(snail_audio)
	snail_audio.global_position = snail.global_position
	for i in range(3):
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.94
		mesh.outer_radius = 1.0
		mesh.rings = 32
		mesh.ring_segments = 4
		ring.mesh = mesh
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.75, 0.25, 0.0)
		ring.material_override = mat
		add_child(ring)
		ring.visible = false
		signal_rings.append(ring)

func _telephone_trill() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(44100)
	for i in range(22050):
		var t := i / 22050.0
		var envelope := sin(PI * clampf(fmod(t, 0.5) / 0.35, 0.0, 1.0))
		var tone := sin(TAU * 1100.0 * t + 2.0 * sin(TAU * 23.0 * t)) * 0.25
		data.encode_s16(i * 2, int(tone * envelope * 24000.0))
	stream.data = data
	return stream

func _animate_foliage() -> void:
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			var original: Material = mesh.get_active_material(surface)
			if not original is StandardMaterial3D or not original.albedo_texture: continue
			var mat := ShaderMaterial.new()
			mat.shader = load("res://Shaders/foliage_wind.gdshader")
			mat.set_shader_parameter("albedo_map", original.albedo_texture)
			mat.set_shader_parameter("tint", original.albedo_color)
			mat.set_shader_parameter("root_height", bounds.position.y + bounds.size.y * 0.3)
			mat.set_shader_parameter("tree_height", maxf(bounds.size.y * 0.7, 0.1))
			mesh.set_surface_override_material(surface, mat)
