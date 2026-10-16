extends Node3D

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
var smoke_emitters: Array[GPUParticles3D] = []
var glows: Array[MeshInstance3D] = []
var beacon: MeshInstance3D
var panes: Array[MeshInstance3D] = []
var bonfire: GPUParticles3D
var lantern_materials: Array[ShaderMaterial] = []
var lantern_meshes: Array[MeshInstance3D] = []
var lantern_glass: MeshInstance3D
var snail_base := Vector3.ZERO
var lamp_head: MeshInstance3D
## Animações das ilhas feitas no Blender (Tools/animate_islands_blender.py): o GLB traz as peças que
## se mexem (Chimney, Cannon_N, Poneglyph, Palm_N, ChestLid, LanternRoom, SnailShell, Antenna_N…)
## e um AnimationPlayer; aqui só disparamos/repetimos. Cada animação ganha um player próprio para
## várias tocarem juntas (loop das palmeiras + baú, por exemplo).
var anim_players := {}
var chimney: Node3D
var chimney_puff: GPUParticles3D
var puff_timer := 3.0
var chests: Array[Dictionary] = []

## Barco do jogador (main_world.ship; o nó não se chama mais PlayerSloop).
func _player_ship() -> Node3D:
	var world := get_parent().get_parent().get_parent()
	return world.get("ship") as Node3D if world else null

func part_mesh(part_name: String) -> MeshInstance3D:
	return model.find_child(part_name, true, false) as MeshInstance3D

## Caixa da peça no espaço da ilha (os vértices já estão nele).
func part_box(part_name: String) -> AABB:
	var mesh := part_mesh(part_name)
	return model.global_transform.affine_inverse() * mesh.global_transform * mesh.mesh.get_aabb() if mesh else AABB()

## Player só desta animação (sem as faixas de repouso das outras peças que o glTF põe junto).
func island_anim(anim_name: String) -> AnimationPlayer:
	if anim_players.has(anim_name):
		return anim_players[anim_name]
	var source := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source == null or not source.has_animation(anim_name):
		return null
	var anim := source.get_animation(anim_name).duplicate() as Animation
	for t in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_key_count(t) <= 1:
			anim.remove_track(t)
	var library := AnimationLibrary.new()
	library.add_animation(anim_name, anim)
	var player := AnimationPlayer.new()
	player.name = "Anim_" + anim_name
	source.get_parent().add_child(player)
	player.root_node = player.get_path_to(source.get_node(source.root_node))
	player.add_animation_library("", library)
	anim_players[anim_name] = player
	return player

func play_loop(anim_name: String) -> void:
	var player := island_anim(anim_name)
	if player:
		player.play(anim_name)

## Ponto do espaço da ilha → espaço deste nó (onde ficam luzes e partículas).
func island_point(at: Vector3) -> Vector3:
	return to_local(model.global_transform * at)

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

