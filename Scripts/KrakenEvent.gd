extends Node3D

## Encontro com o kraken (raríssimo: 2% dos encontros com silhuetas, SeaShadows.gd), só em mar
## aberto. Roteiro (sons e trilha entram depois):
## 1. Aparece o aviso e logo a sombra IMENSA (do tamanho de todo o alcance dos tentáculos) surge
##    atrás do barco e vem por baixo dele: lenta, mas não demora (besta ancestral colossal).
## 2. Quando a METADE da sombra chega ao barco, ele trava (não anda mais); o mar escurece rápido e
##    a sombra some (ele mudou de posição); as nuvens se fecham num vórtice em cima (estudo do
##    Thiago Muniz), raios vermelhos, e os tentáculos (grossos, com colisão) sobem um depois do
##    outro, em cânone, em volta do barco.
## 3. REDEMOINHO: o barco é solto quando o funil começa (sem surfe nem pulos, para não quicar).
##    Para fora dos tentáculos fica a BEIRADA: ali a correnteza segura até o IMPULSO, e só a barra de
##    AÇÃO (Espaço, FOGO ou toques na tela no celular) dá o arranque final. Se a barra esvazia, volta
##    a lutar contra o redemoinho.
##    Quem chega ao miolo naufraga (cartão do easter egg) e volta ao mar longe dali.

## Tentáculo e boca do Meshy riggados/animados no Blender (Tools/rig_creatures_blender.py). Tentáculo:
## base em y 0, 1 m de altura (escala = altura), ventosas para -Z (o nó olha para o centro: ventosas
## para dentro do redemoinho); clipe Thrash (chicoteia em arcos e enrola a ponta). Boca: 20 m, dentes para +Y.
const TENTACLE_SCENE := preload("res://Assets/Optimized/Creatures/tentacle.glb")
## Boca nova (Meshy "rigready volumetric", 9 presas) riggada no Blender: Tools/rig_kraken_maw_blender.py.
const MAW_SCENE := preload("res://Assets/Creatures/kraken_maw_rigged.glb")
const WHIRL := preload("res://Shaders/kraken_whirlpool.gdshader")
const VORTEX := preload("res://Shaders/toon_vortex.gdshader")
const HudTheme = preload("res://Scripts/UI/HudTheme.gd")
const EasterEgg = preload("res://Scripts/UI/EasterEggScreen.gd")

enum Phase { IDLE, OMEN, RISE, PULL, LEAVE }

## Velocidade da sombra em relação ao barco (m/s a mais) e quanto ela nasce atrás.
@export var shadow_overtake := 6.0
## Tentáculos em cânone "natural": grupos de 1 a 3 saindo quase juntos, intervalos irregulares
## (ex.: 1, 3, 2, 1, 1), cada um sobe em tentacle_rise s.
@export var tentacle_interval := 0.9
@export var tentacle_rise := 1.8
@export var rise_seconds := 9.0
@export var whirl_radius := 180.0
@export var funnel_depth := 26.0
@export var core_radius := 12.0
## Anel dos tentáculos e a beirada (zona da barra de ação) logo depois deles.
@export var tentacle_ring := Vector2(85.0, 135.0)
@export var tentacle_height := Vector2(45.0, 70.0)
@export var action_radius := 140.0
@export var escape_radius := 195.0
@export var abort_distance := 210.0
@export var cooldown_seconds := 420.0
@export var tentacle_count := 8
## Boca (dentes) com este diâmetro no fundo do funil.
@export var maw_diameter := 42.0
## Pancada: de tempos em tempos um tentáculo tomba na direção do barco e bate na água.
@export var slam_every := Vector2(5.0, 11.0)
## Sombra: a maior do jogo (cobre todo o alcance dos tentáculos).
const SHADOW_SIZE := Vector2(360.0, 140.0)
const SPLASH_SFX := preload("res://Assets/Sound/SFX/WATER SPLASH CANON BALL SFX.wav")
var slam_push := Vector3.ZERO

