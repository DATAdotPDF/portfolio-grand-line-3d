extends Node3D

## Uma tempestade local (o conjunto é gerenciado por Weather.gd):
## - chuva por partículas na área dela (quadros com vários riscos, técnica do
##   "Easy Particle Rain in Godot 4", CC0), sem cilindro de névoa;
## - massa de nuvens 3D em três camadas (base larga, meio, topo arredondado), cada uma girando
##   no seu ritmo e sentido: o "redemoinho" das tempestades do Wind Waker, sem o buraco no meio;
## - mar mais alto e escuro dentro do raio (Weather soma no oceano);
## - relâmpagos estilizados: fino, anguloso, com galhos, halo aditivo e 2-3 piscadas.
## Quem move a tempestade é o Weather.gd (só por mar aberto, longe das ilhas e das rotas).
## badness (0..4) sobe e desce num ciclo de alguns minutos e comanda chuva, raios e nuvem;
## o Weather repassa o mesmo valor para o mar (ondas, espuma), o vento e o céu.

const DROPS := preload("res://Shaders/rain_drops.gdshader")
const CARD := preload("res://Shaders/cloud_card.gdshader")
const ATLAS := preload("res://Assets/Clouds/cloud_atlas.png")
const CURTAIN := preload("res://Shaders/rain_curtain.gdshader")
const Scale := preload("res://Scripts/WorldScale.gd")

@export var radius := 60.0
@export var peak_badness := 3.5
## Piso do ciclo (a nuvem do ciclone nunca acalma muito).
@export var min_badness := 1.2
## Base da nuvem bem acima das ondas da tempestade (que passam de 5 m) e da câmera.
@export var cloud_height := 54.0

var weather: Node
var planet_radius := 800.0
var center := Vector3.UP
var badness := 2.0
## Série de ondas maiores (evento de desafio, Weather.gd): soma no badness e decai.
var surge := 0.0
var cycle_phase := 0.0
var cycle_period := 240.0
var age := 0.0
var cards: Array[Dictionary] = []
var cloud_cards: MultiMeshInstance3D
var sort_timer := 0.0
var cloud_material: ShaderMaterial
## Forma sorteada ("anvil", "shelf", "tower"); pode ser fixada antes do _ready.
var shape := ""
var rain_shaft: MultiMeshInstance3D
var _curtain_down := Vector3.FORWARD
var rain_shaft_material: ShaderMaterial
var rain: GPUParticles3D
var rain_material: ShaderMaterial
var flash := 0.0
var next_strike := 6.0
var bolt: MeshInstance3D
var bolt_mesh: ImmediateMesh
var bolt_material: StandardMaterial3D
var bolt_age := 99.0
var rng := RandomNumberGenerator.new()

func setup(home_direction: Vector3, seed_value: int) -> void:
	center = home_direction.normalized()
	rng.seed = seed_value
	cycle_phase = rng.randf_range(0.0, TAU)
	cycle_period = rng.randf_range(180.0, 320.0)
	peak_badness = rng.randf_range(3.0, 4.0)
	next_strike = rng.randf_range(3.0, 9.0)

func _ready() -> void:
	_place()
	_build_clouds()
	_build_rain()
	_build_rain_shaft()
	_build_bolt()

