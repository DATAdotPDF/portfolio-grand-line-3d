extends Node3D

## Ciclone do mar (gerenciado por Weather.gd). Ideia estudada no Wind Waker, feita do zero:
## - malha bem simples gerada aqui: perfil de "taça" (base larga, cintura fina, boca aberta),
##   em DUAS cascas quase coincidentes; o volume vem das faixas de ruído girando em ritmos
##   diferentes em cada casca (cyclone_funnel.gdshader), não de geometria;
## - o eixo serpenteia por uma onda helicoidal que sobe pelo funil; a conta está em
##   axis_offset() e no shader, com o mesmo relógio, para a física seguir o desenho;
## - redemoinho de espuma no mar abraçando a base (cyclone_swirl.gdshader);
## - quem move o ciclone é o Weather.gd (só por mar aberto, como as tempestades).
## Forma e pintura revistas pelo estudo do Thiago Muniz: eixo em "S", base fina com saia na água,
## boca larga que vira um disco chato fundido a um vórtice de nuvem no topo, duas cores em
## limiar (toon), raios dentro e um ciclo de ~30 s em que o funil expande e recolhe.

const FUNNEL := preload("res://Shaders/cyclone_funnel.gdshader")
## Cascas em cone (guia do Pedro: 3 cones concêntricos com ruído rolando + limiar + fresnel).
const LAYER := preload("res://Shaders/tornado_layer.gdshader")
## Faixas largas em hélice (estudo do vídeo do Wind Waker; desenho procedural nosso).
const BAND := preload("res://Shaders/tornado_band.gdshader")
## Perfil de "taça" (raio a cada 10% da altura): base larga, cintura fina e longa, boca que abre
## quase plana. Proporções medidas no estudo (References/WW_Study/notes/tornado.md, fora do git).
const PROFILE := [23.8, 15.4, 10.6, 9.9, 9.5, 9.1, 9.8, 12.1, 19.6, 28.0, 51.9]
const SWIRL := preload("res://Shaders/cyclone_swirl.gdshader")
const VORTEX := preload("res://Shaders/toon_vortex.gdshader")
const TORNADO_WIND := preload("res://Shaders/tornado_wind.gdshader")
const ROAR := preload("res://Assets/Sound/SFX/Cuts/cyclone_roar_loop.ogg")
# Texturas grátis do tutorial "GODOT 3D VFX - Tornado Effect" (Le Lu).
const WIND_TEX := preload("res://Assets/Tornado Textures/T_VFX_WindNoise1.png")
const STREAK_TEX := preload("res://Assets/Tornado Textures/T_FirePanningCyl45.png")
const NOISE_TEX := preload("res://Assets/Tornado Textures/T_Noise1_nk.png")
const CELLS_TEX := preload("res://Assets/Tornado Textures/T_Noise_HU85k.png")

@export var height := 95.0
## Escala do perfil (0,55 → cintura ~5 m, base ~13 m, boca ~28 m).
@export var radius_scale := 0.55
## Raio da boca (nuvens e anel de nuvem usam).
var top_flare: float:
	get: return PROFILE[10] * radius_scale
@export var sway_amount := 3.2
## Curva em "S" do eixo (metros no meio do funil).
@export var s_curve := 9.0
## Ciclo de vida: expande e recolhe a cada lifecycle_seconds.
@export var lifecycle_seconds := 30.0
@export var swirl_radius := 30.0
@export var segments := 32
@export var rings := 22

var weather: Node
var planet_radius := 800.0
var center := Vector3.UP
## Barco preso no ciclone (CycloneRide): o ciclone para de andar.
var captured := false
var sway_time := 0.0
var grow := 1.0
var funnel_materials: Array[ShaderMaterial] = []
var swirl_material: ShaderMaterial
var cloud: MeshInstance3D
var cloud_material: ShaderMaterial
## Anel fino de nuvem logo abaixo da tempestade (gira na velocidade do furacão).
var ring: MeshInstance3D
var ring_material: ShaderMaterial
var ribbons: Node3D
var gusts: Array[Dictionary] = []
## Nós de cada parte (para o teste mostrar camada por camada): núcleo, meio, fora.
var layer_nodes: Array[Node3D] = []
var splash: GPUParticles3D
## grow de fora (chegada/mini ciclone); o funil ainda "respira" por cima disso.
var breath := 1.0
var rng := RandomNumberGenerator.new()