var world: Node3D
var phase := Phase.IDLE
var timer := 0.0
var cooldown := 0.0
var center := Vector3.ZERO
var strength := 0.0
var shadow_pos := Vector3.ZERO
var shadow_dir := Vector3.FORWARD
var shadow_opacity := 0.0
var tentacles: Array[Dictionary] = []
var whirl: MeshInstance3D
var whirl_material: ShaderMaterial
var vortex: MeshInstance3D
var vortex_material: ShaderMaterial
var teeth: Node3D
var shadow: Array = []
var event: Dictionary = {}
var lost := false
var aborted := false
## Barra de ação (0..1) e arranque final.
var action := 0.0
var breakout := 0.0
var action_layer: CanvasLayer
var action_bar: ProgressBar
var action_label: Label
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

func can_start() -> bool:
	if phase != Phase.IDLE or cooldown > 0.0 or world == null:
		return false
	var ship: Node3D = world.ship
	if not ship.enabled:
		return false
	var naval: Node = world.get("naval")
	if naval and naval.get("time_attack_running"):
		return false
	var ghost: Node = world.get("ghost_ship")
	if ghost and ghost.get("chasing"):
		return false
	var weather: Node = world.get("weather")
	if weather == null:
		return false
	return weather._island_distance(ship.global_position.normalized()) > 260.0 and world.ocean.badness_at(ship.global_position) < 0.5

## Espaço/FOGO viram a barra de ação na beirada do redemoinho (NavalGame.begin_aim).
func action_active() -> bool:
	return phase == Phase.PULL and _ship_radius() > action_radius and breakout <= 0.0

func action_press() -> void:
	action = minf(1.0, action + 0.085)
	if action >= 1.0:
		breakout = 2.6
		world.hud.show_toast("Arranque!")

func _ship_radius() -> float:
	var up := center.normalized()
	return (world.ship.global_position - center).slide(up).length()

func start() -> void:
	var ship: Node3D = world.ship
	var up: Vector3 = ship.global_position.normalized()
	var forward: Vector3 = ship.heading.slide(up).normalized()
	# A sombra nasce atrás do barco (a cabeça logo atrás da popa) e vem por baixo dele.
	shadow_pos = (ship.global_position - forward * (SHADOW_SIZE.x * 0.5 + 15.0)).normalized() * world.planet_radius
	shadow_dir = forward
	shadow_opacity = 0.0
	center = ship.global_position
	phase = Phase.OMEN
	timer = 0.0
	strength = 0.0
	action = 0.0
	breakout = 0.0
	lost = false
	aborted = false
	event = {"center": center, "radius": 260.0, "badness": 0.0}
	world.weather.sea_events.append(event)
	var shadows: Node = world.sea_life.get("sea_shadows")
	if shadows:
		shadow = shadows.make_plate(4, SHADOW_SIZE.x, SHADOW_SIZE.y)
	world.hud.show_toast("O mar ficou estranho… algo enorme vem por baixo")
	print("KRAKEN omen")

func _surface_basis(up: Vector3) -> Basis:
	var x := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	return Basis(x, up, x.cross(up).normalized())

