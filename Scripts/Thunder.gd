extends MeshInstance3D

## Trovões dentro da tempestade (regras estudadas em dKyr_thunder_move / dThunder_c do Wind
## Waker; código nosso). A cada quadro (base 30 fps) com o barco dentro da tempestade:
## - 0,7% de chance de clarão DISTANTE: acende só o céu e a névoa;
## - 0,5% de chance de clarão PRÓXIMO: luz azulada (90,160,245) em tudo + som.
## O clarão sobe rápido (passo 0,3) e desce devagar (0,1). Enquanto sobe, 18% por quadro de
## nascer um raio encenado no horizonte, à frente da câmera e para um dos lados (os raios
## sempre aparecem para quem olha, em vez de cair num lugar fixo da nuvem).

const FLASH_COLOR := Color(0.35, 0.63, 0.96)
# Trovões gravados (Freesound, recortes de Tools/cut_game_sfx.sh): estalo bem perto, próximo e
# distante, com variações sorteadas.
const CRACK: Array[AudioStream] = [preload("res://Assets/Sound/SFX/Cuts/thunder_crack_a.ogg"), preload("res://Assets/Sound/SFX/Cuts/thunder_crack_b.ogg")]
const NEAR: Array[AudioStream] = [preload("res://Assets/Sound/SFX/Cuts/thunder_near_a.ogg"), preload("res://Assets/Sound/SFX/Cuts/thunder_near_b.ogg"), preload("res://Assets/Sound/SFX/Cuts/thunder_near_c.ogg")]
const FAR: Array[AudioStream] = [preload("res://Assets/Sound/SFX/Cuts/thunder_far_a.ogg"), preload("res://Assets/Sound/SFX/Cuts/thunder_far_b.ogg"), preload("res://Assets/Sound/SFX/Cuts/thunder_far_c.ogg")]
## Velocidade do som (m/s): o trovão chega depois do clarão, atrasado pela distância do raio.
const SOUND_SPEED := 343.0

var weather: Node
var rng := RandomNumberGenerator.new()
## 0 parado, 1 subindo (próximo), 2 descendo (próximo), 11/12 idem distante.
var state := 0
var flash := 0.0
var bolts: Array[Dictionary] = []
var lines := ImmediateMesh.new()
var material := StandardMaterial3D.new()
var accum := 0.0
## Trovão do clarão atual: -1 = ainda sem distância; depois, segundos até o som chegar.
var thunder_wait := -1.0
var thunder_far := false
var thunder_distance := 0.0
var thunder_pending := false

## Clarão que acende tudo (próximo) e só o céu (distante), 0..1.
var near_flash := 0.0
var sky_flash := 0.0
## 0 = raios azulados (tempestade), 1 = vermelhos (kraken).
var red := 0.0

func _ready() -> void:
	rng.randomize()
	top_level = true
	mesh = lines
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true
	material.render_priority = 3
	material_override = material
	custom_aabb = AABB(Vector3.ONE * -1e5, Vector3.ONE * 2e5)

## gloom: quanto o barco está dentro de tempestade (0..1).
func step(delta: float, gloom: float) -> void:
	accum += delta
	# Lógica em passos de 1/30 s, como o jogo original.
	while accum >= 1.0 / 30.0:
		accum -= 1.0 / 30.0
		_tick(gloom)
	if thunder_pending and thunder_wait >= 0.0:
		thunder_wait -= delta
		if thunder_wait <= 0.0:
			_play_thunder()
	near_flash = flash if state in [1, 2] else 0.0
	sky_flash = flash
	_draw()

func _tick(gloom: float) -> void:
	match state:
		0:
			flash = 0.0
			if gloom < 0.5:
				return
			if rng.randf() < 0.007:
				state = 11
			elif rng.randf() < 0.005:
				state = 1
			if state != 0:
				_arm_thunder(state == 11)
		1, 11:
			flash = _add_calc(flash, 1.0, 0.3, 0.2)
			if rng.randf() < 0.18:
				_spawn_bolt(state == 11)
			if flash >= 1.0:
				state += 1
				# Clarão sem raio visível: trovão de uma distância sorteada.
				if thunder_pending and thunder_wait < 0.0:
					_schedule_thunder(rng.randf_range(150.0, 320.0) * (1.4 if state == 12 else 1.0))
		2, 12:
			flash = _add_calc(flash, 0.0, 0.1, 0.05)
			if flash <= 0.0:
				state = 0
	for b in bolts:
		b.life -= 1.0 / 30.0
	bolts = bolts.filter(func(b): return b.life > 0.0)

## Aproximação do original (cLib_addCalc): passo = diferença × escala, entre 0,001 e o máximo.
func _add_calc(value: float, target: float, scale: float, max_step: float) -> float:
	var step := clampf(absf(target - value) * scale, 0.001, max_step)
	return move_toward(value, target, step)