## Nuvem em cartões (técnica do Sea of Thieves; tufos volumétricos nossos assados no Blender,
## Tools/bake_cloud_atlas.py): cada bolota vira um cartão virado para a câmera, num MultiMesh só.
## Formas variadas (referência: o vídeo do Sea of Thieves): cada tempestade sorteia uma:
## - "anvil": torre + bigorna larga e achatada no topo;
## - "shelf": massa baixa e larga, base reta e escura, com braços de fumaça esticados para os lados;
## - "tower": torre alta inclinada pelo vento (o topo escorre a favor do vento) e bigorna pequena.
## Tudo é esticado na direção do vento e as camadas de cima deslizam a favor dele (cisalhamento).
func _build_clouds() -> void:
	if shape == "":
		shape = ["anvil", "shelf", "tower"][rng.randi() % 3]
	var stretch := rng.randf_range(1.05, 1.4)
	var h := cloud_height
	# [altura, [anel: quantidade, raio relativo, tamanho relativo], achatamento, deslize a favor do vento (× raio)]
	var layers: Array = []
	# [camada, altura local, quantidade, comprimento (× raio)]
	var arms: Array = []
	match shape:
		"shelf":
			layers = [
				[h - 3.0, [[20, 0.95, 0.24], [12, 0.6, 0.26], [5, 0.3, 0.28], [1, 0.0, 0.3]], 0.36, 0.0, true],
				[h + 5.0, [[10, 0.55, 0.25], [1, 0.0, 0.3]], 0.6, 0.08],
				[h + 13.0, [[5, 0.26, 0.22], [1, 0.0, 0.26]], 0.8, 0.15],
			]
			arms = [[0, 1.0, rng.randi_range(3, 5), rng.randf_range(1.0, 1.5)]]
		"tower":
			layers = [
				[h - 3.0, [[12, 0.7, 0.26], [6, 0.4, 0.28], [1, 0.0, 0.32]], 0.55, 0.0],
				[h + 8.0, [[7, 0.36, 0.25], [1, 0.0, 0.3]], 0.85, 0.08],
				[h + 19.0, [[6, 0.3, 0.23], [1, 0.0, 0.28]], 0.9, 0.18],
				[h + 30.0, [[5, 0.26, 0.22], [1, 0.0, 0.26]], 0.95, 0.3],
				[h + 41.0, [[5, 0.24, 0.2], [1, 0.0, 0.25]], 0.9, 0.42],
				[h + 50.0, [[16, 0.95, 0.2], [9, 0.55, 0.22], [1, 0.0, 0.26]], 0.24, 0.6, true],
			]
			arms = [[5, 0.0, rng.randi_range(1, 2), rng.randf_range(0.8, 1.2)]]
		_:
			# Cumulonimbus clássico (fotos de referência): torre alta em "couve-flor", bigorna fina e
			# muito larga (bem mais que a torre) com a barriga lisa, e um domo pequeno furando o topo.
			layers = [
				[h - 3.0, [[16, 0.8, 0.26], [8, 0.45, 0.28], [1, 0.0, 0.34]], 0.5, 0.0],
				[h + 7.0, [[10, 0.5, 0.27], [1, 0.0, 0.32]], 0.9, 0.04],
				[h + 18.0, [[8, 0.38, 0.25], [1, 0.0, 0.3]], 0.95, 0.08],
				[h + 29.0, [[7, 0.33, 0.24], [1, 0.0, 0.28]], 0.95, 0.12],
				[h + 40.0, [[6, 0.3, 0.24], [1, 0.0, 0.28]], 0.95, 0.16],
				[h + 50.0, [[26, 1.45, 0.2], [18, 1.0, 0.22], [10, 0.55, 0.24], [1, 0.0, 0.26]], 0.2, 0.3, true],
				[h + 55.0, [[3, 0.14, 0.16], [1, 0.0, 0.2]], 0.85, 0.22],
			]
			arms = [[5, 0.0, rng.randi_range(1, 2), rng.randf_range(0.5, 0.8)]]
	var down := _wind_local()
	var side := Vector3(-down.z, 0.0, down.x)
	var base_y := h - 6.0
	var top_y: float = float(layers[layers.size() - 1][0]) + 6.0
	var to_frac := func(y: float) -> float: return clampf((y - base_y) / maxf(top_y - base_y, 1.0), 0.0, 1.0)
	for layer in layers:
		var y: float = layer[0]
		var shift: Vector3 = down * radius * float(layer[3])
		var flat_layer: bool = layer.size() > 4 and layer[4]
		# Camadas achatadas (bigorna, prateleira): poucas lâminas grandes e bem transparentes só
		# para fechar a barriga; o corpo vem dos tufos achatados abaixo.
		if flat_layer:
			var reach := 0.0
			for ring in layer[1]:
				reach = maxf(reach, float(ring[1]) + float(ring[2]))
			for k in 5:
				var a := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
				var p := Vector3(cos(a), 0.0, sin(a)) * radius * reach * (0.0 if k == 0 else 0.45)
				p = down * p.dot(down) * stretch + side * p.dot(side)
				_add_card(p + shift + Vector3(0.0, y - 2.0, 0.0), radius * reach * 1.3, 8 + rng.randi() % 4, to_frac.call(y), 0.5)
		# Camadas achatadas: tufos espalhados pelo disco inteiro (em anéis, vistos de baixo,
		# apareciam como argolas com buraco no meio).
		var reach_flat := 0.0
		var total := 0
		for ring in layer[1]:
			reach_flat = maxf(reach_flat, float(ring[1]))
			total += int(ring[0])
		for ring in layer[1]:
			var amount: int = ring[0]
			for i in amount:
				var angle: float = TAU * (i + rng.randf_range(-0.25, 0.25)) / maxi(amount, 1)
				var dist: float = radius * float(ring[1]) * rng.randf_range(0.9, 1.08)
				if flat_layer:
					angle = rng.randf_range(0.0, TAU)
					dist = radius * reach_flat * sqrt(rng.randf()) * 1.02
				var size: float = radius * float(ring[2]) * rng.randf_range(0.9, 1.15) * 2.5
				var flat := Vector3(cos(angle), 0.0, sin(angle)) * dist
				flat = down * flat.dot(down) * stretch + side * flat.dot(side)
				var y_here := y + rng.randf_range(-1.5, 2.5)
				var origin := flat + shift + Vector3(0.0, y_here, 0.0)
				if flat_layer:
					# Bigorna: tufos de couve-flor achatados no próprio cartão (mais largos que altos),
					# dois por ponto para a folha fechar sem falhas vista de baixo.
					_add_card(origin, size * 2.2, rng.randi() % 8, to_frac.call(y_here), 0.95, 0.5)
					var jitter := Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)) * size * 0.5
					_add_card(origin + jitter + Vector3(0.0, -size * 0.12, 0.0), size * 1.8, rng.randi() % 8, to_frac.call(y_here), 0.9, 0.45)
				else:
					_add_card(origin, size * 1.7, rng.randi() % 8, to_frac.call(y_here), 1.0)
	# Braços: fiapos (variantes 12..15) que afinam e caem na ponta.
	for arm in arms:
		var layer_shift: Vector3 = down * radius * float(layers[int(arm[0])][3])
		var arm_y: float = float(layers[int(arm[0])][0]) + float(arm[1])
		for n in int(arm[2]):
			var spread := 0.5 if shape == "tower" else 1.3
			var dir := down.rotated(Vector3.UP, rng.randf_range(-spread, spread))
			var curl := rng.randf_range(-0.6, 0.6)
			var length: float = radius * float(arm[3]) * rng.randf_range(0.8, 1.2)
			var steps := 7
			for k in steps:
				var t := float(k) / (steps - 1)
				var bend := dir.rotated(Vector3.UP, curl * t)
				var size := radius * lerpf(0.3, 0.12, t) * 2.6
				var origin := layer_shift + bend * (radius * 0.5 + length * t) + Vector3(0.0, arm_y - 5.0 * t * t, 0.0)
				_add_card(origin, size, 12 + rng.randi() % 4, to_frac.call(origin.y), lerpf(0.9, 0.5, t))
	_build_card_multimesh()