## Monta tentáculos, redemoinho, vórtice de nuvens e dentes em volta de "center".
func _build_arena() -> void:
	var up := center.normalized()
	var basis := _surface_basis(up)
	tentacles.clear()
	var order: Array = range(tentacle_count)
	order.shuffle()
	var delays := _canon_delays(tentacle_count)
	for i in tentacle_count:
		var a := TAU * i / tentacle_count + rng.randf_range(-0.15, 0.15)
		var dist := rng.randf_range(tentacle_ring.x, tentacle_ring.y)
		var height := rng.randf_range(tentacle_height.x, tentacle_height.y)
		# O tentáculo novo (épico) tem ~0,35 de largura por 1 de altura: raio de colisão acompanha a escala.
		var radius := height * 0.16
		var node := TENTACLE_SCENE.instantiate() as Node3D
		node.top_level = true
		node.visible = false
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		var player := node.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player and player.has_animation("Thrash"):
			player.get_animation("Thrash").loop_mode = Animation.LOOP_LINEAR
			# Cada um no seu ritmo (antes todos chicoteavam igual).
			player.speed_scale = rng.randf_range(0.65, 1.35)
		var offset: Vector3 = basis.x * cos(a) * dist + basis.z * sin(a) * dist
		tentacles.append({"node": node, "player": player, "offset": offset, "height": height, "radius": radius,
			"delay": delays[order[i]], "facing": -offset.normalized(), "rise": 0.0, "emerged": false,
			"phase": rng.randf_range(0.0, TAU), "sway_speed": rng.randf_range(0.25, 0.55),
			"slam": -1.0, "slam_dir": Vector3.ZERO, "slam_hit": false, "next_slam": rng.randf_range(slam_every.x, slam_every.y)})
	whirl_material = ShaderMaterial.new()
	whirl_material.shader = WHIRL
	# Acima do mar perto do barco (o patch de ondas é transparente e cobria o redemoinho: o efeito
	# de água girando tinha sumido).
	whirl_material.render_priority = 20
	world.ocean.register_material(whirl_material)
	whirl = MeshInstance3D.new()
	whirl.mesh = _ring_mesh(whirl_radius, 28, 96)
	whirl.material_override = whirl_material
	whirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	whirl.top_level = true
	add_child(whirl)
	vortex_material = ShaderMaterial.new()
	vortex_material.shader = VORTEX
	vortex_material.render_priority = 3
	vortex_material.set_shader_parameter("rim_amount", 0.8)
	vortex_material.set_shader_parameter("twist", 1.6)
	vortex_material.set_shader_parameter("rips", 0.6)
	vortex_material.set_shader_parameter("sphere_radius", world.planet_radius + 85.0)
	vortex = MeshInstance3D.new()
	vortex.mesh = _ring_mesh(420.0, 28, 96)
	vortex.material_override = vortex_material
	vortex.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vortex.top_level = true
	add_child(vortex)
	teeth = _build_teeth()
	add_child(teeth)
	_build_action_ui()