## Luz de janela/ambiente: sem esfera visível (antes as bolinhas pareciam soltas no ar).
func window_light(where: Vector3, color: Color, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = where
	light.light_color = color
	light.omni_range = reach
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	add_child(light)
	lamps.append(light)
	return light

## Halo emissivo em billboard; some de dia. disable_fog para ser visto de longe.
func glow_sprite(where: Vector3, color: Color, size: float) -> MeshInstance3D:
	var sprite := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	sprite.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_fog = true
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	soft.add_point(0.25, Color(1, 1, 1, 0.75))
	var tex := GradientTexture2D.new()
	tex.gradient = soft
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	mat.albedo_texture = tex
	mat.albedo_color = color
	sprite.material_override = mat
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.position = where
	add_child(sprite)
	glows.append(sprite)
	return sprite

## Vidro de janela aceso: painel emissivo rente à parede + luz logo à frente.
func lit_pane(where: Vector3, outward: Vector3, size: Vector2, color: Color) -> void:
	var pane := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	pane.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.disable_fog = true
	pane.material_override = mat
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pane.position = where + outward * 0.04
	pane.basis = Basis.looking_at(-outward, Vector3.UP)
	add_child(pane)
	panes.append(pane)
	var light := OmniLight3D.new()
	light.position = where + outward * 0.7
	light.light_color = color
	light.omni_range = 3.5
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	add_child(light)
	lamps.append(light)

## Chama dentro da câmara de uma lanterna de pedra: miolo emissivo pequeno + luz curta, as duas lá
## dentro; só as aberturas da lanterna brilham. O miolo entra em `panes` (aparece só à noite).
func lantern_flame(where: Vector3) -> void:
	var core := MeshInstance3D.new()
	core.name = "LanternFlame"
	var ball := SphereMesh.new()
	ball.radius = 0.2
	ball.height = 0.4
	ball.radial_segments = 10
	ball.rings = 5
	core.mesh = ball
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.albedo_color = Color(1.0, 0.82, 0.45)
	hot.disable_fog = true
	core.material_override = hot
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.position = where
	add_child(core)
	panes.append(core)
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.position = where
	light.light_color = Color("ffb85c")
	light.omni_range = 1.3
	light.omni_attenuation = 1.0
	light.shadow_enabled = false
	add_child(light)
	lamps.append(light)

## Fogueira: chamas em partículas + luz forte que tremula.
func _build_bonfire(where: Vector3) -> void:
	var fire := GPUParticles3D.new()
	fire.name = "Bonfire"
	fire.position = where
	fire.amount = 26
	fire.lifetime = 0.9
	fire.local_coords = true
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.5
	motion.direction = Vector3.UP
	motion.spread = 15.0
	motion.initial_velocity_min = 1.2
	motion.initial_velocity_max = 2.2
	motion.gravity = Vector3.ZERO
	motion.scale_min = 0.6
	motion.scale_max = 1.2
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.1))
	var shrink_tex := CurveTexture.new()
	shrink_tex.curve = shrink
	motion.scale_curve = shrink_tex
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	ramp.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	motion.color_ramp = ramp_tex
	fire.process_material = motion
	var flame := QuadMesh.new()
	flame.size = Vector2(0.7, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = soft
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	mat.albedo_texture = tex
	flame.material = mat
	fire.draw_pass_1 = flame
	add_child(fire)
	bonfire = fire
	var light := OmniLight3D.new()
	light.name = "BonfireLight"
	light.position = where + Vector3.UP * 1.0
	light.light_color = Color("ff8a2a")
	light.omni_range = 14.0
	light.shadow_enabled = false
	add_child(light)
	lamps.append(light)

## Vidro da lanterna do farol pintado de branco fluorescente à noite (a luz parece sair dali).
func _paint_lantern_glass(center_local: Vector3) -> void:
	var world_center: Vector3 = (get_parent() as Node3D).global_transform * center_local
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var model_center: Vector3 = mesh.global_transform.affine_inverse() * world_center
		for surface in range(mesh.mesh.get_surface_count()):
			var original := mesh.get_active_material(surface) as StandardMaterial3D
			if original == null or original.albedo_texture == null:
				continue
			var glow := ShaderMaterial.new()
			glow.shader = load("res://Shaders/lantern_glow.gdshader")
			glow.set_shader_parameter("albedo_map", original.albedo_texture)
			glow.set_shader_parameter("tint", original.albedo_color)
			glow.set_shader_parameter("glow_center", model_center)
			glow.set_shader_parameter("glow_radius", 0.12)
			mesh.set_surface_override_material(surface, glow)
			lantern_materials.append(glow)
			lantern_meshes.append(mesh)

func _build_chimney_smoke(where: Vector3) -> void:
	var smoke := GPUParticles3D.new()
	smoke.name = "ChimneySmoke"
	smoke.position = where
	smoke.amount = 10
	smoke.lifetime = 4.0
	smoke.local_coords = false
	smoke.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 14, 12))
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 12.0
	motion.initial_velocity_min = 0.5
	motion.initial_velocity_max = 0.9
	motion.gravity = Vector3.ZERO
	motion.scale_min = 0.4
	motion.scale_max = 0.7
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.6))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	motion.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(0.85, 0.85, 0.85, 0.55))
	fade.set_color(1, Color(0.85, 0.85, 0.85, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	motion.color_ramp = ramp
	smoke.process_material = motion
	var puff := SphereMesh.new()
	puff.radius = 0.35
	puff.height = 0.7
	puff.radial_segments = 8
	puff.rings = 4
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = paint
	smoke.draw_pass_1 = puff
	add_child(smoke)
	smoke_emitters.append(smoke)

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	clock = get_node("/root/DayNightCycle")
	match index:
		0:
			# Medido por raycast na malha (Tests/island_probe.gd): vidros das janelas da casa.
			for w in [Vector3(0.345, 0.587, 0.262), Vector3(0.445, 0.596, 0.308), Vector3(0.498, 0.596, 0.309), Vector3(0.585, 0.357, 0.307), Vector3(0.641, 0.358, 0.309), Vector3(0.469, 0.781, 0.306)]:
				lit_pane(point(w.x, w.y, w.z), Vector3.BACK, Vector2(0.55, 0.6), Color("ffb85c"))
			for d in [Vector3(0.330, 0.354, 0.293), Vector3(0.466, 0.362, 0.310)]:
				lit_pane(point(d.x, d.y, d.z), Vector3.BACK, Vector2(0.8, 1.2), Color("ff9f45"))
			chimney = part_mesh("Chimney")
			if chimney:
				var box := part_box("Chimney")
				var top := island_point(box.get_center() + Vector3(0, box.size.y * 0.5, 0))
				_build_chimney_smoke(top)
				chimney_puff = _puff_emitter(top)
			else:
				_build_chimney_smoke(point(0.632, 0.775, 0.275))
		1:
			_build_fort_cannons()
			# Fogueira no pátio + uma luz em cada torre (medidos no topo da malha).
			_build_bonfire(point(0.488, 0.617, 0.488))
			for tower in [Vector3(0.247, 0.90, 0.243), Vector3(0.734, 0.90, 0.243), Vector3(0.246, 0.90, 0.721), Vector3(0.733, 0.90, 0.721)]:
				window_light(point(tower.x, tower.y, tower.z), Color("ffb050"), 5.0)
		2:
			_extract_cube()
			# Lanternas de pedra dos dois lados da escada: chama no miolo da câmara de cada uma (achado
			# varrendo a frente com raios de física: abertura vazada à altura da janela, atrás da moldura).
			for lantern in [Vector3(0.350, 0.477, 0.824), Vector3(0.621, 0.477, 0.824)]:
				lantern_flame(point(lantern.x, lantern.y, lantern.z))
			# Poneglyph flutua/gira e as palmeiras balançam: tudo no loop "idle" feito no Blender.
			play_loop("idle")
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
			# Único baú com tampa separada (ChestLid, animação chest_open); palmeiras no loop "idle".
			_build_chest_lid()
			play_loop("idle")
			# Brilho do ouro logo acima de cada baú.
			for chest in [Vector3(0.290, 0.30, 0.712), Vector3(0.742, 0.27, 0.686)]:
				window_light(point(chest.x, chest.y, chest.z), Color("ffcc40"), 4.0)
				glow_sprite(point(chest.x, chest.y + 0.02, chest.z), Color(1.0, 0.8, 0.3), 1.4)
		4:
			# Concha do Den Den Mushi (shell_ring quando toca), antenas e sala da lanterna (loop "idle").
			snail = part_mesh("SnailShell")
			var room := part_box("LanternRoom")
			play_loop("idle")
			lantern_pivot = Node3D.new()
			lantern_pivot.position = island_point(room.get_center())
			add_child(lantern_pivot)
			beam = SpotLight3D.new()
			beam.spot_range = 600.0
			beam.distance_fade_enabled = false
			beam.spot_angle = 15.0
			beam.light_color = Color("fff4b8")
			beam.shadow_enabled = false
			lantern_pivot.add_child(beam)
			# Alcance curto: a luz de 9 m atravessava os polígonos do Den Den Mushi logo acima.
			var glow := window_light(lantern_pivot.position, Color("fff4b8"), 2.2)
			glow.name = "LanternInteriorGlow"
			# Lanterna acesa por dentro: núcleo emissivo que aparece de longe (sem névoa).
			lantern_glass = MeshInstance3D.new()
			var core := SphereMesh.new()
			core.radius = 0.3
			core.height = 0.6
			lantern_glass.mesh = core
			var hot := StandardMaterial3D.new()
			hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			hot.albedo_color = Color(1.0, 0.95, 0.7)
			hot.disable_fog = true
			lantern_glass.material_override = hot
			lantern_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lantern_glass.position = lantern_pivot.position
			add_child(lantern_glass)
			beacon = glow_sprite(lantern_pivot.position, Color(1.0, 0.92, 0.65), 2.6)
			# O topo do farol fica parado: quem gira é a lâmpada lá dentro, junto com o facho.
			lamp_head = MeshInstance3D.new()
			lamp_head.name = "LampHead"
			var lens := BoxMesh.new()
			lens.size = Vector3(0.7, 0.5, 0.14)
			lamp_head.mesh = lens
			var bright := StandardMaterial3D.new()
			bright.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bright.albedo_color = Color(1.0, 0.97, 0.8)
			bright.disable_fog = true
			lamp_head.material_override = bright
			lamp_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lamp_head.position = Vector3(0, 0, -0.45)
			lantern_pivot.add_child(lamp_head)
			_paint_lantern_glass(model.transform * room.get_center())
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
	var in_view := camera and camera.global_position.distance_to(global_position) < 260.0
	
	for i in range(lamps.size()):
		var light := lamps[i]
		# No celular só as luzes da ilha bem próxima ficam ligadas (cada luz custa caro no WebGL).
		var view_ok: bool = nearby if OS.has_feature("mobile_lite") else in_view
		light.visible = (view_ok or light.name == "LanternInteriorGlow") and (night > 0.05 or index == 2)
		var flicker := 1.0 + 0.10 * sin(elapsed * 8.1 + i * 2.0) + 0.05 * sin(elapsed * 13.7)
		var strength := 6.0 if light.name == "BonfireLight" else 2.6
		light.light_energy = (lerpf(0.35, 3.2, night) if index == 2 and light.name != "LanternLight" else night * strength) * flicker + flash
	
	if chimney:
		puff_timer -= delta
		if puff_timer <= 0.0 and in_view:
			puff_timer = randf_range(2.6, 4.2)
			island_anim("chimney_puff").stop()
			island_anim("chimney_puff").play("chimney_puff")
			# A baforada sai no fim do squash (quadro 4 de 24 fps no Blender).
			get_tree().create_timer(0.17).timeout.connect(chimney_puff.restart)
		(chimney_puff.process_material as ParticleProcessMaterial).gravity = global_position.normalized() * 0.25
	if not chests.is_empty():
		var sloop := _player_ship()
		# Abre com o barco chegando perto ou com a câmera de visita (Carta) rodando a ilha.
		var near_chest: bool = (sloop != null and sloop.global_position.distance_to(global_position) < 60.0) or (camera != null and camera.global_position.distance_to(global_position) < 45.0)
		for chest in chests:
			_update_chest(chest, near_chest)
	if cube:
		for mat in cube_materials:
			mat.set_shader_parameter("glow", lerpf(0.35, 2.0, night) * (0.85 + 0.15 * sin(elapsed * 3.0)))
	
	if index == 1 and in_view:
		cannon_timer -= delta
		if cannon_timer <= 0.0 and not decorative_cannons.is_empty():
			cannon_timer = cannon_rng.randf_range(4.0, 8.0)
			_fire_cannon(decorative_cannons[cannon_rng.randi_range(0, decorative_cannons.size() - 1)])
	
	if snail:
		var boat := _player_ship()
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
			var ring_anim := island_anim("shell_ring")
			if ring_anim:
				ring_anim.stop()
				ring_anim.play("shell_ring")
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
		if lamp_head:
			# De dia a lâmpada aparece apagada (amarelada); à noite acende forte.
			(lamp_head.material_override as StandardMaterial3D).albedo_color = Color(0.85, 0.8, 0.6).lerp(Color(1.0, 0.97, 0.8) * 1.8, night)
		if lantern_glass:
			lantern_glass.visible = night > 0.05
			(lantern_glass.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.95, 0.7) * lerpf(0.6, 1.6, night)
	for pane in panes:
		pane.visible = night > 0.08
		(pane.material_override as StandardMaterial3D).albedo_color.a = 1.0
	if bonfire:
		bonfire.emitting = night > 0.05 and in_view
	var beam_world: Vector3 = -lantern_pivot.global_basis.z if lantern_pivot else Vector3.FORWARD
	for i in lantern_materials.size():
		var mat := lantern_materials[i]
		mat.set_shader_parameter("night", night)
		mat.set_shader_parameter("beam_dir", lantern_meshes[i].global_basis.inverse() * beam_world)
	for glow in glows:
		glow.visible = night > 0.08
		var mat := glow.material_override as StandardMaterial3D
		var pulse := 0.9 + 0.1 * sin(elapsed * 2.3 + glow.position.x)
		mat.albedo_color.a = night * pulse * (0.95 if glow == beacon else 0.8)
	for smoke in smoke_emitters:
		smoke.emitting = in_view
		(smoke.process_material as ParticleProcessMaterial).gravity = global_position.normalized() * 0.15
	flash = move_toward(flash, 0.0, delta * 5.0)

func open_chest() -> void:
	flash = 5.0

func _extract_cube() -> void:
	var stone := part_mesh("Poneglyph")
	if stone:
		cube = stone
		var glow := ShaderMaterial.new()
		glow.shader = load("res://Shaders/runes.gdshader")
		glow.set_shader_parameter("albedo_map", (stone.get_active_material(0) as StandardMaterial3D).albedo_texture)
		stone.material_override = glow
		cube_materials.append(glow)
		return
	for instance in model.find_children("*", "MeshInstance3D", true, false):
		var original: Mesh = instance.mesh
		for surface in range(original.get_surface_count()):
			var material: Material = instance.get_active_material(surface)
			if not material is StandardMaterial3D or not material.albedo_texture: continue
			var arrays := original.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			# Começa acima do chão do pedestal: o chão fica inteiro, só o cubo levita.
			var region := AABB(Vector3(-0.196, 0.085, -0.234), Vector3(0.37, 0.342, 0.36))
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
			instance.mesh = base_mesh
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
	var center := part_box("Island").get_center()
	for i in 8:
		var part := part_mesh("Cannon_%d" % i)
		if not part: continue
		var box := part_box(part.name)
		# Os canhões apontam para fora do forte: o coice é para dentro.
		var out := Vector3(box.get_center().x - center.x, 0.0, box.get_center().z - center.z).normalized()
		var muzzle := island_point(box.get_center() + out * box.size.length() * 0.45)
		var aim := (muzzle - island_point(box.get_center())).normalized()
		var smoke := GPUParticles3D.new()
		smoke.position = muzzle
		smoke.basis = Basis.looking_at(-aim, Vector3.UP)
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
		decorative_cannons.append({"anim": "cannon_fire_%d" % i, "smoke": smoke, "sound": sound})

## Tiro decorativo: coice + squash & stretch (animação do Blender), fumaça e som.
func _fire_cannon(cannon: Dictionary) -> void:
	var player := island_anim(cannon.anim)
	if player:
		player.stop()
		player.play(cannon.anim)
	cannon.smoke.restart()
	cannon.sound.play()

## Baforada da chaminé: 3 bolas maiores de uma vez, além da fumaça contínua.
func _puff_emitter(where: Vector3) -> GPUParticles3D:
	var puff := GPUParticles3D.new()
	puff.name = "ChimneyPuff"
	puff.position = where
	puff.amount = 3
	puff.lifetime = 2.6
	puff.one_shot = true
	puff.explosiveness = 0.85
	puff.emitting = false
	puff.local_coords = false
	puff.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 14, 12))
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 18.0
	motion.initial_velocity_min = 1.1
	motion.initial_velocity_max = 1.6
	motion.damping_min = 0.6
	motion.damping_max = 0.9
	motion.scale_min = 0.7
	motion.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(0.15, 1.0))
	grow.add_point(Vector2(1, 1.8))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	motion.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(0.92, 0.92, 0.92, 0.75))
	fade.set_color(1, Color(0.85, 0.85, 0.88, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	motion.color_ramp = ramp
	puff.process_material = motion
	var ball := SphereMesh.new()
	ball.radius = 0.4
	ball.height = 0.8
	ball.radial_segments = 8
	ball.rings = 4
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material = paint
	puff.draw_pass_1 = ball
	add_child(puff)
	return puff

## Tampa do baú (animação chest_open do Blender: começa fechada e abre); toca ao contrário para fechar.
func _build_chest_lid() -> void:
	var lid := part_mesh("ChestLid")
	var player := island_anim("chest_open")
	if lid == null or player == null:
		return
	player.play("chest_open")
	player.seek(0.0, true)
	player.pause()
	var box := part_box("ChestLid")
	var burst := _gold_burst(island_point(box.get_center()))
	chests.append({"player": player, "open": false, "burst": burst})

func _update_chest(chest: Dictionary, near: bool) -> void:
	if near == chest.open:
		return
	chest.open = near
	var player: AnimationPlayer = chest.player
	if near:
		player.play("chest_open")
		chest.burst.restart()
		flash = 3.0
	else:
		player.play_backwards("chest_open")

func _gold_burst(where: Vector3) -> GPUParticles3D:
	var burst := GPUParticles3D.new()
	burst.name = "GoldBurst"
	burst.position = where
	burst.amount = 40
	burst.lifetime = 1.6
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.emitting = false
	burst.local_coords = true
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 35.0
	motion.initial_velocity_min = 2.5
	motion.initial_velocity_max = 4.5
	motion.gravity = Vector3(0, -6.0, 0)
	motion.angular_velocity_min = -360.0
	motion.angular_velocity_max = 360.0
	motion.scale_min = 0.7
	motion.scale_max = 1.3
	burst.process_material = motion
	var coin := CylinderMesh.new()
	coin.top_radius = 0.09
	coin.bottom_radius = 0.09
	coin.height = 0.025
	coin.radial_segments = 10
	coin.rings = 1
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("ffd74d")
	paint.metallic = 0.9
	paint.roughness = 0.25
	paint.emission_enabled = true
	paint.emission = Color("ffb820")
	paint.emission_energy_multiplier = 0.6
	coin.material = paint
	burst.draw_pass_1 = coin
	add_child(burst)
	return burst

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
	for mesh in model.find_children("Island", "MeshInstance3D", true, false):
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