func setup(home_direction: Vector3, seed_value: int) -> void:
	center = home_direction.normalized()
	rng.seed = seed_value

func _ready() -> void:
	_build_funnel()
	_build_swirl()
	_build_cloud()
	# Rugido em loop (som sintetizado nosso), ouvido de ~120 m.
	var roar := AudioStreamPlayer3D.new()
	roar.name = "Roar"
	roar.stream = ROAR
	roar.unit_size = 25.0
	roar.max_distance = 140.0
	roar.volume_db = -2.0
	roar.position = Vector3(0.0, 8.0, 0.0)
	roar.autoplay = true
	add_child(roar)
	_place()

## Raio da casca de fora na altura relativa h (0 = mar, 1 = topo): perfil de taça interpolado
## (Catmull-Rom); a boca respira com o ciclo de vida.
func radius_at(h: float) -> float:
	return profile_at(h) * radius_scale * (1.0 + 0.12 * (breath - 0.5) * smoothstep(0.6, 1.0, h))

static func profile_at(h: float) -> float:
	var x := clampf(h, 0.0, 1.0) * 10.0
	var i := mini(int(x), 9)
	var t := x - i
	var p0: float = PROFILE[maxi(i - 1, 0)]
	var p1: float = PROFILE[i]
	var p2: float = PROFILE[i + 1]
	var p3: float = PROFILE[mini(i + 2, 10)]
	return 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t)

## Deslocamento do eixo (local, plano XZ) na altura relativa h. Igual ao sway() do shader.
func axis_offset(h: float) -> Vector3:
	var amp := sway_amount * pow(h, 1.3) * (sin(sway_time * 1.6 - h * 5.0) * 0.5 + 0.5)
	var dir := sway_time * 0.8 - h * 7.0
	# "S" fixo do eixo (mesma conta do shader), girando devagar com o tempo.
	var s := s_curve * sin(h * PI * 1.25) * (1.0 - 0.35 * h)
	var s_dir := sway_time * 0.12
	return (Vector3(cos(dir) * amp, 0.0, sin(dir) * amp) + Vector3(cos(s_dir) * s, 0.0, sin(s_dir) * s)) * grow

## Ponto do eixo em coordenadas de mundo na altura relativa h.
func axis_point(h: float) -> Vector3:
	return global_transform * (axis_offset(h) + Vector3(0.0, h * height * grow, 0.0))

func _funnel_mesh(top_scale: float, tall := 1.0) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rings + 1:
		var h := float(j) / rings * tall
		var scale := top_scale
		var r := radius_at(minf(h, 1.0)) * scale
		# Inclinação do perfil para a normal (dr/dy).
		var dr := (radius_at(minf(h + 0.01, 1.0)) - radius_at(maxf(h - 0.01, 0.0))) * scale / (0.02 * height)
		for i in segments + 1:
			var a := TAU * i / segments
			var c := cos(a)
			var s := sin(a)
			tool.set_normal(Vector3(c, -dr, s).normalized())
			tool.set_uv(Vector2(float(i) / segments, h))
			tool.add_vertex(Vector3(c * r, h * height, s * r))
	var row := segments + 1
	for j in rings:
		for i in segments:
			var v := j * row + i
			tool.add_index(v)
			tool.add_index(v + row)
			tool.add_index(v + 1)
			tool.add_index(v + 1)
			tool.add_index(v + row)
			tool.add_index(v + row + 1)
	return tool.commit()