func _physics_process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	if phase == Phase.IDLE:
		return
	timer += delta
	var ship: Node3D = world.ship
	var thunder: Node = world.weather.get("thunder")
	match phase:
		Phase.OMEN:
			# A sombra vem por baixo, um pouco mais rápida que o barco, no rumo dele.
			var up := shadow_pos.normalized()
			var to_ship: Vector3 = (ship.global_position - shadow_pos).slide(up)
			var ship_dir: Vector3 = (ship.heading as Vector3).slide(up).normalized()
			var speed := absf(float(ship.measured_speed)) + shadow_overtake
			var aim := (to_ship.normalized() * 0.6 + ship_dir * 0.4).normalized() if to_ship.length() > 1.0 else ship_dir
			shadow_dir = shadow_dir.slerp(aim, 1.0 - exp(-0.8 * delta)).normalized()
			shadow_pos = (shadow_pos + shadow_dir * speed * delta).normalized() * world.planet_radius
			shadow_opacity = minf(0.95, shadow_opacity + delta / 3.0)
			event.center = shadow_pos
			event.badness = 0.6 * shadow_opacity
			# Metade da sombra chegou ao barco: trava e começa.
			if to_ship.dot(shadow_dir) < 2.0:
				# Miolo à frente: o barco fica dentro do anel de tentáculos, longe da boca.
				center = (ship.global_position + ship_dir * 60.0).normalized() * world.planet_radius
				event.center = center
				ship.held = true
				_build_arena()
				phase = Phase.RISE
				timer = 0.0
				world.hud.show_toast("O Kraken!")
				print("KRAKEN rise")
			elif timer > 60.0:
				aborted = true
				print("KRAKEN aborted")
				_leave()
		Phase.RISE:
			# O mar escurece rápido e a sombra some (ele mudou de posição); o barco fica preso.
			ship.held = true
			shadow_opacity = maxf(0.0, shadow_opacity - delta / 1.5)
			event.badness = lerpf(0.6, 2.2, smoothstep(0.0, 2.0, timer))
			if thunder:
				thunder.red = 1.0
			if timer > rise_seconds:
				phase = Phase.PULL
				timer = 0.0
				ship.held = false
				ship.calm_ride = true
				world.hud.show_toast("Redemoinho! Fuja para fora: depois dos tentáculos, aperte Espaço sem parar")
				print("KRAKEN pull")
		Phase.PULL:
			strength = smoothstep(0.0, 4.0, timer)
			event.badness = 2.4
			ship.ignore_wind = true
			var up := center.normalized()
			var rel: Vector3 = (ship.global_position - center).slide(up)
			var r := rel.length()
			var radial := rel / maxf(r, 0.01)
			var tangent := up.cross(radial).normalized()
			# Puxão entre o cruzeiro e o BURST: só navegando (15 m/s) o barco desce; com BURST a cada
			# recarga (30 m/s por 1,5 s a cada 5 s: ~24 m/s na média) sai devagar até a beirada.
			var inflow := lerpf(15.5, 19.0, smoothstep(0.0, 25.0, timer)) * strength * (1.0 + 0.12 * (1.0 - smoothstep(core_radius, whirl_radius, r)))
			# Beirada: a correnteza segura até o impulso; só o arranque da barra de ação passa.
			inflow += 16.0 * smoothstep(action_radius, action_radius + 22.0, r) * strength
			var swirl := 13.0 * strength * (1.0 - smoothstep(whirl_radius, escape_radius, r) * 0.6)
			var push := -radial * inflow + tangent * swirl + slam_push
			slam_push = slam_push.lerp(Vector3.ZERO, 1.0 - exp(-2.5 * delta))
			_update_slams(delta)
			if breakout > 0.0:
				breakout -= delta
				push = radial * 22.0 + tangent * swirl * 0.3
				action = maxf(0.0, action - delta * 0.2)
			elif r > action_radius:
				# Barra esvazia sozinha: se parar de apertar, volta a lutar.
				action = maxf(0.0, action - delta * 0.32)
			else:
				action = maxf(0.0, action - delta * 1.2)
			ship.external_velocity = push
			var twist := deg_to_rad(14.0) * strength * (1.0 - smoothstep(whirl_radius * 0.6, escape_radius, r))
			if breakout <= 0.0:
				ship.heading = (ship.heading as Vector3).slerp(tangent, 1.0 - exp(-twist * delta)).normalized()
			if r > escape_radius:
				_finish(false)
			elif r < core_radius:
				_finish(true)
		Phase.LEAVE:
			strength = maxf(0.0, strength - delta / 5.0)
			shadow_opacity = maxf(0.0, shadow_opacity - delta / 3.0)
			event.badness = maxf(0.0, float(event.badness) - delta * 0.5)
			if thunder:
				thunder.red = maxf(0.0, float(thunder.red) - delta / 5.0)
			if timer > 6.0:
				_cleanup()
				return
	_collide_tentacles()
	_animate()

## Colisão com os tentáculos: o barco não atravessa; ao encostar é empurrado para fora e perde
## velocidade. Feita aqui (e não com corpo físico, que arremessava o barco).
func _collide_tentacles() -> void:
	var ship: Node3D = world.ship
	for t in tentacles:
		if float(t.rise) < 0.4:
			continue
		var reach := float(t.radius) + 0.6 + 2.6
		var base: Vector3 = (center + t.offset).normalized() * world.planet_radius
		var away: Vector3 = (ship.global_position - base).slide(ship.global_position.normalized())
		var d := away.length()
		if d < reach:
			var up: Vector3 = ship.global_position.normalized()
			var out: Vector3 = away / d if d > 0.01 else ship.heading.cross(up).normalized()
			ship.global_position += out * (reach - d)
			# Tira só a parte da velocidade que vai contra o tentáculo: o barco desliza em volta.
			var into := -(ship.heading as Vector3).dot(out)
			if into > 0.0:
				ship.heading = ((ship.heading as Vector3) + out * into).slide(up).normalized()
				ship.drive_speed *= 0.92

