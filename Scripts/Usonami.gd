extends MeshInstance3D

## "Usonami" (onda de mentira), estudados no mar do Wind Waker: picos de onda em cartão que
## aparecem perto do horizonte. Em vez de deformar o mar inteiro, umas dezenas de cartões em pé
## (Shaders/usonami.gdshader) espalhados por um disco em volta da câmera, até um pouco além do
## horizonte (num planeta de 800 m ele fica a ~60–100 m: d = √(2·R·altura)). Regras tiradas do
## wave_move/drawWave do Wind Waker: cada pico vive num ciclo de seno (nasce, cresce, encolhe e
## some metade do tempo), deriva com o vento, e a "força do ambiente" zera o mar perto das ilhas
## e do barco (mar calmo); em mar aberto fica uma malha vasta. Somem na tempestade e no mapa.

const SHADER := preload("res://Shaders/usonami.gdshader")
const COUNT := 360

var near_distance := 40.0
var far_distance := 140.0

var world: Node3D
var ship: Node3D
var ocean: Node
var planet_radius := 800.0
var rng := RandomNumberGenerator.new()
var cards: Array[Dictionary] = []
var material: ShaderMaterial
## Quantos cartões foram desenhados no último quadro (testes).
var drawn := 0
var island_dirs: Array[Vector3] = []
var island_calm: Array[float] = []
## Deslocamento do centro do disco para a frente da câmera (m, no plano do mar).
var look_ahead := Vector3.ZERO

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	rng.randomize()
	material = ShaderMaterial.new()
	material.shader = SHADER
	# Depois do mar (que lê a profundidade e por isso vai para a fila transparente).
	material.render_priority = 1
	mesh = ImmediateMesh.new()
	material_override = material
	# Os cartões ficam em volta do barco; a caixa de visibilidade acompanha (ver _process).
	custom_aabb = AABB(Vector3.ONE * -1e5, Vector3.ONE * 2e5)

func _spawn(card: Dictionary, anywhere: bool, eye: Vector3) -> void:
	var up: Vector3 = eye.normalized()
	var t1 := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var t2 := up.cross(t1).normalized()
	var angle := rng.randf_range(0.0, TAU)
	# Como no original: espalhados pelo disco inteiro em volta da câmera (malha vasta), e quem
	# sai pela borda volta pelo lado oposto.
	var dist := sqrt(rng.randf()) * far_distance if anywhere else rng.randf_range(far_distance * 0.9, far_distance)
	# Como no original, o disco fica um pouco à frente do olhar (mais picos onde se olha),
	# mas cobre também a volta do barco.
	var flat: Vector3 = eye.normalized() * planet_radius + look_ahead + (t1 * cos(angle) + t2 * sin(angle)) * dist
	card.dir = flat.normalized()
	# Como no d_kankyo_rain.cpp (wave_move): tamanho sorteado; os pequenos vivem mais rápido e
	# os grandes andam mais com o vento. Largura total = 12 × altura (scaleBottom 6).
	card.scale = rng.randf_range(0.05, 1.0)
	# Baixos e abertos (ângulo largo): a crista quase deitada no mar.
	card.height = lerpf(0.4, 1.5, card.scale)
	card.width = card.height * 13.0
	if not card.has("counter"):
		card.counter = rng.randf_range(0.0, TAU)
	card.counter_speed = ((1.0 - card.scale) * 0.05 + 0.02) * 1.2 * 30.0
	card.alpha = 0.0

## Atrás do barco ou de uma ilha (esfera aproximada), visto da câmera?
func _occluded(eye: Vector3, pos: Vector3) -> bool:
	var to_card := pos - eye
	var card_dist := to_card.length()
	var dir := to_card / maxf(card_dist, 0.001)
	var blockers: Array = [[ship.global_position, 4.0]]
	for k in island_dirs.size():
		blockers.append([island_dirs[k] * planet_radius, island_calm[k] * 0.9])
	for b in blockers:
		var center: Vector3 = b[0]
		var along := (center - eye).dot(dir)
		if along <= 0.0 or along >= card_dist:
			continue
		if (eye + dir * along).distance_to(center) < float(b[1]):
			return true
	return false