## Um cartão: posição local, tamanho (m), variante do atlas, altura relativa, opacidade e
## proporção altura/largura (1 = quadrado; 0,5 = tufo achatado).
func _add_card(position: Vector3, size: float, variant: int, height: float, opacity: float, aspect := 1.0) -> void:
	cards.append({"position": position, "size": size, "variant": variant, "height": height,
		"opacity": opacity, "flip": 1.0 if rng.randf() < 0.5 else 0.0, "aspect": aspect})

func _build_card_multimesh() -> void:
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = CARD
	cloud_material.set_shader_parameter("atlas", ATLAS)
	cloud_material.set_shader_parameter("near_fade", radius * 0.6)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = cards.size()
	cloud_cards = MultiMeshInstance3D.new()
	cloud_cards.name = "CloudCards"
	cloud_cards.multimesh = multimesh
	cloud_cards.material_override = cloud_material
	cloud_cards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud_cards.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Caixa de visibilidade generosa (os cartões giram para a câmera).
	cloud_cards.custom_aabb = AABB(Vector3(-radius * 3.0, -10.0, -radius * 3.0), Vector3(radius * 6.0, cloud_height + 90.0, radius * 6.0))
	add_child(cloud_cards)
	_sort_cards(Vector3(0.0, -1000.0, 0.0))