func _animate() -> void:
	var night: float = world.clock.night_at(world.ship.global_position)
	if not shadow.is_empty():
		var node: MeshInstance3D = shadow[0]
		var up := shadow_pos.normalized()
		node.global_transform = Transform3D(Basis.looking_at(shadow_dir.slide(up).normalized(), up), up * world.planet_radius)
		var material: ShaderMaterial = shadow[1]
		material.set_shader_parameter("opacity", shadow_opacity)
		material.set_shader_parameter("swim", Time.get_ticks_msec() * 0.0008)
		material.set_shader_parameter("wiggle", 0.5)
		world.sea_life.sea_shadows.push_patch(material)
	if phase == Phase.OMEN or whirl == null:
		_update_action_ui()
		return
	var up := center.normalized()
	var basis := _surface_basis(up)
	# O funil e as ondas calmas lá dentro vêm do próprio mar (ocean_eval).
	world.ocean.set_whirl(center, whirl_radius * 1.05, funnel_depth * strength)
	whirl.global_transform = Transform3D(basis.rotated(up, timer * 0.15), up * world.planet_radius)
	whirl_material.set_shader_parameter("strength", strength)
	whirl_material.set_shader_parameter("night", night)
	world.sea_life.sea_shadows.push_patch(whirl_material)
	# Nuvens se fechando no céu (olho diminui na subida, abre de novo no fim).
	var close := smoothstep(0.0, rise_seconds * 0.8, timer) if phase == Phase.RISE else (1.0 if phase == Phase.PULL else strength)
	vortex.global_transform = Transform3D(basis.rotated(up, -timer * 0.05), up * (world.planet_radius + 85.0))
	vortex_material.set_shader_parameter("eye", lerpf(0.85, 0.16, close))
	vortex_material.set_shader_parameter("strength", clampf(close * 1.4, 0.0, 1.0) if phase != Phase.LEAVE else strength)
	vortex_material.set_shader_parameter("night", night)
	vortex_material.set_shader_parameter("flash", float(world.get("sky_flash")) if world.get("sky_flash") != null else 0.0)
	var rise_time := timer if phase == Phase.RISE else (rise_seconds + timer if phase == Phase.PULL else 0.0)
	for t in tentacles:
		var rise: float
		if phase == Phase.LEAVE:
			rise = minf(float(t.rise), strength)
		else:
			rise = smoothstep(float(t.delay), float(t.delay) + tentacle_rise, rise_time)
		t.rise = rise
		var base: Vector3 = (center + t.offset).normalized()
		var water: Vector3 = world.ocean.surface_at(base * world.planet_radius)
		var facing: Vector3 = (t.facing as Vector3).slide(base).normalized()
		var b := Basis.looking_at(facing, base)
		# Vida própria: torce devagar no eixo e balança para os lados, cada um fora de fase.
		var clock := Time.get_ticks_msec() * 0.001
		var ph := float(t.phase)
		var sp := float(t.sway_speed)
		b = Basis(base, sin(clock * sp + ph) * 0.35) * b
		var side: Vector3 = base.cross(facing).normalized()
		b = Basis(side, sin(clock * sp * 1.3 + ph * 2.0) * 0.14) * Basis(facing, sin(clock * sp * 0.9 + ph) * 0.1) * b
		# Pancada: tomba da base na direção do barco e volta devagar.
		var slam := float(t.slam)
		if slam >= 0.0:
			var dir: Vector3 = (t.slam_dir as Vector3).slide(base).normalized()
			var axis := base.cross(dir).normalized()
			var tip := smoothstep(0.0, 0.45, slam) * (1.0 - smoothstep(0.75, 2.2, slam))
			b = Basis(axis, tip * 1.25) * b
		var node: Node3D = t.node
		node.visible = rise > 0.01
		# De pé, ~14% do tentáculo continua embaixo d'água: a base nunca aparece (ilusão de que ele
		# segue fundo abaixo da superfície).
		var sunk := float(t.height) * 0.14
		node.global_transform = Transform3D(b.scaled(Vector3.ONE * float(t.height)), water + base * lerpf(-float(t.height) - sunk, -sunk, rise))
		# Chicoteando (Thrash em loop) desde que rompe a água; cada um com a sua fase.
		var player: AnimationPlayer = t.player
		if player and node.visible and not t.emerged:
			t.emerged = true
			player.play("Thrash")
			player.seek(rng.randf() * player.current_animation_length, true)
	var bottom: float = world.planet_radius + float(world.ocean.height_at(center)) - 0.5
	teeth.visible = strength > 0.02
	var maw_scale := float(teeth.get_meta("fit_scale", 1.0))
	teeth.global_transform = Transform3D(basis.rotated(up, -timer * 0.15).scaled(Vector3.ONE * maw_scale), up * (bottom + lerpf(-8.0, 1.0, strength)))
	_update_action_ui()