## Raio no horizonte: a 150–320 m à frente da câmera, deslocado para um lado.
func _spawn_bolt(far: bool) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or weather == null:
		return
	# Sem raios "na frente da câmera" quando ela está no espaço (mapa).
	if weather.world and float(weather.world.get("space_view")) > 0.3:
		return
	var eye: Vector3 = camera.global_position
	var up := eye.normalized()
	var forward := (-camera.global_basis.z).slide(up).normalized()
	var side := up.cross(forward).normalized()
	var ground: Vector3 = up * weather.planet_radius
	var dist := rng.randf_range(150.0, 320.0) * (1.4 if far else 1.0)
	var base := ground + forward * dist + side * rng.randf_range(-1.0, 1.0) * dist * 0.8
	var base_up := base.normalized()
	base = base_up * weather.planet_radius
	if thunder_pending and thunder_wait < 0.0:
		_schedule_thunder(eye.distance_to(base))
	var height := rng.randf_range(80.0, 150.0) * (0.6 if far else 1.0)
	var width := rng.randf_range(5.0, 20.0) * (1.0 if rng.randf() < 0.5 else -1.0) * (0.5 if far else 1.0)
	var bolt_side: Vector3 = base_up.cross(forward).normalized()
	var points: Array = []
	# Zigue-zague anguloso: alterna o lado a cada segmento (como os raios do jogo).
	var segments := 12
	var lean := 0.0
	for i in segments + 1:
		var t := float(i) / segments
		if i > 0 and i < segments:
			lean += (1.0 if i % 2 == 0 else -1.0) * rng.randf_range(0.04, 0.12) + 0.03
		points.append(base + base_up * height * (1.0 - t) + bolt_side * width * lean)
	var branch: Array = []
	var start_i := rng.randi_range(2, 4)
	var start: Vector3 = points[start_i]
	for i in 4:
		branch.append(start + bolt_side * width * 0.35 * i - base_up * height * 0.12 * i)
	bolts.append({"points": points, "branch": branch, "life": rng.randf_range(0.25, 0.5), "far": far})

func _arm_thunder(far: bool) -> void:
	thunder_pending = true
	thunder_far = far
	thunder_wait = -1.0

func _schedule_thunder(distance: float) -> void:
	thunder_distance = distance
	thunder_wait = distance / SOUND_SPEED

## Mais perto = mais alto e com o estalo seco; o distante é só o ronco abafado.
func _play_thunder() -> void:
	thunder_pending = false
	# Raios vermelhos do kraken: ele tem os próprios sons (KrakenAudio), sem trovão de tempestade.
	if red > 0.05:
		return
	var sound := AudioStreamPlayer.new()
	if thunder_far:
		sound.stream = FAR[rng.randi() % FAR.size()]
		sound.volume_db = remap(thunder_distance, 200.0, 450.0, -10.0, -16.0)
	elif thunder_distance < 210.0:
		sound.stream = CRACK[rng.randi() % CRACK.size()]
		sound.volume_db = -6.0
	else:
		sound.stream = NEAR[rng.randi() % NEAR.size()]
		sound.volume_db = remap(thunder_distance, 210.0, 320.0, -7.0, -11.0)
	sound.pitch_scale = rng.randf_range(0.92, 1.05)
	add_child(sound)
	sound.play()
	sound.finished.connect(sound.queue_free)
	print("THUNDER %s %.0f m (%.2f s after the flash)" % ["far" if thunder_far else "near", thunder_distance, thunder_distance / SOUND_SPEED])

func _draw() -> void:
	lines.clear_surfaces()
	if bolts.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	lines.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in bolts:
		var a := clampf(b.life / 0.25, 0.0, 1.0) * (0.55 if b.far else 1.0)
		_ribbon(b.points, eye, 0.9, Color(0.55, 0.8, 1.0, 0.35 * a).lerp(Color(1.0, 0.2, 0.15, 0.4 * a), red))
		_ribbon(b.points, eye, 0.22, Color(0.95, 1.0, 1.0, a).lerp(Color(1.0, 0.6, 0.5, a), red))
		_ribbon(b.branch, eye, 0.14, Color(0.85, 0.95, 1.0, 0.8 * a).lerp(Color(1.0, 0.35, 0.3, 0.8 * a), red))
	lines.surface_end()

func _ribbon(points: Array, eye: Vector3, width: float, color: Color) -> void:
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var side := (b - a).cross(eye - a).normalized() * width * (eye.distance_to(a) / 100.0)
		for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
			lines.surface_set_color(color)
			lines.surface_add_vertex(v)