## Transparência precisa de ordem: do mais longe ao mais perto da câmera (refeito a cada 0,2 s).
func _sort_cards(eye_local: Vector3) -> void:
	var order := range(cards.size())
	order.sort_custom(func(a, b): return (cards[a].position as Vector3).distance_squared_to(eye_local) > (cards[b].position as Vector3).distance_squared_to(eye_local))
	var multimesh := cloud_cards.multimesh
	for slot in order.size():
		var c: Dictionary = cards[order[slot]]
		var s: float = c.size
		multimesh.set_instance_transform(slot, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s * float(c.aspect), s)), c.position))
		multimesh.set_instance_color(slot, Color((float(c.variant) + 0.01) / 16.0, c.height, c.flip, c.opacity))

## Direção do vento no plano local da tempestade (para esticar e inclinar a nuvem).
func _wind_local() -> Vector3:
	var axis := Scale.wind_axis()
	var local := global_basis.inverse() * axis if is_inside_tree() else axis
	local.y = 0.0
	return local.normalized() if local.length_squared() > 0.0001 else Vector3.FORWARD

## Cortina de chuva vista de longe: alguns lençóis verticais macios (rain_curtain.gdshader)
## espalhados sob a nuvem, cada um girando para encarar a câmera e inclinado pelo vento. Sem
## cilindro (a borda dele aparecia como linhas marcando a área da tempestade).
func _build_rain_shaft() -> void:
	var down := _wind_local()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.center_offset = Vector3(0.0, 0.0, 0.0)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	var sheets := 9
	multimesh.instance_count = sheets
	var top := cloud_height - 3.0
	for k in sheets:
		var a := TAU * k / sheets + rng.randf_range(-0.3, 0.3)
		var r := radius * rng.randf_range(0.0, 0.65)
		var width := radius * rng.randf_range(0.7, 1.1)
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
		# Vai até 8 m abaixo do nível do mar: com ondas de tempestade e a curva do planeta, a base
		# sempre fica dentro d'água.
		var b := Basis(Vector3(width, 0, 0), Vector3(0, top + 8.0, 0), Vector3(0, 0, 1))
		multimesh.set_instance_transform(k, Transform3D(b, base - Vector3(0, 8.0, 0)))
	rain_shaft_material = ShaderMaterial.new()
	rain_shaft_material.shader = CURTAIN
	rain_shaft_material.set_shader_parameter("near_fade", radius * 1.2)
	rain_shaft_material.set_shader_parameter("lean", radius * 0.3)
	rain_shaft = MultiMeshInstance3D.new()
	rain_shaft.name = "RainCurtain"
	rain_shaft.multimesh = multimesh
	rain_shaft.material_override = rain_shaft_material
	rain_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain_shaft.custom_aabb = AABB(Vector3(-radius * 2, -10, -radius * 2), Vector3(radius * 4, cloud_height + 20, radius * 4))
	add_child(rain_shaft)
	_curtain_down = down