func _build_action_ui() -> void:
	if action_layer:
		return
	action_layer = CanvasLayer.new()
	action_layer.layer = 15
	add_child(action_layer)
	var colors := HudTheme.palette(0.0)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.68
	box.anchor_bottom = 0.68
	box.offset_left = -170
	box.offset_right = 170
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	action_layer.add_child(box)
	action_label = Label.new()
	action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_label.add_theme_font_override("font", HudTheme.font("label"))
	action_label.add_theme_font_size_override("font_size", 15)
	action_label.add_theme_color_override("font_color", colors.ink)
	action_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	action_label.add_theme_constant_override("outline_size", 6)
	box.add_child(action_label)
	action_bar = ProgressBar.new()
	action_bar.max_value = 1.0
	action_bar.show_percentage = false
	action_bar.custom_minimum_size = Vector2(340, 16)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.1, 0.75)
	bg.border_color = Color(1, 1, 1, 0.5)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.35, 0.25)
	action_bar.add_theme_stylebox_override("background", bg)
	action_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(action_bar)
	action_layer.visible = false

func _update_action_ui() -> void:
	if action_layer == null:
		return
	var show := phase == Phase.PULL and _ship_radius() > action_radius - 6.0
	action_layer.visible = show
	if not show:
		return
	var touch := DisplayServer.is_touchscreen_available()
	action_label.text = "ARRANQUE!" if breakout > 0.0 else ("Toque na tela sem parar!" if touch else "Aperte ESPAÇO sem parar!")
	action_bar.value = 1.0 if breakout > 0.0 else action

func _finish(sank: bool) -> void:
	lost = sank
	print("KRAKEN %s" % ("sank" if sank else "escaped"))
	_leave()
	if sank:
		# Pego: o barco para ali (não continua descendo no funil) até o cartão fechar.
		world.ship.held = true
		world.ship.drive_speed = 0.0
	if not sank:
		world.hud.show_toast("Você escapou do Kraken!")
		return
	var days: float = world.adventure_seconds / maxf(float(world.clock.day_duration_seconds), 1.0)
	world.easter_egg.show_card(
		"Easter egg · segurança digital",
		"O Kraken levou o seu tesouro",
		[
			"Todo dia alguém cai num golpe: phishing, link falso, senha vazada. Os dados que a gente guarda como tesouro afundam por falta de informação sobre segurança na rede.",
			"Me segue nas redes pra acompanhar o que eu estudo de cibersegurança e boas práticas, e não naufragar nas suas aventuras online.",
		],
		[["Navegou", EasterEgg.format_duration(world.adventure_seconds)], ["Distância", EasterEgg.format_distance(world.distance_sailed)], ["Dias no mar", "%.1f" % days]],
		"Voltar ao mar",
		_respawn_after_wreck)