## Fita de vento: tira subindo em espiral por fora do funil (UV.x = ao longo, UV.y = largura).
func _ribbon_mesh(phase: float, turns: float, out_scale: float, width: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 160
	for j in steps + 1:
		var s := float(j) / steps
		var a := phase + s * turns * TAU
		var r := radius_at(s) * out_scale + 0.6
		var center := Vector3(cos(a) * r, s * height, sin(a) * r)
		# Largura na vertical (inclinada com a subida): a fita aparece bem de lado.
		var half := Vector3(0.0, width * (1.0 - 0.4 * s) * 0.5, 0.0)
		for k in 2:
			tool.set_uv(Vector2(s, float(k)))
			tool.set_normal(Vector3(cos(a), 0.0, sin(a)))
			tool.add_vertex(center + half * (1.0 if k == 1 else -1.0))
	for j in steps:
		var v := j * 2
		for k in [v, v + 2, v + 1, v + 1, v + 2, v + 3]:
			tool.add_index(k)
	return tool.commit()

func _build_funnel() -> void:
	# Três cascas concêntricas (de dentro para fora), faixas largas em hélice em ritmos e sentidos
	# diferentes: [escala, altura, faixas, torção, giro, largura, vãos, clara, sombra, prioridade].
	var shells := [
		# Interna: tom médio, gira devagar no sentido contrário.
		[0.86, 0.98, 3.0, 1.5, -0.12, 0.6, 0.0, Color(0.7, 0.72, 0.8), Color(0.5, 0.52, 0.62), 2],
		# Meio: clara e rápida, um pouco mais alta.
		[0.94, 1.06, 3.0, 1.7, 0.3, 0.62, 0.6, Color(0.9, 0.92, 0.97), Color(0.68, 0.7, 0.8), 3],
		# Fora: densa e escura, lenta, com vãos largos (mostra as de dentro).
		[1.0, 1.0, 2.0, 1.3, 0.16, 0.62, 1.0, Color(0.62, 0.62, 0.72), Color(0.4, 0.4, 0.5), 4],
	]
	for shell in shells:
		var material := ShaderMaterial.new()
		material.shader = BAND
		material.render_priority = shell[9]
		material.set_shader_parameter("noise_texture", NOISE_TEX)
		material.set_shader_parameter("bands", shell[2])
		material.set_shader_parameter("twist", shell[3])
		material.set_shader_parameter("spin", shell[4])
		material.set_shader_parameter("band_width", shell[5])
		material.set_shader_parameter("gaps", shell[6])
		material.set_shader_parameter("light_color", shell[7])
		material.set_shader_parameter("shade_color", shell[8])
		material.set_shader_parameter("height", height)
		material.set_shader_parameter("sway_amount", sway_amount)
		var node := MeshInstance3D.new()
		node.mesh = _funnel_mesh(shell[0], shell[1])
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		funnel_materials.append(material)
		layer_nodes.append(node)
	_build_splash()
	# Linhas de vento por fora: a mecânica do vento do jogo (fitas com cabeça e cauda, estudo do
	# Wind Waker) correndo em espiral pelo funil. Nascem e somem em ciclo, cada uma com fase própria.
	ribbons = Node3D.new()
	ribbons.name = "WindRibbons"
	add_child(ribbons)
	for k in 4:
		var material := ShaderMaterial.new()
		material.shader = TORNADO_WIND
		material.render_priority = 5
		var strip := PlaneMesh.new()
		strip.subdivide_width = 63
		strip.subdivide_depth = 1
		var node := MeshInstance3D.new()
		node.mesh = strip
		node.material_override = material
		node.custom_aabb = AABB(Vector3(-80, -5, -80), Vector3(160, height * 1.3, 160))
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ribbons.add_child(node)
		gusts.append({"material": material, "age": float(k) / 4.0, "life": rng.randf_range(2.6, 3.6)})
		_respawn_gust(gusts[k])

func _respawn_gust(gust: Dictionary) -> void:
	var material: ShaderMaterial = gust.material
	material.set_shader_parameter("phase", rng.randf_range(0.0, TAU))
	material.set_shader_parameter("turns", rng.randf_range(1.2, 2.2))
	material.set_shader_parameter("start_h", rng.randf_range(0.02, 0.3))
	material.set_shader_parameter("end_h", rng.randf_range(0.6, 0.95))
	material.set_shader_parameter("loop_amount", 1.0 if rng.randf() < 0.6 else 0.0)
	material.set_shader_parameter("out_scale", rng.randf_range(1.2, 1.5))
	material.set_shader_parameter("width", rng.randf_range(1.1, 1.8))
	for key in ["height", "radius_scale", "sway_amount", "s_curve"]:
		material.set_shader_parameter(key, get(key))
	gust.life = rng.randf_range(2.6, 3.6)

## Casca translúcida: o mesmo shader sem o recorte duro (o recorte manda para o passe opaco).
func _translucent(shader: Shader) -> Shader:
	var copy := Shader.new()
	copy.code = shader.code.replace("	ALPHA_SCISSOR_THRESHOLD = scissor > 0.5 ? 0.5 : 0.01;\n", "").replace("depth_draw_opaque", "depth_draw_never")
	return copy

## Gotículas e espuma girando rápido onde a ponta toca a água (vórtice de água).
func _build_splash() -> void:
	splash = GPUParticles3D.new()
	splash.name = "BaseSplash"
	splash.amount = 160
	splash.lifetime = 1.6
	splash.local_coords = true
	splash.visibility_aabb = AABB(Vector3(-25, -2, -25), Vector3(50, 20, 50))
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	motion.emission_ring_axis = Vector3.UP
	motion.emission_ring_radius = radius_at(0.0) * 1.05
	motion.emission_ring_inner_radius = radius_at(0.0) * 0.7
	motion.emission_ring_height = 0.5
	motion.direction = Vector3.UP
	motion.spread = 25.0
	motion.initial_velocity_min = 4.0
	motion.initial_velocity_max = 8.0
	motion.gravity = Vector3(0, -9.0, 0)
	# Gira em volta do eixo (órbita) e é jogada para fora.
	motion.orbit_velocity_min = 0.5
	motion.orbit_velocity_max = 0.8
	motion.radial_accel_min = 2.0
	motion.radial_accel_max = 5.0
	motion.scale_min = 0.6
	motion.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(0.85, 0.92, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	motion.color_ramp = ramp
	splash.process_material = motion
	var drop := QuadMesh.new()
	drop.size = Vector2(1.8, 1.8)
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.vertex_color_use_as_albedo = true
	paint.render_priority = 5
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = soft
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	paint.albedo_texture = tex
	drop.material = paint
	splash.draw_pass_1 = drop
	add_child(splash)

## Variante dos dois lados do shader do funil (render_mode não é parâmetro).
func _double_sided(shader: Shader) -> Shader:
	var copy := Shader.new()
	copy.code = shader.code.replace("render_mode unshaded,", "render_mode unshaded, cull_disabled,")
	return copy

## Disco largo no mar que sobe como parede de spray em volta da base do funil.
func _build_swirl() -> void:
	# Perfil (raio, altura) de fora para dentro.
	# A parede fica por fora da base do funil e sobe até ~8 m, cobrindo onde ele toca o mar.
	var profile := [Vector2(swirl_radius, 0.5), Vector2(swirl_radius * 0.75, 0.6), Vector2(swirl_radius * 0.6, 1.2),
		Vector2(swirl_radius * 0.53, 3.0), Vector2(swirl_radius * 0.5, 5.5), Vector2(swirl_radius * 0.53, 8.0)]
	var radial := 48
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in profile.size():
		var p: Vector2 = profile[j]
		for i in radial + 1:
			var a := TAU * i / radial
			tool.set_uv(Vector2(float(i) / radial, float(j) / (profile.size() - 1)))
			tool.set_normal(Vector3.UP)
			tool.add_vertex(Vector3(cos(a) * p.x, p.y, sin(a) * p.x))
	var row := radial + 1
	for j in profile.size() - 1:
		for i in radial:
			var v := j * row + i
			tool.add_index(v)
			tool.add_index(v + 1)
			tool.add_index(v + row)
			tool.add_index(v + 1)
			tool.add_index(v + row + 1)
			tool.add_index(v + row)
	swirl_material = ShaderMaterial.new()
	swirl_material.shader = SWIRL
	# O mar lê a profundidade da cena e por isso vai para a fila transparente (prioridade 0):
	# redemoinho e funil precisam vir depois dele.
	swirl_material.render_priority = 1
	swirl_material.set_shader_parameter("swirl_outer_radius", swirl_radius)
	swirl_material.set_shader_parameter("wall_height", 8.0)
	swirl_material.set_shader_parameter("cells_tex", CELLS_TEX)
	if weather and weather.ocean:
		weather.ocean.register_material(swirl_material)
	var node := MeshInstance3D.new()
	node.name = "Swirl"
	node.mesh = tool.commit()
	node.material_override = swirl_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

## 1) Nuvem de tempestade larga, girando devagar, com buraco no meio que converge nela mesma;
## 2) logo abaixo, um anel fino de nuvem girando na velocidade do furacão.
func _build_cloud() -> void:
	cloud_material = _vortex_material(0.12, 2.2, 0.1, 0.5, Color(0.3, 0.31, 0.36), Color(0.16, 0.17, 0.21))
	cloud = MeshInstance3D.new()
	cloud.name = "StormCloud"
	cloud.mesh = _disc_mesh(top_flare * 3.2, 18)
	cloud.material_override = cloud_material
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cloud)
	ring_material = _vortex_material(0.72, 0.8, 1.3, 0.0, Color(0.62, 0.6, 0.64), Color(0.42, 0.4, 0.45))
	ring_material.render_priority = 4
	ring = MeshInstance3D.new()
	ring.name = "CloudRing"
	ring.mesh = _disc_mesh(top_flare * 1.25, 10)
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

func _vortex_material(eye: float, twist_amount: float, spin_amount: float, rips: float, light: Color, dark: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = VORTEX
	material.render_priority = 3
	material.set_shader_parameter("eye", eye)
	material.set_shader_parameter("twist", twist_amount)
	material.set_shader_parameter("spin", spin_amount)
	material.set_shader_parameter("rips", rips)
	material.set_shader_parameter("light_color", light)
	material.set_shader_parameter("dark_color", dark)
	return material

func _disc_mesh(radius: float, rings_count: int) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments_count := 64
	for j in rings_count + 1:
		var r := pow(float(j) / rings_count, 1.3)
		for i in segments_count + 1:
			var a := TAU * i / segments_count
			tool.set_uv(Vector2(float(i) / segments_count, r))
			tool.set_normal(Vector3.UP)
			tool.add_vertex(Vector3(cos(a) * r * radius, 0.0, sin(a) * r * radius))
	var row := segments_count + 1
	for j in rings_count:
		for i in segments_count:
			var v := j * row + i
			for k in [v, v + 1, v + row, v + 1, v + row + 1, v + row]:
				tool.add_index(k)
	return tool.commit()

func _place() -> void:
	var up := center
	var tangent := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var other := tangent.cross(up).normalized()
	global_transform = Transform3D(Basis(tangent, up, other), up * planet_radius)

func _process(delta: float) -> void:
	sway_time += delta
	# Respira: expande e recolhe num ciclo de ~30 s.
	breath = 0.5 + 0.5 * sin(sway_time * TAU / lifecycle_seconds)
	_place()
	var night := 0.0
	var sun_dir := Vector3.UP
	if weather and weather.world and weather.world.sun:
		night = 1.0 - clampf(weather.world.sun.light_energy / 1.15, 0.0, 1.0)
		sun_dir = weather.world.sun.global_basis.z
	for material in funnel_materials:
		material.set_shader_parameter("sway_time", sway_time)
		material.set_shader_parameter("night", night)
		material.set_shader_parameter("sun_direction", sun_dir)
		material.set_shader_parameter("grow", grow)
		material.set_shader_parameter("breath", breath)
		material.set_shader_parameter("s_curve", s_curve)
		var flash: float = weather.world.get("sky_flash") if weather and weather.world and weather.world.get("sky_flash") != null else 0.0
		material.set_shader_parameter("flash", flash + (0.6 if fmod(sway_time, 7.3) < 0.12 else 0.0))
	if splash:
		splash.position = axis_offset(0.0)
		splash.scale = Vector3.ONE * grow
		splash.emitting = grow > 0.2
	if cloud_material:
		var top := axis_offset(1.0)
		cloud.scale = Vector3.ONE * grow
		cloud.position = top + Vector3(0.0, height * 1.04 * grow, 0.0)
		ring.scale = Vector3.ONE * grow * (0.9 + 0.1 * breath)
		ring.position = top + Vector3(0.0, height * 0.97 * grow, 0.0)
		ring_material.set_shader_parameter("night", night)
		ring_material.set_shader_parameter("strength", grow)
		for gust in gusts:
			gust.age = float(gust.age) + delta / float(gust.life)
			if float(gust.age) >= 1.0:
				gust.age = 0.0
				_respawn_gust(gust)
			var gm: ShaderMaterial = gust.material
			gm.set_shader_parameter("age", gust.age)
			gm.set_shader_parameter("sway_time", sway_time)
			gm.set_shader_parameter("breath", breath)
			gm.set_shader_parameter("grow", grow)
			gm.set_shader_parameter("night", night)
		cloud_material.set_shader_parameter("night", night)
		cloud_material.set_shader_parameter("strength", grow)
		# Forma-se juntando os pedaços (e se desfaz um pouco quando o funil recolhe).
		cloud_material.set_shader_parameter("form", 0.7 + 0.3 * breath)
	swirl_material.set_shader_parameter("night", night)
	swirl_material.set_shader_parameter("grow", grow)
	# O redemoinho acompanha as ondas do patch do mar (só existe perto do barco).
	var patch: Node3D = weather.world.get("ocean_patch") if weather and weather.world else null
	if is_instance_valid(patch):
		swirl_material.set_shader_parameter("patch_center", patch.global_position)
		swirl_material.set_shader_parameter("patch_radius", patch.patch_radius if patch.visible else 0.0)