func _build_rain() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius * 1.05
	process.emission_ring_inner_radius = 0.0
	process.emission_ring_height = 3.0
	process.direction = Vector3.DOWN
	process.spread = 2.0
	process.initial_velocity_min = 17.0
	process.initial_velocity_max = 20.0
	process.gravity = Vector3.ZERO
	process.scale_min = 0.8
	process.scale_max = 1.25
	# Nasce e some transparente (sem "estalo" no topo e na água).
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.85, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	rain_material = ShaderMaterial.new()
	rain_material.shader = DROPS
	rain_material.set_shader_parameter("streaks", 6)
	rain_material.set_shader_parameter("streak_width", 0.022)
	rain_material.set_shader_parameter("streak_length", 0.26)
	rain_material.set_shader_parameter("opacity", 0.24)
	# De longe a cortina fica mais escura e densa (lê como chuva saindo da nuvem).
	rain_material.set_shader_parameter("rain_color", Color(0.42, 0.47, 0.48))
	rain_material.set_shader_parameter("soft_density", 0.6)
	# Quadros grandes com 8 riscos cada: de longe vira "cortina" de chuva, sem névoa.
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 7.0)
	quad.material = rain_material
	rain = GPUParticles3D.new()
	rain.name = "StormRain"
	rain.process_material = process
	rain.draw_pass_1 = quad
	rain.amount = 1500
	rain.lifetime = cloud_height / 18.5
	rain.preprocess = rain.lifetime
	rain.local_coords = true
	rain.position.y = cloud_height - 2.0
	rain.visibility_aabb = AABB(Vector3(-radius * 1.2, -cloud_height - 6.0, -radius * 1.2), Vector3(radius * 2.4, cloud_height + 10.0, radius * 2.4))
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)

func _build_bolt() -> void:
	bolt_mesh = ImmediateMesh.new()
	bolt_material = StandardMaterial3D.new()
	bolt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt_material.vertex_color_use_as_albedo = true
	bolt_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bolt_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bolt_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	bolt_material.no_depth_test = false
	bolt = MeshInstance3D.new()
	bolt.mesh = bolt_mesh
	bolt.material_override = bolt_material
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.visible = false
	add_child(bolt)

func _place() -> void:
	var up := center
	var tangent := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var other := tangent.cross(up).normalized()
	global_transform = Transform3D(Basis(tangent, up, other), up * planet_radius)

func _process(delta: float) -> void:
	# Ciclo de vida: cresce até o pico e acalma, sem nunca sumir de vez.
	age += delta
	badness = lerpf(min_badness, peak_badness, 0.5 + 0.5 * sin(age * TAU / cycle_period + cycle_phase))
	surge = move_toward(surge, 0.0, delta * 0.12)
	badness += surge
	rain.amount_ratio = clampf(badness / 4.0, 0.25, 1.0)
	cloud_material.set_shader_parameter("badness", badness)
	_place()
	# A nuvem inteira gira bem devagar; os cartões são reordenados para a câmera de tempos em tempos.
	cloud_cards.rotation.y += 0.025 * delta
	sort_timer -= delta
	var camera := get_viewport().get_camera_3d()
	if sort_timer <= 0.0 and camera:
		sort_timer = 0.2
		_sort_cards(cloud_cards.global_transform.affine_inverse() * camera.global_position)
	var night := 0.0
	if weather and weather.world and weather.world.sun:
		night = 1.0 - clampf(weather.world.sun.light_energy / 1.15, 0.0, 1.0)
		# À noite a luz vem de cima (lua), não do sol embaixo do horizonte.
		var light_travel: Vector3 = (-weather.world.sun.global_basis.z).lerp(-global_basis.y, night).normalized()
		cloud_material.set_shader_parameter("sun_direction", light_travel)
		# À noite a "luz de cima" é a lua (azulada), não o laranja do sol abaixo do horizonte.
		cloud_material.set_shader_parameter("sun_color", weather.world.sun.light_color.lerp(Color(0.55, 0.62, 0.8), night))
	rain_material.set_shader_parameter("night", night)
	cloud_material.set_shader_parameter("night", night)
	rain_shaft_material.set_shader_parameter("night", night)
	rain_shaft_material.set_shader_parameter("density", clampf(badness / 4.0, 0.2, 1.0))
	rain_shaft_material.set_shader_parameter("flash", flash)
	rain_shaft_material.set_shader_parameter("lean_dir", global_basis * _curtain_down)
	# Partículas de chuva só de perto (de longe viravam tracinhos cinza; lá vale a cortina).
	var cam := get_viewport().get_camera_3d()
	if cam:
		rain.visible = cam.global_position.distance_to(global_position) < radius * 1.8
	# Trovão de dentro (Thunder.gd) também acende a nuvem.
	var thunder_flash: float = weather.thunder.sky_flash if weather and weather.get("thunder") else 0.0
	cloud_material.set_shader_parameter("flash", maxf(flash, thunder_flash * 0.7))
	_update_lightning(delta)