func _leave() -> void:
	slam_push = Vector3.ZERO
	phase = Phase.LEAVE
	timer = 0.0
	breakout = 0.0
	world.ship.external_velocity = Vector3.ZERO
	world.ship.ignore_wind = false
	world.ship.held = false
	world.ship.calm_ride = false

## Celular: tocar na tela (em qualquer lugar) também enche a barra de ação.
func _input(event: InputEvent) -> void:
	if not action_active():
		return
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		action_press()

## Depois do naufrágio o barco volta ao mar longe do redemoinho, de proa para fora.
func _respawn_after_wreck() -> void:
	var ship: Node3D = world.ship
	var up := center.normalized()
	var out: Vector3 = (ship.global_position - center).slide(up)
	out = out.normalized() if out.length() > 0.1 else _surface_basis(up).x
	var pos: Vector3 = world.ocean.surface_at((center + out * (escape_radius + 60.0)).normalized() * world.planet_radius)
	var new_up := pos.normalized()
	var forward := out.slide(new_up).normalized()
	ship.heading = forward
	ship.drive_speed = 0.0
	ship.external_velocity = Vector3.ZERO
	ship.global_transform = Transform3D(Basis(forward.cross(new_up).normalized(), new_up, -forward), pos)
	ship.held = false

func _cleanup() -> void:
	phase = Phase.IDLE
	cooldown = cooldown_seconds
	world.weather.sea_events.erase(event)
	world.ocean.set_whirl(Vector3.ZERO, 0.0, 0.0)
	var thunder: Node = world.weather.get("thunder")
	if thunder:
		thunder.red = 0.0
	for t in tentacles:
		(t.node as Node).queue_free()
	tentacles.clear()
	if is_instance_valid(whirl):
		world.ocean.materials.erase(whirl_material)
		whirl.queue_free()
	whirl = null
	if is_instance_valid(vortex):
		vortex.queue_free()
	vortex = null
	if is_instance_valid(teeth):
		teeth.queue_free()
	teeth = null
	if action_layer:
		action_layer.queue_free()
	action_layer = null
	var shadows: Node = world.sea_life.get("sea_shadows")
	if shadows and not shadow.is_empty():
		shadows.free_plate(shadow)
	shadow = []