func _process(delta: float) -> void:
	if not is_instance_valid(ship) or ocean == null:
		return
	var space_view: float = world.get("space_view") if world else 0.0
	visible = space_view < 0.3
	if not visible:
		return
	var camera := get_viewport().get_camera_3d()
	var eye: Vector3 = camera.global_position if camera else ship.global_position
	if eye.length() < planet_radius * 0.5:
		return  # câmera ainda no centro do planeta (primeiros quadros)
	# Faixa em volta do horizonte: de 70% dele até onde um pico de ~2 m ainda aparece atrás.
	var eye_height := maxf(eye.length() - planet_radius, 1.0)
	var horizon := sqrt(2.0 * planet_radius * eye_height)
	near_distance = maxf(25.0, horizon * 0.7)
	far_distance = horizon + sqrt(2.0 * planet_radius * 1.5)
	var cam_forward := (-camera.global_basis.z).slide(eye.normalized()) if camera else Vector3.ZERO
	look_ahead = cam_forward.normalized() * far_distance * 0.35 if cam_forward.length() > 0.01 else Vector3.ZERO
	if cards.is_empty():
		for i in COUNT:
			var c := {}
			_spawn(c, true, eye)
			cards.append(c)
	var daylight: float = clampf(world.sun.light_energy / 1.15, 0.0, 1.0) if world and world.sun else 1.0
	material.set_shader_parameter("daylight", daylight)
	# Corpo na cor do mar de verdade (as cores do oceano mudam com o horário).
	if not ocean.materials.is_empty():
		var sea: ShaderMaterial = ocean.materials[0]
		var deep = sea.get_shader_parameter("deep_ocean_color")
		var shallow = sea.get_shader_parameter("shallow_ocean_color")
		if deep is Color and shallow is Color:
			material.set_shader_parameter("body_color", (shallow as Color).lerp(Color(0.85, 0.97, 1.0), 0.25))
	var eye_ground: Vector3 = eye.normalized() * planet_radius
	var wind: Vector3 = world.wind_at(eye_ground) if world.has_method("wind_at") else Vector3.ZERO
	if island_dirs.is_empty() and "islands" in world:
		for island in world.islands:
			island_dirs.append(island.global_position.normalized())
			# Mar calmo em volta da ilha (raio de colisão da costa + folga).
			island_calm.append(60.0)
	var im := mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	drawn = 0
	for i in cards.size():
		var c: Dictionary = cards[i]
		var base: Vector3 = (c.dir as Vector3) * planet_radius
		var dist := base.distance_to(eye_ground + look_ahead)
		# Saiu pela borda: volta pelo outro lado; longe demais (teleporte, mapa): em qualquer lugar.
		if dist > far_distance * 1.1:
			_spawn(c, dist < far_distance * 1.6, eye)
			base = (c.dir as Vector3) * planet_radius
			dist = base.distance_to(eye_ground + look_ahead)
		# Ciclo do original: a altura segue sin(contador); metade do tempo o pico não existe.
		c.counter += float(c.counter_speed) * delta
		# Fim do ciclo: a onda se desfez; a próxima nasce em outro ponto do disco.
		if float(c.counter) > TAU:
			var keep: float = float(c.counter) - TAU
			_spawn(c, true, eye)
			c.counter = keep
			base = (c.dir as Vector3) * planet_radius
			dist = base.distance_to(eye_ground + look_ahead)
		var rise := sin(float(c.counter))
		if rise <= 0.0:
			continue
		# Deriva com o vento (grandes andam mais).
		var drift: Vector3 = wind * float(c.scale) * 1.8 * delta
		c.dir = ((c.dir as Vector3) * planet_radius + drift).normalized()
		var surface: Vector3 = ocean.surface_at(base)
		var up := surface.normalized()
		var pos := surface - up * 0.1
		# Força do ambiente (mStrengthEnv): zero perto das ilhas e do barco, como no jogo.
		var strength := 1.0
		for k in island_dirs.size():
			var d_island: float = up.angle_to(island_dirs[k]) * planet_radius
			strength = minf(strength, smoothstep(island_calm[k], island_calm[k] + 90.0, d_island))
		strength *= smoothstep(2.0, 20.0, pos.distance_to(ship.global_position))
		# Desenhados sem teste de profundidade (nosso mar tem ondulação grande e os escondia;
		# no Wind Waker o mar é quase plano). Então escondemos à mão os que ficam atrás do barco
		# ou de uma ilha vistos da câmera.
		if _occluded(eye, pos):
			continue
		strength *= 1.0 - smoothstep(0.4, 1.2, float(ocean.badness_at(surface)))
		# Opaco quase todo o ciclo (o tamanho já faz nascer/sumir); só a ponta do ciclo esmaece.
		var target_alpha := clampf((1.0 - dist / (2.0 * far_distance)) * 3.0 * rise, 0.0, 1.0)
		c.alpha = lerpf(float(c.alpha), target_alpha, 1.0 - exp(-6.0 * delta))
		var fade: float = float(c.alpha) * (1.0 - smoothstep(far_distance * 0.9, far_distance * 1.1, dist))
		rise *= strength
		if fade <= 0.01:
			continue
		drawn += 1
		# Quadrado de pé (no "para cima" do planeta) virado para a câmera.
		var right := up.cross(eye - pos).normalized() * (float(c.width) * 0.5 * strength)
		var top := up * (float(c.height) * rise)
		var color := Color(1, 1, 1, fade)
		var corners := [pos - right, pos + right, pos + right + top, pos - right + top]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in [0, 1, 2, 0, 2, 3]:
			im.surface_set_color(color)
			im.surface_set_uv(uvs[k])
			im.surface_add_vertex(corners[k])
	im.surface_end()