func _update_lightning(delta: float) -> void:
	bolt_age += delta
	# Piscadas: acende, quase apaga, acende de novo e some.
	var a := 0.0
	if bolt_age < 0.06:
		a = 1.0
	elif bolt_age < 0.11:
		a = 0.15
	elif bolt_age < 0.2:
		a = 1.0
	elif bolt_age < 0.24:
		a = 0.3
	elif bolt_age < 0.4:
		a = 0.8 * (1.0 - (bolt_age - 0.24) / 0.16)
	flash = a
	bolt.visible = a > 0.0
	bolt_material.albedo_color = Color(1, 1, 1, a)
	# Só cai raio se o barco estiver por perto (de longe: só a nuvem e a chuva).
	if weather == null or not is_instance_valid(weather.ship):
		return
	# Raio da própria nuvem só visto de fora; dentro quem cuida é o Thunder (raios no horizonte).
	var ship_dist: float = weather.ship.global_position.distance_to(center * planet_radius)
	if ship_dist > 480.0 or ship_dist < radius * 1.2 or badness < 2.3:
		return
	next_strike -= delta
	if next_strike <= 0.0:
		# Quanto pior a tempestade, mais raios.
		next_strike = rng.randf_range(4.0, 10.0) * 3.0 / badness
		bolt_age = 0.0
		_draw_bolt()

## Raio estilizado: tronco em zigue-zague anguloso + 1 a 2 galhos; núcleo branco fino + halo azulado.
func _draw_bolt() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := to_local(camera.global_position)
	# Cai dentro da tempestade, preferindo o lado de quem olha.
	var look := to_local(camera.global_position - camera.global_basis.z * 50.0) - eye
	var dir2 := Vector2(look.x, look.z).normalized() if Vector2(look.x, look.z).length() > 0.01 else Vector2(1, 0)
	var base := Vector2(eye.x, eye.z) + dir2.rotated(rng.randf_range(-0.6, 0.6)) * rng.randf_range(25.0, 45.0)
	if base.length() > radius * 0.7:
		base = base.normalized() * radius * 0.7
	var top := Vector3(base.x, cloud_height - 4.0, base.y)
	var trunk := _zigzag(top, Vector3(base.x + rng.randf_range(-5, 5), -0.3, base.y + rng.randf_range(-5, 5)), 8, 2.8)
	var branches: Array = []
	for b in rng.randi_range(1, 2):
		var start: Vector3 = trunk[rng.randi_range(2, 4)]
		var out := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		branches.append(_zigzag(start, start + out * rng.randf_range(6.0, 10.0) + Vector3(0, -rng.randf_range(6.0, 10.0), 0), 4, 1.6))
	bolt_mesh.clear_surfaces()
	bolt_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_ribbon(trunk, eye, 0.5, Color(1.0, 0.42, 0.38, 0.5))
	_ribbon(trunk, eye, 0.09, Color(1.0, 0.9, 0.72, 1))
	for branch in branches:
		_ribbon(branch, eye, 0.28, Color(1.0, 0.45, 0.5, 0.35))
		_ribbon(branch, eye, 0.05, Color(1.0, 0.85, 0.7, 0.9))
	bolt_mesh.surface_end()

func _zigzag(a: Vector3, b: Vector3, segments: int, jitter: float) -> Array:
	var points: Array = [a]
	var side := 1.0
	var axis := (b - a).normalized()
	var lateral := axis.cross(Vector3(0.3, 0.0, 1.0)).normalized()
	var lateral2 := axis.cross(lateral).normalized()
	for i in range(1, segments):
		var t := float(i) / segments
		side = -side
		var p := a.lerp(b, t) + lateral * side * rng.randf_range(jitter * 0.4, jitter) + lateral2 * rng.randf_range(-jitter, jitter) * 0.5
		points.append(p)
	points.append(b)
	return points

func _ribbon(points: Array, eye: Vector3, width: float, color: Color) -> void:
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var w := width * lerpf(1.0, 0.55, float(i) / points.size())
		var side := (b - a).cross(eye - a).normalized() * w
		for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
			bolt_mesh.surface_set_color(color)
			bolt_mesh.surface_add_vertex(v)