## Duas fileiras de dentes em volta de uma boca escura, inclinados para dentro.
func _build_teeth() -> Node3D:
	var root := MAW_SCENE.instantiate() as Node3D
	root.name = "KrakenTeeth"
	root.top_level = true
	root.visible = false
	var box := AABB()
	var first := true
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var b: AABB = (mesh as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	# Boca colossal: escala para maw_diameter no fundo do funil.
	root.set_meta("fit_scale", maw_diameter / maxf(maxf(box.size.x, box.size.z), 0.01))
	# Presas mordendo em onda em volta do anel (clipe cíclico "Gnash").
	var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player and player.has_animation("Gnash"):
		player.get_animation("Gnash").loop_mode = Animation.LOOP_LINEAR
		player.play("Gnash")
	return root

## Atrasos de subida em grupos de 1 a 3 (cânone natural: 1, 3, 2, 1…), espaçamentos irregulares.
func _canon_delays(count: int) -> Array[float]:
	var delays: Array[float] = []
	var t := 0.8
	while delays.size() < count:
		var group := mini(rng.randi_range(1, 3), count - delays.size())
		for k in group:
			delays.append(t + rng.randf_range(0.0, 0.35))
		t += rng.randf_range(0.6, 1.5)
	return delays

## Pancadas: cada tentáculo de pé conta o seu tempo; quando zera e o barco está ao alcance, tomba
## na direção dele. No impacto: onda, borrifo, som e empurrão se pegou perto.
func _update_slams(delta: float) -> void:
	var ship: Node3D = world.ship
	for t in tentacles:
		if float(t.rise) < 0.95:
			continue
		var base: Vector3 = (center + t.offset).normalized() * world.planet_radius
		var to_ship: Vector3 = (ship.global_position - base).slide(base.normalized())
		if float(t.slam) < 0.0:
			t.next_slam = float(t.next_slam) - delta
			if float(t.next_slam) <= 0.0 and to_ship.length() < float(t.height) * 1.5:
				t.slam = 0.0
				t.slam_dir = to_ship.normalized()
				t.slam_hit = false
			continue
		t.slam = float(t.slam) + delta
		if not t.slam_hit and float(t.slam) >= 0.42:
			t.slam_hit = true
			var dir: Vector3 = t.slam_dir
			var impact: Vector3 = world.ocean.surface_at(base + dir * float(t.height) * 0.85)
			world.ocean.touch(impact, 1.4, 6.0)
			_splash(impact, float(t.height) * 0.12)
			var miss: float = (ship.global_position - impact).length()
			if miss < 14.0:
				slam_push += dir * lerpf(16.0, 5.0, miss / 14.0)
				ship.drive_speed *= 0.5
		if float(t.slam) > 2.4:
			t.slam = -1.0
			t.next_slam = rng.randf_range(slam_every.x, slam_every.y)

func _splash(at: Vector3, size: float) -> void:
	var fx := GPUParticles3D.new()
	fx.one_shot = true
	fx.explosiveness = 0.95
	fx.amount = 90
	fx.lifetime = 1.8
	fx.local_coords = false
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = size
	motion.direction = Vector3.UP
	motion.spread = 40.0
	motion.initial_velocity_min = 8.0
	motion.initial_velocity_max = 18.0
	motion.gravity = -at.normalized() * 14.0
	motion.scale_min = 1.0
	motion.scale_max = 2.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.95))
	fade.set_color(1, Color(0.85, 0.92, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	motion.color_ramp = ramp
	fx.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.vertex_color_use_as_albedo = true
	paint.render_priority = 21
	# Gota redonda e macia (sem textura a partícula saía como um quadrado branco).
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	soft.add_point(0.45, Color(1, 1, 1, 0.8))
	var drop := GradientTexture2D.new()
	drop.gradient = soft
	drop.fill = GradientTexture2D.FILL_RADIAL
	drop.fill_from = Vector2(0.5, 0.5)
	drop.fill_to = Vector2(0.5, 0.0)
	paint.albedo_texture = drop
	quad.material = paint
	fx.draw_pass_1 = quad
	fx.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 60, 80))
	fx.top_level = true
	add_child(fx)
	fx.global_position = at
	fx.emitting = true
	var sound := AudioStreamPlayer3D.new()
	sound.stream = SPLASH_SFX
	sound.pitch_scale = 0.55
	sound.unit_size = 40.0
	sound.max_distance = 400.0
	sound.volume_db = 4.0
	sound.top_level = true
	add_child(sound)
	sound.global_position = at
	sound.play()
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if is_instance_valid(fx): fx.queue_free()
		if is_instance_valid(sound): sound.queue_free())

## Anel (redemoinho / vórtice de nuvens): UV.x = ângulo, UV.y = raio relativo.
func _ring_mesh(radius: float, rings: int, segments: int) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rings + 1:
		var r := pow(float(j) / rings, 1.4)
		for i in segments + 1:
			var a := TAU * i / segments
			tool.set_uv(Vector2(float(i) / segments, r))
			tool.set_normal(Vector3.UP)
			tool.add_vertex(Vector3(cos(a) * r * radius, 0.0, sin(a) * r * radius))
	var row := segments + 1
	for j in rings:
		for i in segments:
			var v := j * row + i
			for k in [v, v + 1, v + row, v + 1, v + row + 1, v + row]:
				tool.add_index(k)
	return tool.commit()
