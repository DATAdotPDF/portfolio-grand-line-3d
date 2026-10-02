extends SceneTree

## Making-of "Grand Line" — reel de motion graphics pirata × cyber, gravado pelo Movie Maker.
## Tudo em sincronia com "Barnacle Reel 1" (≈143 BPM; 1 compasso = 4 batidas ≈ 1,68 s).
## Os SFX tocam aqui dentro (vão para o áudio do AVI); a música entra no ffmpeg (Web/make_making_of.ps1).
##   Godot.exe --path . --write-movie Builds/MakingOf/raw.avi --fixed-fps 30 --script res://Tests/making_of.gd

const FPS := 30.0
## Tempo da música escolhida (ver _initialize): batida, compasso e onde cai o 1º compasso.
var BEAT := 60.0 / 142.9
var BAR := BEAT * 4.0
var OFFSET := 0.0
var option := 1
const SCREEN := Vector2(1920, 1080)

const NAVY := Color("0a1120")
const DEEP := Color("060b16")
const GOLD := Color("e8c172")
const PARCH := Color("efe4cc")
const INK := Color("eef1f6")
const MIST := Color("8f9bb3")
const CYAN := Color("38f2ff")
const MAGENTA := Color("ff3d7f")
const RED := Color("ff4a4a")

## Real (git log): o diário de bordo do projeto.
const GIT_LOG := [
	"7759455  oceano Gerstner com patch local",
	"d2ab70d  Seagazer pass: água turquesa",
	"64014a9  canhão: só eixo vertical",
	"f3d57d7  jogo como página inicial",
	"a0f0c31  vela que enche, bandeira, farol aceso",
	"4eb01cf  linha d'água: -0.38 -> +0.05",
	"4950d03  navegador monta o .pck em partes",
	"0add081  mobile lite: 70 MB -> 20 MB",
	"c82fa63  gráficos adaptativos",
]

var world: Node3D
var overlay: CanvasLayer
var stage: Control
var grid: Control
var route: Control
var flash: ColorRect
var wipe: ColorRect
var post: ColorRect
var fonts := {}
var sounds := {}
var players: Array[AudioStreamPlayer] = []
var start_frame := 0
var rng := RandomNumberGenerator.new()

# ===================================================================================
# Componentes desenhados
# ===================================================================================

## Fundo: carta náutica cyber (grade de lat/long em ciano, linhas de onda, deriva lenta).
class Chart extends Control:
	var drift := 0.0
	var tint := Color("38f2ff")
	## Energia da música (0.4 calmo … 1.8 pico): velocidade da deriva e da poeira dourada.
	var energy := 1.0
	var dust: Array[Vector3] = []
	func _ready() -> void:
		var r := RandomNumberGenerator.new()
		r.seed = 11
		for i in range(70):
			dust.append(Vector3(r.randf() * 1920.0, r.randf() * 1080.0, r.randf_range(0.4, 1.4)))
	func _process(delta: float) -> void:
		drift += delta * 12.0 * energy
		for i in range(dust.size()):
			var d := dust[i]
			d.y -= d.z * 26.0 * energy * delta
			d.x += sin(drift * 0.02 + i) * 0.3
			if d.y < -10.0:
				d.y = 1090.0
			dust[i] = d
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0a1120"))
		var step := 96.0
		var off := fmod(drift, step)
		var x := -off
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(tint, 0.06), 1.0)
			x += step
		var y := fmod(drift * 0.5, step)
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(tint, 0.06), 1.0)
			y += step
		for i in range(5):
			var pts := PackedVector2Array()
			var base := size.y * (0.15 + i * 0.18)
			for k in range(0, 41):
				var px := size.x * k / 40.0
				pts.append(Vector2(px, base + sin(px * 0.006 + drift * 0.02 + i) * 14.0))
			draw_polyline(pts, Color("e8c172", 0.05), 2.0, true)
		for d in dust:
			draw_circle(Vector2(d.x, d.y), 1.2 + d.z * 1.4, Color("e8c172", 0.10 + 0.12 * minf(energy, 1.5) * d.z))

## Mapa do tesouro: rota pontilhada entre os capítulos, X nas paradas, ping de sonar.
class Route extends Control:
	var stops := PackedVector2Array()
	var progress := 0.0
	var reached := 0
	var pings: Array = []
	func _process(delta: float) -> void:
		for p in pings:
			p.t += delta
		pings = pings.filter(func(p): return p.t < 1.4)
		queue_redraw()
	func ping(index: int) -> void:
		pings.append({"at": stops[index], "t": 0.0})
	func _draw() -> void:
		for i in range(stops.size() - 1):
			var amount := clampf(progress - i, 0.0, 1.0)
			if amount <= 0.0:
				break
			var a := stops[i]
			var b := stops[i + 1]
			var mid := (a + b) * 0.5 + Vector2(0, -90 if i % 2 == 0 else 90)
			var samples := 46
			for k in range(int(samples * amount)):
				var t := float(k) / samples
				var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
				if k % 2 == 0:
					draw_circle(p, 4.0, Color("e8c172"))
		for i in range(stops.size()):
			var c := stops[i]
			var lit := i < reached
			var col := Color("ff4a4a") if lit else Color("e8c172", 0.35)
			draw_line(c + Vector2(-18, -18), c + Vector2(18, 18), col, 6.0 if lit else 3.0, true)
			draw_line(c + Vector2(18, -18), c + Vector2(-18, 18), col, 6.0 if lit else 3.0, true)
		for p in pings:
			var k: float = p.t / 1.4
			draw_arc(p.at, 30.0 + k * 220.0, 0, TAU, 64, Color("38f2ff", 1.0 - k), 3.0, true)
			draw_arc(p.at, 20.0 + k * 120.0, 0, TAU, 64, Color("38f2ff", (1.0 - k) * 0.5), 2.0, true)

## Rosa dos ventos girando (pirata) com anel de radar (cyber).
class Compass extends Control:
	var spin := 0.0
	var radius := 300.0
	func _process(delta: float) -> void:
		spin += delta * 0.35
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		draw_arc(c, radius, 0, TAU, 96, Color("38f2ff", 0.35), 2.0, true)
		draw_arc(c, radius * 0.82, 0, TAU, 96, Color("e8c172", 0.25), 1.5, true)
		for i in range(72):
			var a := TAU * i / 72.0 + spin * 0.3
			var l := 18.0 if i % 9 == 0 else 7.0
			draw_line(c + Vector2.from_angle(a) * radius, c + Vector2.from_angle(a) * (radius - l), Color("38f2ff", 0.5), 2.0, true)
		var pts := PackedVector2Array()
		for i in range(16):
			var a := TAU * i / 16.0 + spin
			var r := radius * (0.72 if i % 4 == 0 else (0.4 if i % 2 == 0 else 0.16))
			pts.append(c + Vector2.from_angle(a) * r)
		draw_colored_polygon(pts, Color("e8c172", 0.18))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color("e8c172", 0.6), 2.0, true)
		# varredura do radar
		var sweep := spin * 2.2
		for k in range(18):
			draw_line(c, c + Vector2.from_angle(sweep - k * 0.02) * radius, Color("38f2ff", 0.18 * (1.0 - k / 18.0)), 3.0, true)

## Cantoneiras de HUD em volta de uma imagem.
class Brackets extends Control:
	var color := Color("38f2ff")
	func _draw() -> void:
		var l := 34.0
		var r := Rect2(Vector2.ZERO, size)
		for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var sx := 1.0 if corner.x <= r.position.x else -1.0
			var sy := 1.0 if corner.y <= r.position.y else -1.0
			draw_line(corner, corner + Vector2(l * sx, 0), color, 4.0)
			draw_line(corner, corner + Vector2(0, l * sy), color, 4.0)

# ===================================================================================
# Utilitários de tempo, som e animação
# ===================================================================================

func _initialize() -> void:
	# Opção 1: Barnacle Reel 1 · Opção 2: Open Sea Quest 2 (Godot ... -- option=2)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("option="):
			option = int(arg.trim_prefix("option="))
	if option == 2:
		BEAT = 60.0 / 143.2
		BAR = BEAT * 4.0
		OFFSET = 0.449
	call_deferred("run")

func now() -> float:
	return float(Engine.get_process_frames() - start_frame) / FPS

## Espera até o compasso n (em compassos desde o início da música).
func at_bar(n: float) -> void:
	while now() < OFFSET + n * BAR:
		await process_frame

func wait(seconds: float) -> void:
	var end := now() + seconds
	while now() < end:
		await process_frame

func sfx(name: String, db := 0.0, pitch := 1.0) -> void:
	for player in players:
		if not player.playing:
			player.stream = sounds[name]
			player.volume_db = db
			player.pitch_scale = pitch
			player.play()
			return

func tween() -> Tween:
	return stage.create_tween().set_parallel(true)

func label(text: String, font: String, size: int, color: Color, pos: Vector2, width := 1600.0, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", fonts[font])
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size = Vector2(width, size * 1.35)
	l.position = Vector2((SCREEN.x - width) * 0.5 if pos.x < 0.0 else pos.x, pos.y)
	l.pivot_offset = Vector2(width * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 0.0, size * 0.68)
	stage.add_child(l)
	return l

## Entrada com impacto: cresce de 1.9x para 1x, flash curto e tremida.
func slam(node: Control, sound := "boom", db := -4.0, shake_px := 14.0) -> void:
	node.scale = Vector2.ONE * 1.9
	node.modulate.a = 0.0
	var t := tween()
	t.tween_property(node, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 1.0, 0.12)
	if sound != "":
		sfx(sound, db)
	shake(shake_px)

func pop(node: Control, from := 0.4) -> void:
	node.scale = Vector2.ONE * from
	node.modulate.a = 0.0
	var t := tween()
	t.tween_property(node, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 1.0, 0.15)

func shake(px: float, seconds := 0.28) -> void:
	if px <= 0.0:
		return
	var t := stage.create_tween()
	var steps := 7
	for i in range(steps):
		var k := 1.0 - float(i) / steps
		t.tween_property(stage, "position", Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * px * k, seconds / steps)
	t.tween_property(stage, "position", Vector2.ZERO, 0.04)

func do_flash(color: Color, seconds := 0.35) -> void:
	flash.color = color
	flash.modulate.a = 1.0
	stage.create_tween().tween_property(flash, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_SINE)

func glitch(amount := 1.0, seconds := 0.4, sound := true) -> void:
	var material := post.material as ShaderMaterial
	material.set_shader_parameter("glitch", amount)
	stage.create_tween().tween_method(func(v): material.set_shader_parameter("glitch", v), amount, 0.0, seconds)
	if sound:
		sfx("glitch", -6.0)

## Texto de terminal digitado com cliques de teclado.
func typewrite(l: Label, cps := 34.0, clicks := true) -> void:
	l.visible_characters = 0
	l.modulate.a = 1.0
	var total := l.text.length()
	for i in range(total):
		if not is_instance_valid(l):
			return
		l.visible_characters = i + 1
		if clicks and i % 2 == 0 and l.text[i] != " ":
			sfx("key", -16.0, rng.randf_range(0.85, 1.25))
		await wait(1.0 / cps)

func fade_out_all(seconds := 0.25) -> void:
	for child in stage.get_children():
		if child is CanvasItem:
			stage.create_tween().tween_property(child, "modulate:a", 0.0, seconds)
	await wait(seconds)
	for child in stage.get_children():
		child.queue_free()

## Transição em onda: cobre a tela da esquerda para a direita e descobre em seguida.
func wave_wipe(color: Color, cover := 0.45, hold := 0.05, reveal := 0.45, sound := true) -> void:
	var material := wipe.material as ShaderMaterial
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("cover", 0.0)
	material.set_shader_parameter("reveal", 0.0)
	wipe.visible = true
	if sound:
		sfx("wave", -6.0)
	var t := stage.create_tween()
	t.tween_method(func(v): material.set_shader_parameter("cover", v), 0.0, 1.0, cover).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await wait(cover + hold)
	var r := stage.create_tween()
	r.tween_method(func(v): material.set_shader_parameter("reveal", v), 0.0, 1.0, reveal).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	r.tween_callback(func(): wipe.visible = false)

func picture(path: String, rect: Rect2, bracket_color := CYAN, whole := false) -> Control:
	var holder := Control.new()
	holder.position = rect.position
	holder.size = rect.size
	holder.pivot_offset = rect.size * 0.5
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	var tex := TextureRect.new()
	tex.texture = ImageTexture.create_from_image(image)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if whole else TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.clip_contents = true
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(tex)
	holder.clip_contents = true
	var b := Brackets.new()
	b.color = bracket_color
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(b)
	# linha de varredura (scanner) que passa uma vez
	var scan := ColorRect.new()
	scan.color = Color(CYAN, 0.55)
	scan.size = Vector2(rect.size.x, 3)
	holder.add_child(scan)
	stage.create_tween().tween_property(scan, "position:y", rect.size.y, 0.9).set_trans(Tween.TRANS_SINE)
	stage.add_child(holder)
	return holder

## Cartão voando para o lugar (rotação + escala), estilo "carta jogada na mesa".
func fly_in(node: Control, from_offset: Vector2, spin_deg: float) -> void:
	var target := node.position
	node.position = target + from_offset
	node.rotation_degrees = spin_deg
	node.scale = Vector2.ONE * 0.6
	node.modulate.a = 0.0
	var t := tween()
	t.tween_property(node, "position", target, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "rotation_degrees", 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 1.0, 0.15)

func terminal(rect: Rect2, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(DEEP, 0.94)
	box.border_color = Color(CYAN, 0.7)
	box.set_border_width_all(2)
	box.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", box)
	panel.position = rect.position
	panel.size = rect.size
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var bar := Label.new()
	bar.text = "●  ●  ●     " + title
	bar.add_theme_font_override("font", fonts.mono)
	bar.add_theme_font_size_override("font_size", 22)
	bar.add_theme_color_override("font_color", MIST)
	column.add_child(bar)
	stage.add_child(panel)
	pop(panel, 0.85)
	return column

func term_line(column: VBoxContainer, text: String, color := INK, size := 28) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", fonts.mono)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(l)
	return l

## Cartão de capítulo: a rota avança até o X do capítulo, ping de sonar, número + título.
func chapter(index: int, number: String, title: String, subtitle: String) -> void:
	route.visible = true
	route.modulate.a = 1.0
	sfx("doppler", -8.0)
	stage.create_tween().tween_property(route, "progress", float(index), BAR * 0.6).set_trans(Tween.TRANS_SINE)
	await wait(BAR * 0.6)
	route.reached = index + 1
	route.ping(index)
	sfx("ping", -4.0)
	var at: Vector2 = route.stops[index]
	var num := label(number, "mono", 30, CYAN, Vector2(at.x - 300, at.y + 46), 600)
	pop(num)
	var head := label(title, "black", 150, INK, Vector2(-1, 400))
	slam(head, "cannon_small", -6.0, 10.0)
	await wait(BEAT * 1.5)
	var sub := label(subtitle, "mono", 34, GOLD, Vector2(-1, 600))
	await typewrite(sub, 42.0)
	await wait(1.5)
	stage.create_tween().tween_property(route, "modulate:a", 0.0, 0.25)
	await fade_out_all(0.25)
	route.visible = false

## Legenda de gameplay: palavra grande à esquerda, sublinhado ciano que corre.
func live_caption(big: String, small: String) -> void:
	var l := label(big, "black", 120, INK, Vector2(120, 760), 1500, HORIZONTAL_ALIGNMENT_LEFT)
	l.add_theme_color_override("font_outline_color", Color(DEEP, 0.8))
	l.add_theme_constant_override("outline_size", 18)
	slam(l, "whoosh", -10.0, 0.0)
	var underline := ColorRect.new()
	underline.color = CYAN
	underline.position = Vector2(126, 930)
	underline.size = Vector2(0, 8)
	stage.add_child(underline)
	stage.create_tween().tween_property(underline, "size:x", 420.0, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	var s := label(small, "mono", 30, CYAN, Vector2(128, 952), 1500, HORIZONTAL_ALIGNMENT_LEFT)
	s.add_theme_color_override("font_outline_color", Color(DEEP, 0.9))
	s.add_theme_constant_override("outline_size", 10)
	typewrite(s, 45.0, false)

# ===================================================================================
# Montagem da cena
# ===================================================================================

func setup() -> void:
	rng.seed = 7
	var black := FontVariation.new()
	black.base_font = load("res://Assets/Fonts/Inter-Variable.ttf")
	black.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 900}
	fonts = {
		"serif": load("res://Assets/Fonts/IMFellEnglish-Italic.ttf"),
		"roman": load("res://Assets/Fonts/IMFellEnglish-Regular.ttf"),
		"sans": load("res://Assets/Fonts/Inter-Variable.ttf"),
		"black": black,
		"mono": load("res://Assets/Fonts/JetBrainsMono-Variable.ttf"),
	}
	var sfx_dir := "res://Assets/Sound/SFX/"
	sounds = {
		"cannon": load(sfx_dir + "CANNON SHOT SFX.wav"),
		"cannon_small": load(sfx_dir + "cannon.wav"),
		"doppler": load(sfx_dir + "CANON BALL DOPPLER SFX.wav"),
		"whoosh": load(sfx_dir + "CANON BALL DOPPLER SFX.wav"),
		"explosion": load(sfx_dir + "EXPLOSION SFX.wav"),
		"fuse": load(sfx_dir + "FUSE SFX.wav"),
		"bell": load(sfx_dir + "hitmarker_bell.wav"),
		"wood": load(sfx_dir + "WOOD IMPACT CANON BALL SFX.wav"),
		"splash": load(sfx_dir + "splash.wav"),
		"wave": load(sfx_dir + "OCEAN WAVE CRASH SFX.mp3"),
		"gulls": load(sfx_dir + "SEAGULLS OPEN SEA SFX 1.mp3"),
	}
	for synth in ["key", "glitch", "ping", "blip", "boom", "riser"]:
		sounds[synth] = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://Builds/MakingOf/sfx/%s.wav" % synth))
	# Áudio do mundo num barramento próprio (baixo); a música do jogo fica muda.
	var world_bus := AudioServer.bus_count
	AudioServer.add_bus(world_bus)
	AudioServer.set_bus_name(world_bus, "World")
	AudioServer.set_bus_volume_db(world_bus, -16.0)
	node_added.connect(_route_audio)
	for i in range(16):
		var p := AudioStreamPlayer.new()
		p.set_meta("reel", true)
		root.add_child(p)
		players.append(p)

	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = true
	root.add_child(world)
	world.clock.set_time(0.40, true)
	world.select_time("day")
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		_route_audio(n)
		stack.append_array(n.get_children())
	await process_frame
	await process_frame
	if world.graphics:
		world.graphics.set_mode("alto")
	if world.get("music"):
		world.music.stop()
		world.music.volume_db = -80.0

	overlay = CanvasLayer.new()
	overlay.layer = 200
	# O jogo usa tela virtual de 1152×648 (main_world.gd); o reel é desenhado em 1920×1080.
	overlay.scale = Vector2.ONE * (1152.0 / 1920.0)
	root.add_child(overlay)
	grid = Chart.new()
	grid.size = SCREEN
	overlay.add_child(grid)
	route = Route.new()
	route.size = SCREEN
	route.stops = PackedVector2Array([Vector2(180, 860), Vector2(520, 560), Vector2(860, 820), Vector2(1180, 520), Vector2(1480, 800), Vector2(1760, 470)])
	route.visible = false
	overlay.add_child(route)
	stage = Control.new()
	stage.size = SCREEN
	overlay.add_child(stage)
	wipe = ColorRect.new()
	wipe.size = SCREEN
	wipe.visible = false
	var wipe_material := ShaderMaterial.new()
	wipe_material.shader = _wipe_shader()
	wipe.material = wipe_material
	overlay.add_child(wipe)
	flash = ColorRect.new()
	flash.size = SCREEN
	flash.modulate.a = 0.0
	overlay.add_child(flash)
	var post_layer := CanvasLayer.new()
	post_layer.layer = 300
	root.add_child(post_layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var post_material := ShaderMaterial.new()
	post_material.shader = _post_shader()
	post.material = post_material
	post_layer.add_child(post)

func _route_audio(node: Node) -> void:
	if node.has_meta("reel"):
		return
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		node.bus = "World"

func _wipe_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.22, 0.95, 1.0, 1.0);
uniform float cover = 0.0;
uniform float reveal = 0.0;
void fragment() {
	float wave = sin(UV.y * 14.0 + TIME * 6.0) * 0.035 + sin(UV.y * 31.0 - TIME * 9.0) * 0.012;
	float front = cover * 1.25 - 0.1 + wave;
	float back = reveal * 1.25 - 0.1 + wave;
	float inside = step(UV.x, front) * step(back, UV.x);
	float foam = smoothstep(0.03, 0.0, abs(UV.x - front)) + smoothstep(0.03, 0.0, abs(UV.x - back)) * step(0.001, reveal);
	vec3 col = mix(tint.rgb, vec3(1.0), clamp(foam, 0.0, 1.0) * 0.85);
	COLOR = vec4(col, max(inside, clamp(foam, 0.0, 1.0)) * step(0.001, cover));
}
"""
	return s

func _post_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float glitch = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	float band = floor(uv.y * 22.0 + floor(TIME * 18.0) * 3.0);
	float r = fract(sin(band * 91.7 + floor(TIME * 24.0) * 12.3) * 43758.5);
	uv.x += (r > 0.55 ? (r - 0.55) * 0.22 : 0.0) * glitch;
	float ca = 0.0012 + 0.009 * glitch;
	vec3 c;
	c.r = texture(screen_tex, uv + vec2(ca, 0.0)).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - vec2(ca, 0.0)).b;
	c *= 0.95 + 0.05 * sin(SCREEN_UV.y * 1080.0 * 3.14159);
	float v = smoothstep(1.25, 0.3, length(SCREEN_UV - 0.5) * 1.55);
	c *= mix(0.72, 1.0, v);
	COLOR = vec4(c, 1.0);
}
"""
	return s

func show_grid(on: bool, seconds := 0.3) -> void:
	stage.create_tween().tween_property(grid, "modulate:a", 1.0 if on else 0.0, seconds)
	await wait(seconds)

# ===================================================================================
# Roteiro (em compassos)
# ===================================================================================

## Tempo de leitura: ~3 palavras/s + margem (nada some antes de dar para ler).
func read_time(text: String) -> float:
	return maxf(1.6, text.split(" ", false).size() / 3.0 + 0.9)

## Deriva lenta para cima enquanto o texto está na tela (nada fica parado).
func float_up(node: Control, seconds := 3.0, px := 16.0) -> void:
	stage.create_tween().tween_property(node, "position:y", node.position.y - px, seconds).set_trans(Tween.TRANS_SINE)

func say(text: String, font: String, size: int, color: Color, y: float, width := 1600.0) -> Label:
	var l := label(text, font, size, color, Vector2(-1, y), width)
	pop(l, 0.88)
	float_up(l, read_time(text) + 1.0)
	return l

func outlined(l: Label, px := 14) -> Label:
	l.add_theme_color_override("font_outline_color", Color(DEEP, 0.85))
	l.add_theme_constant_override("outline_size", px)
	return l

func set_energy(value: float) -> void:
	stage.create_tween().tween_property(grid, "energy", value, 2.0)

func run() -> void:
	await setup()
	await process_frame
	start_frame = Engine.get_process_frames()
	if option == 2:
		await run_option2()
		return
	grid.energy = 0.4

	# A · "OIE!" — calmo, a música ainda acordando (0–27 s) --------------------------------------
	sfx("gulls", -14.0)
	var hi := label("Oie!", "serif", 190, INK, Vector2(-1, 360))
	pop(hi, 0.8)
	float_up(hi, 3.0)
	await at_bar(1.75)
	await fade_out_all(0.4)
	var p1 := label("> fazer um site padrão e estático...", "mono", 46, CYAN, Vector2(220, 400), 1600, HORIZONTAL_ALIGNMENT_LEFT)
	await typewrite(p1, 24.0)
	await wait(0.4)
	var p2 := label("> não tinha nada a ver comigo.", "mono", 46, INK, Vector2(220, 480), 1600, HORIZONTAL_ALIGNMENT_LEFT)
	await typewrite(p2, 24.0)
	await at_bar(5.5)
	await fade_out_all(0.4)
	say("então meu currículo virou", "serif", 84, INK, 360)
	await wait(1.0)
	say("um planetinha à la One Piece.", "serif", 104, GOLD, 480)
	sfx("ping", -14.0)
	await at_bar(8.75)
	await fade_out_all(0.3)
	set_energy(0.7)
	wave_wipe(CYAN, 0.6, 0.05, 0.7)
	await wait(0.62)
	# Só a cena: o cartão de abertura do jogo competiria com as legendas.
	world.hud.visible = false
	grid.modulate.a = 0.0
	var frame := Brackets.new()
	frame.position = Vector2(40, 40)
	frame.size = SCREEN - Vector2(80, 80)
	stage.add_child(frame)
	var live := outlined(label("● AO VIVO  ·  GODOT 4.7", "mono", 26, RED, Vector2(80, 64), 900, HORIZONTAL_ALIGNMENT_LEFT), 8)
	pop(live)
	await wait(0.8)
	var pilot := outlined(label("você pilota uma chalupa pirata", "black", 64, INK, Vector2(110, 700), 1700, HORIZONTAL_ALIGNMENT_LEFT))
	pop(pilot, 0.9)
	await wait(1.2)
	var pilot2 := outlined(label("e navega até cinco ilhas:", "black", 64, INK, Vector2(110, 785), 1700, HORIZONTAL_ALIGNMENT_LEFT))
	pop(pilot2, 0.9)
	await wait(0.6)
	var names := ["SOBRE", "EXPERIÊNCIA", "FORMAÇÃO", "PROJETOS", "CONTATO"]
	var x := 116.0
	for n in names:
		var tag := outlined(label(n, "mono", 34, GOLD, Vector2(x, 890), 400, HORIZONTAL_ALIGNMENT_LEFT), 8)
		pop(tag)
		sfx("blip", -14.0)
		x += n.length() * 21.0 + 60.0
		await wait(BEAT)
	await at_bar(12.75)
	await fade_out_all(0.2)
	world.hud.visible = true
	grid.modulate.a = 1.0
	await at_bar(13.0)
	do_flash(PARCH, 0.5)
	sfx("cannon", -3.0)
	shake(20.0, 0.4)
	var compass := Compass.new()
	compass.size = Vector2(800, 800)
	compass.position = Vector2(560, 140)
	stage.add_child(compass)
	pop(compass, 0.3)
	var title := label("GRAND LINE", "black", 210, INK, Vector2(-1, 400))
	slam(title, "", 0.0, 0.0)
	await wait(BEAT * 2.0)
	var tag2 := label("MEU PORTFÓLIO  //  VERSÃO PIRATA", "mono", 36, CYAN, Vector2(-1, 650))
	await typewrite(tag2, 34.0)
	await at_bar(16.0)
	await fade_out_all(0.25)

	# B · POR QUE PIRATA? (27–40 s) -------------------------------------------------------------------
	set_energy(0.9)
	var why := label("// POR QUE PIRATA?", "mono", 32, CYAN, Vector2(-1, 140))
	pop(why)
	var career := [
		["> +10 anos de audiovisual", "(cruzes, véio)"],
		["> migrei pra Dados", ""],
		["> hoje estudo Cibersegurança", ""],
		["> e cresci jogando videogame e vendo anime", ""],
	]
	for i in range(career.size()):
		await at_bar(16.5 + i * 1.0)
		var line := label(career[i][0], "mono", 46, INK, Vector2(220, 270 + i * 100), 1500, HORIZONTAL_ALIGNMENT_LEFT)
		typewrite(line, 34.0)
		if career[i][1] != "":
			await wait(1.0)
			var aside := label(career[i][1], "serif", 46, GOLD, Vector2(1000, 266 + i * 100), 600, HORIZONTAL_ALIGNMENT_LEFT)
			pop(aside)
	await at_bar(20.75)
	await fade_out_all(0.25)
	say("One Piece numa interface profissional?", "serif", 78, INK, 380)
	await wait(1.8)
	var lindo := label("PERFEITAMENTE LINDO, RISOS.", "black", 92, GOLD, Vector2(-1, 520))
	slam(lindo, "wood", -8.0, 8.0)
	await at_bar(23.75)
	await fade_out_all(0.25)

	# C · A TRIPULAÇÃO (40–48 s) ----------------------------------------------------------------------
	var crew := label("// A TRIPULAÇÃO", "mono", 32, CYAN, Vector2(-1, 140))
	pop(crew)
	say("criamos juntos:", "serif", 76, INK, 220)
	var members := [["MESHY.AI", "modelos 3D", GOLD], ["CODEX", "agente de código · MCP", INK], ["CLAUDE", "agente de código · MCP", CYAN]]
	for i in range(members.size()):
		await at_bar(24.75 + i * 0.75)
		var cx := 160.0 + i * 560.0
		var box := Brackets.new()
		box.color = members[i][2]
		box.position = Vector2(cx, 380)
		box.size = Vector2(500, 260)
		box.pivot_offset = box.size * 0.5
		stage.add_child(box)
		pop(box, 0.6)
		var who := label(members[i][0], "black", 80, members[i][2], Vector2(cx, 440), 500)
		slam(who, "cannon_small", -12.0, 6.0)
		var role := label(members[i][1], "mono", 28, MIST, Vector2(cx, 560), 500)
		pop(role)
	await wait(1.0)
	var stack := label("+ Godot 4.7  ·  Cloudflare Workers  ·  API do GitHub", "mono", 32, INK, Vector2(-1, 740))
	await typewrite(stack, 40.0)
	await at_bar(28.25)
	await fade_out_all(0.25)

	# D · CONCEITO + ITERAÇÕES (48–63 s) ---------------------------------------------------------------
	set_energy(1.1)
	await chapter(0, "01", "CONCEITO", "tudo começou em 2D, no Meshy.ai")
	var concepts := []
	for file in DirAccess.get_files_at("res://References/2D"):
		if file.ends_with(".png"):
			concepts.append(file)
	concepts.sort()
	var head := label("OS CONCEITOS", "black", 84, INK, Vector2(-1, 90))
	slam(head, "boom", -10.0, 6.0)
	for i in range(concepts.size()):
		var card := picture("res://References/2D/" + concepts[i], Rect2(200 + (i % 6) * 260, 260 + (i / 6) * 250, 236, 228), GOLD, true)
		fly_in(card, Vector2(rng.randf_range(-500, 500), 700), rng.randf_range(-25, 25))
		sfx("blip", -15.0, 0.8 + i * 0.04)
		await wait(BEAT * 0.5)
	await wait(1.2)
	await fade_out_all(0.25)
	# as versões reais no Meshy (refiz várias até ficar do meu jeito)
	var tall := picture("res://Builds/MakingOf/assets/meshy_iterations.png", Rect2(250, 70, 540, 940), GOLD, true)
	fly_in(tall, Vector2(-500, 0), -8)
	sfx("whoosh", -10.0)
	stage.create_tween().tween_property(tall, "scale", Vector2.ONE * 1.04, 6.0)
	await wait(0.6)
	var no1 := label("e não,", "serif", 84, INK, Vector2(900, 300), 900, HORIZONTAL_ALIGNMENT_LEFT)
	pop(no1, 0.9)
	await wait(0.9)
	var no2 := label("não acertei de primeira.", "serif", 84, GOLD, Vector2(900, 400), 960, HORIZONTAL_ALIGNMENT_LEFT)
	pop(no2, 0.9)
	await wait(1.6)
	var no3 := label("> refiz um monte de versão até ficar do meu jeito.", "mono", 34, CYAN, Vector2(904, 560), 900, HORIZONTAL_ALIGNMENT_LEFT)
	await typewrite(no3, 38.0)
	await at_bar(37.5)
	await fade_out_all(0.25)

	# E · PROTÓTIPO (63–70 s) ------------------------------------------------------------------------
	await chapter(1, "02", "PROTÓTIPO", "primeira versão: Codex + Godot, via MCP")
	var jelly := picture("res://Documentation/Previews/overview.png", Rect2(560, 120, 800, 470), MAGENTA)
	pop(jelly, 0.7)
	sfx("splash", -6.0)
	var wob := stage.create_tween()
	for k in range(5):
		wob.tween_property(jelly, "scale", Vector2(1.07, 0.93), BEAT * 0.5).set_trans(Tween.TRANS_SINE)
		wob.tween_property(jelly, "scale", Vector2(0.94, 1.06), BEAT * 0.5).set_trans(Tween.TRANS_SINE)
	wob.tween_property(jelly, "scale", Vector2.ONE, BEAT * 0.5)
	var gel := label("o oceano em algum momento parecia uma gelatina.", "serif", 64, MAGENTA, Vector2(-1, 650), 1700)
	pop(gel, 0.9)
	glitch(0.6, 0.4)
	await wait(2.4)
	var shh := label("(essa parte a gente finge que nunca aconteceu, rs)", "mono", 32, MIST, Vector2(-1, 760))
	await typewrite(shh, 40.0, false)
	await at_bar(43.0)
	await fade_out_all(0.2)

	# F · "EU ATÉ QUERIA FAZER ALGO SIMPLES..." — energia subindo (72–84 s) --------------------------------
	set_energy(1.6)
	say("eu até queria fazer algo simples...", "serif", 86, INK, 400)
	await wait(2.2)
	var but := label("MAS DAÍ, QUANDO VI:", "black", 90, GOLD, Vector2(-1, 540))
	slam(but, "boom", -6.0, 12.0)
	await at_bar(44.75)
	await fade_out_all(0.15)
	var log_panel := terminal(Rect2(1340, 110, 520, 860), "git log --oneline")
	var features := [
		["física e flutuação", "v10_waterline_bow.png"],
		["vento na vela", "v8_sail.png"],
		["espuma e spray na proa", "v6_bow_wave_port.png"],
		["ciclo de dia e noite", "v10_night.png"],
		["farol e fogueira", "v10_night_island_5.png"],
		["mapa-múndi em 3D", "v10_overview.png"],
		["Log Pose", "v7_logpose.png"],
		["controles pro celular", "v10_mobile.png"],
	]
	for i in range(features.size()):
		var shot := picture("res://Documentation/Previews/" + features[i][1], Rect2(60, 110, 1240, 640), CYAN)
		shot.modulate.a = 1.0
		fly_in(shot, Vector2(-260 if i % 2 == 0 else 260, 0), -5.0 if i % 2 == 0 else 5.0)
		stage.create_tween().tween_property(shot, "scale", Vector2.ONE * 1.06, BEAT * 2.0)
		var word := outlined(label(features[i][0].to_upper(), "black", 74, INK, Vector2(70, 790), 1260, HORIZONTAL_ALIGNMENT_LEFT))
		slam(word, "whoosh", -16.0, 5.0)
		var commit := term_line(log_panel, GIT_LOG[i], CYAN if i % 2 == 0 else INK, 22)
		typewrite(commit, 90.0, false)
		sfx("key", -12.0)
		await wait(BEAT * 2.0)
		shot.queue_free()
		word.queue_free()
	var target := picture("res://Documentation/Previews/v10_hud_race.png", Rect2(60, 110, 1240, 640), RED)
	pop(target, 0.8)
	var race := outlined(label("E UM DESAFIO DE CANHÃO COM 20 ALVOS.", "black", 64, GOLD, Vector2(70, 790), 1260, HORIZONTAL_ALIGNMENT_LEFT))
	slam(race, "cannon", -4.0, 22.0)
	do_flash(Color(1, 1, 1, 0.6), 0.3)
	await wait(BAR * 1.25)
	await fade_out_all(0.2)
	var science := label("até artigo científico sobre ondas trocoidais eu li.", "serif", 70, INK, Vector2(-1, 360), 1700)
	pop(science, 0.9)
	await wait(2.4)
	var reddit := label("+ altos vídeos de tutorial + muito Reddit", "mono", 38, CYAN, Vector2(-1, 520))
	await typewrite(reddit, 36.0)
	await at_bar(50.5)
	await fade_out_all(0.25)

	# G · DEU ERRADO — o vale da música, ritmo de leitura (85–103 s) ---------------------------------------------
	set_energy(0.6)
	grid.tint = RED
	await chapter(2, "03", "DEU ERRADO", "muita coisa, antes de começar a dar certo")
	sfx("fuse", -12.0)
	var fails := [
		["O NAVIO AFUNDAVA.", "medi a linha d'água: -0,38 -> +0,05"],
		["O CLOUDFLARE CORTAVA O JOGO NO MEIO.", "agora o navegador monta o jogo em partes"],
		["NO CELULAR, TUDO BRANCO.", "o cache do Godot pulava a importação"],
		["TEVE CELULAR QUE TRAVOU INTEIRO.", "versão leve + gráficos que se ajustam sozinhos"],
	]
	for i in range(fails.size()):
		var y := 170.0 + i * 205.0
		var stamp_bg := ColorRect.new()
		stamp_bg.color = RED
		stamp_bg.position = Vector2(150, y + 12)
		stamp_bg.size = Vector2(110, 46)
		stage.add_child(stamp_bg)
		pop(stamp_bg, 1.6)
		var stamp := label("ERRO", "mono", 30, DEEP, Vector2(160, y + 16), 120)
		pop(stamp, 1.0)
		var fail := label(fails[i][0], "black", 60, INK, Vector2(300, y), 1500, HORIZONTAL_ALIGNMENT_LEFT)
		slam(fail, "explosion", -12.0, 16.0)
		glitch(0.7, 0.35)
		await wait(BAR)
		var fix := label("✓  " + fails[i][1], "mono", 32, GOLD, Vector2(304, y + 90), 1500, HORIZONTAL_ALIGNMENT_LEFT)
		sfx("bell", -6.0, 1.0 + i * 0.06)
		await typewrite(fix, 50.0, false)
		await wait(BAR * 1.0)
	await at_bar(61.0)
	await fade_out_all(0.25)
	grid.tint = CYAN

	# H · "MAS AINDA PRECISAVA SER UM PORTFÓLIO" (103–110 s) -------------------------------------------------
	set_energy(1.0)
	say("só que isso ainda precisava ser um portfólio.", "serif", 72, INK, 250, 1700)
	await wait(2.2)
	var duties := ["> cartão profissional enquanto o 3D carrega", "> visita guiada pra quem não quer pilotar", "> versão só texto pra conexão ruim"]
	for i in range(duties.size()):
		var d := label(duties[i], "mono", 38, CYAN if i % 2 == 0 else INK, Vector2(300, 440 + i * 90), 1400, HORIZONTAL_ALIGNMENT_LEFT)
		typewrite(d, 48.0)
		await wait(BAR * 0.75)
	await at_bar(65.5)
	await fade_out_all(0.2)

	# I · O RESULTADO — gameplay real no pico da música (110–143 s) --------------------------------------------
	set_energy(1.8)
	var result := label("O RESULTADO", "black", 190, INK, Vector2(-1, 420))
	slam(result, "cannon", -2.0, 30.0)
	do_flash(PARCH, 0.4)
	await at_bar(66.5)
	await fade_out_all(0.1)
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1, 0.1, 1)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("World"), -6.0)
	wave_wipe(CYAN, 0.3, 0.0, 0.45)
	await wait(0.31)
	grid.modulate.a = 0.0
	var rec := outlined(label("● AO VIVO  ·  GAMEPLAY REAL", "mono", 26, RED, Vector2(70, 60), 900, HORIZONTAL_ALIGNMENT_LEFT), 8)
	live_caption("NAVEGUE.", "> física e flutuação sincronizadas com as ondas")
	await at_bar(69.0)
	await _clear_captions(rec)
	world.ship.test_controls = Vector3(0.6, 0.0, 0)
	world.naval.call("fire")
	live_caption("ATIRE.", "> canhão de verdade, splash de verdade")
	await at_bar(71.5)
	await _clear_captions(rec)
	world.ship.test_controls = Vector3.ZERO
	world.toggle_map()
	await wait(1.6)
	live_caption("GIRE O MUNDO.", "> mapa-múndi em 3D")
	var spin_end := now() + BAR * 1.6
	while now() < spin_end:
		await process_frame
		world.camera.drag_orbit(Vector2(-9, 6))
	await at_bar(74.5)
	await _clear_captions(rec)
	var visits := [[1, "EXPERIÊNCIA.", "> cada ilha, uma parte do currículo"], [3, "PROJETOS.", "> direto da API do GitHub, sempre atualizado"], [4, "CONTATO.", "> com Den Den Mushi no farol, claro"]]
	for v in visits:
		world.hud.island_pressed.emit(v[0])
		sfx("whoosh", -14.0)
		await wait(2.3)
		# Garante o painel da ilha certa (a visita pode ter aberto outra no caminho).
		world.hud.show_island(v[0], false)
		live_caption(v[1], v[2])
		await wait(BAR * 2.5 - 2.3)
		await _clear_captions(rec)
	world.select_time("night")
	live_caption("E DE NOITE...", "> o farol acende")
	await at_bar(84.5)
	await _clear_captions(rec)
	rec.queue_free()
	grid.modulate.a = 1.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("World"), -16.0)

	# J · FECHAMENTO (142–152 s) -------------------------------------------------------------------------
	set_energy(1.2)
	say("no fim, acho que isso mostra muito melhor quem eu sou", "serif", 68, INK, 300, 1700)
	await wait(2.6)
	say("do que uma página estática.", "serif", 68, GOLD, 400)
	await at_bar(87.5)
	await fade_out_all(0.25)
	say("e, convenhamos, se é pra falar de mim,", "serif", 70, INK, 330, 1700)
	await wait(2.4)
	var adventure := label("QUE SEJA CURTINDO ALTAS AVENTURAS!", "black", 84, GOLD, Vector2(-1, 470), 1800)
	slam(adventure, "cannon", -4.0, 24.0)
	do_flash(PARCH, 0.4)
	await at_bar(90.75)
	await fade_out_all(0.25)

	# K · ASSINATURA (152–163 s) -------------------------------------------------------------------------
	route.visible = true
	route.modulate.a = 0.35
	route.progress = 5.0
	route.reached = 6
	for i in range(6):
		route.ping(i)
	sfx("ping", -8.0)
	var me := label("Pedro D. Ferreira", "serif", 150, INK, Vector2(-1, 200))
	pop(me, 0.85)
	var role2 := label("Data Engineer & Cybersecurity Student", "roman", 52, GOLD, Vector2(-1, 390))
	pop(role2)
	await wait(1.0)
	var li := label("in   Pedro D. Ferreira", "mono", 44, INK, Vector2(560, 530), 900, HORIZONTAL_ALIGNMENT_LEFT)
	await typewrite(li, 34.0)
	var gh := label("gh   github.com/DATAdotPDF", "mono", 44, CYAN, Vector2(560, 610), 900, HORIZONTAL_ALIGNMENT_LEFT)
	await typewrite(gh, 34.0)
	var code := label("código, arquitetura e o processo completo estão lá", "sans", 30, MIST, Vector2(-1, 720))
	pop(code)
	var made := label("feito junto com Meshy.ai · Codex · Claude  —  em Godot", "sans", 28, MIST, Vector2(-1, 780))
	pop(made)
	await at_bar(94.0)
	var otaku := label("#otakusnotopo", "black", 96, GOLD, Vector2(-1, 880))
	slam(otaku, "cannon", -3.0, 20.0)
	await at_bar(95.75)
	var out := ColorRect.new()
	out.color = Color.BLACK
	out.size = SCREEN
	out.modulate.a = 0.0
	stage.add_child(out)
	stage.create_tween().tween_property(out, "modulate:a", 1.0, BAR)
	await at_bar(97.0)
	quit()

## OPÇÃO 2 — "Open Sea Quest 2" (≈143,2 BPM; intro quieta até 3,5 s; vale em 75–105 s; pico em 165–175 s).
## Roteiro original (terminal → título → referências → capítulos → resultado → eu → assinatura),
## escrito no jeito do Pedro de falar.
func run_option2() -> void:
	grid.energy = 0.35

	# A · ABERTURA (0–15 s): intro quieta, só terminal --------------------------------------------
	await wait(0.6)
	var a1 := label("> abrindo portfolio_antigo.html", "mono", 44, CYAN, Vector2(220, 380), 1600, HORIZONTAL_ALIGNMENT_LEFT)
	await typewrite(a1, 20.0)
	await at_bar(2.0)
	var a2 := label("> resultado: mais um site igualzinho aos outros", "mono", 44, MIST, Vector2(220, 455), 1600, HORIZONTAL_ALIGNMENT_LEFT)
	await typewrite(a2, 28.0)
	await at_bar(3.75)
	var a3 := label("> nível de emoção: 2/10 (sendo generoso)", "mono", 44, INK, Vector2(220, 530), 1600, HORIZONTAL_ALIGNMENT_LEFT)
	await typewrite(a3, 28.0)
	await at_bar(5.5)
	var a4 := label("ERRO: PORTFÓLIO SEM GRAÇA", "black", 92, RED, Vector2(220, 630), 1600, HORIZONTAL_ALIGNMENT_LEFT)
	slam(a4, "", 0.0, 20.0)
	glitch(1.0, 0.7)
	await at_bar(7.0)
	sfx("riser", -10.0)
	await fade_out_all(0.3)
	set_energy(0.6)
	await at_bar(7.5)
	wave_wipe(CYAN, 0.45, 0.05, 0.55)
	await wait(0.48)
	say("e se, em vez de rolar a página,", "serif", 84, INK, 360)
	await wait(1.6)
	say("você saísse navegando?", "serif", 104, GOLD, 480)
	await at_bar(10.0)
	await fade_out_all(0.25)

	# B · TÍTULO + MUNDO AO VIVO (17–27 s) -----------------------------------------------------------
	do_flash(PARCH, 0.5)
	sfx("cannon", -3.0)
	shake(22.0, 0.4)
	var compass := Compass.new()
	compass.size = Vector2(800, 800)
	compass.position = Vector2(560, 140)
	stage.add_child(compass)
	pop(compass, 0.3)
	var title := label("GRAND LINE", "black", 210, INK, Vector2(-1, 400))
	slam(title, "", 0.0, 0.0)
	await wait(BEAT * 2.0)
	var edition := label("MEU PORTFÓLIO  //  EDIÇÃO PIRATA", "mono", 36, CYAN, Vector2(-1, 650))
	await typewrite(edition, 34.0)
	var by := label("por Pedro D. Ferreira", "serif", 54, GOLD, Vector2(-1, 720))
	pop(by)
	await at_bar(13.0)
	await fade_out_all(0.2)
	wave_wipe(NAVY, 0.35, 0.0, 0.5)
	await wait(0.37)
	world.hud.visible = false
	grid.modulate.a = 0.0
	var frame := Brackets.new()
	frame.position = Vector2(40, 40)
	frame.size = SCREEN - Vector2(80, 80)
	stage.add_child(frame)
	var live := outlined(label("● AO VIVO  ·  GODOT 4.7", "mono", 26, RED, Vector2(80, 64), 900, HORIZONTAL_ALIGNMENT_LEFT), 8)
	pop(live)
	await wait(0.6)
	var world_line := outlined(label("um planeta. uma chalupa. cinco ilhas.", "black", 64, INK, Vector2(110, 760), 1700, HORIZONTAL_ALIGNMENT_LEFT))
	pop(world_line, 0.9)
	await wait(2.2)
	var cv := outlined(label("> e o meu currículo espalhado nelas", "mono", 36, GOLD, Vector2(114, 860), 1700, HORIZONTAL_ALIGNMENT_LEFT), 8)
	await typewrite(cv, 34.0, false)
	await at_bar(16.0)
	await fade_out_all(0.2)
	world.hud.visible = true
	grid.modulate.a = 1.0

	# C · REFERÊNCIAS (27–33 s) ------------------------------------------------------------------------
	set_energy(0.9)
	var guilty := label("// A CULPA É DELES:", "mono", 32, CYAN, Vector2(-1, 150))
	pop(guilty)
	var refs := [["ONE PIECE", INK], ["WIND WAKER", GOLD], ["SEA OF THIEVES", CYAN], ["MONKEY ISLAND", INK], ["PIRATAS DO CARIBE", GOLD]]
	for i in range(refs.size()):
		await at_bar(16.5 + i * 0.5)
		var r := label(refs[i][0], "black", 100, refs[i][1], Vector2(-1, 250 + i * 125))
		slam(r, "wood", -12.0, 6.0)
	await wait(0.8)
	var naz := label("+ o portfólio do José Nazaré, que já abria direto no mar", "mono", 28, MIST, Vector2(-1, 905))
	await typewrite(naz, 46.0, false)
	await at_bar(20.25)
	await fade_out_all(0.2)

	# D · 01 CONCEITO (34–50 s) ------------------------------------------------------------------------
	set_energy(1.1)
	await chapter(0, "01", "CONCEITO", "primeiro em 2D, tudo no Meshy.ai")
	var concepts := []
	for file in DirAccess.get_files_at("res://References/2D"):
		if file.ends_with(".png"):
			concepts.append(file)
	concepts.sort()
	var head := label("OS CONCEITOS", "black", 84, INK, Vector2(-1, 90))
	slam(head, "boom", -10.0, 6.0)
	for i in range(concepts.size()):
		var card := picture("res://References/2D/" + concepts[i], Rect2(200 + (i % 6) * 260, 260 + (i / 6) * 250, 236, 228), GOLD, true)
		fly_in(card, Vector2(rng.randf_range(-500, 500), 700), rng.randf_range(-25, 25))
		sfx("blip", -15.0, 0.8 + i * 0.04)
		await wait(BEAT * 0.5)
	await wait(1.0)
	await fade_out_all(0.2)
	var tall := picture("res://Builds/MakingOf/assets/meshy_iterations.png", Rect2(250, 70, 540, 940), GOLD, true)
	fly_in(tall, Vector2(-500, 0), -8)
	sfx("whoosh", -10.0)
	stage.create_tween().tween_property(tall, "scale", Vector2.ONE * 1.04, 5.0)
	await wait(0.5)
	var sp1 := label("spoiler:", "mono", 40, CYAN, Vector2(900, 300), 900, HORIZONTAL_ALIGNMENT_LEFT)
	pop(sp1)
	await wait(0.7)
	var sp2 := label("teve MUITA versão descartada", "serif", 76, INK, Vector2(900, 370), 960, HORIZONTAL_ALIGNMENT_LEFT)
	pop(sp2, 0.9)
	await wait(1.4)
	var sp3 := label("até eu ficar feliz.", "serif", 76, GOLD, Vector2(900, 470), 960, HORIZONTAL_ALIGNMENT_LEFT)
	pop(sp3, 0.9)
	await at_bar(28.75)
	await fade_out_all(0.2)
	var carriage := picture("res://References/2D/Meshy_AI_cannon_carriage_corrected_concept.png", Rect2(1020, 220, 620, 500), GOLD)
	var barrel := picture("res://References/2D/Meshy_AI_cannon_barrel_isolated_concept.png", Rect2(280, 220, 620, 500), GOLD)
	fly_in(barrel, Vector2(-600, 0), -20)
	fly_in(carriage, Vector2(600, 0), 20)
	sfx("wood", -8.0)
	await wait(BEAT)
	barrel.pivot_offset = Vector2(560, 320)
	var tilt := stage.create_tween()
	for k in range(2):
		tilt.tween_property(barrel, "rotation_degrees", -14.0, BEAT).set_trans(Tween.TRANS_SINE)
		tilt.tween_property(barrel, "rotation_degrees", 6.0, BEAT).set_trans(Tween.TRANS_SINE)
	tilt.tween_property(barrel, "rotation_degrees", 0.0, BEAT * 0.5)
	var rule := label("REGRA QUE EU NÃO ABRO MÃO:", "black", 58, RED, Vector2(-1, 790))
	slam(rule, "cannon_small", -8.0, 8.0)
	var rule2 := label("o cano só sobe e desce. duas peças, sempre.", "mono", 34, INK, Vector2(-1, 875))
	await typewrite(rule2, 44.0)
	sfx("bell", -6.0)
	await at_bar(31.0)
	await fade_out_all(0.2)

	# E · 02 PROTÓTIPO (50–62 s) ------------------------------------------------------------------------
	await chapter(1, "02", "PROTÓTIPO", "a primeira versão saiu com o Codex")
	var term := terminal(Rect2(160, 140, 760, 300), "codex@godot ~")
	var t1 := term_line(term, "$ gerar planeta --raio 200m", CYAN)
	await typewrite(t1, 30.0)
	var t2 := term_line(term, "ok. planeta gerado.", MIST)
	await typewrite(t2, 60.0, false)
	var jelly := picture("res://Documentation/Previews/overview.png", Rect2(980, 140, 780, 500), MAGENTA)
	pop(jelly, 0.7)
	sfx("splash", -6.0)
	var wob := stage.create_tween()
	for k in range(5):
		wob.tween_property(jelly, "scale", Vector2(1.07, 0.93), BEAT * 0.5).set_trans(Tween.TRANS_SINE)
		wob.tween_property(jelly, "scale", Vector2(0.94, 1.06), BEAT * 0.5).set_trans(Tween.TRANS_SINE)
	wob.tween_property(jelly, "scale", Vector2.ONE, BEAT * 0.5)
	var gel := label("o oceano virou uma gelatina azul.", "serif", 76, MAGENTA, Vector2(-1, 700))
	pop(gel, 0.9)
	glitch(0.6, 0.4)
	await wait(2.0)
	var nope := label("lindo? não.", "black", 70, INK, Vector2(-1, 810))
	slam(nope, "boom", -8.0, 10.0)
	await at_bar(36.0)
	await fade_out_all(0.15)
	var storms := ["revision_sailing.png", "v2_island_2_day.png", "v3_island_3_night.png"]
	for i in range(storms.size()):
		var s := picture("res://Documentation/Previews/" + storms[i], Rect2(90 + i * 590, 200, 560, 360), MIST)
		fly_in(s, Vector2(0, 500), rng.randf_range(-10, 10))
		sfx("wave", -16.0, 1.2)
		await wait(BEAT * 0.5)
	shake(18.0, 0.8)
	say("mar de tempestade num portfólio...", "serif", 76, INK, 640)
	await wait(2.0)
	var breathe := label("RESPIRA, PEDRO.", "black", 120, GOLD, Vector2(-1, 760))
	slam(breathe, "boom", -4.0, 18.0)
	await at_bar(39.0)
	await fade_out_all(0.2)

	# F · 03 O PLANO (64–73 s) --------------------------------------------------------------------------
	await chapter(2, "03", "O PLANO", "parei tudo e escrevi um brief com cada coisa que deu errado")
	var steps := ["ENTENDER", "PLANEJAR", "PERGUNTAR", "EXECUTAR"]
	for i in range(steps.size()):
		var x := 110.0 + i * 445.0
		var s := label(steps[i], "black", 54, INK if i < 3 else GOLD, Vector2(x, 380), 400)
		slam(s, "", 0.0, 4.0)
		sfx("ping", -14.0, 1.0 + i * 0.15)
		if i < 3:
			var arrow := label("→", "mono", 64, CYAN, Vector2(x + 385, 375), 80)
			pop(arrow)
		await wait(BEAT)
	var crew_in := label("aí o Claude entrou na tripulação:", "serif", 64, INK, Vector2(-1, 560))
	pop(crew_in, 0.9)
	await wait(1.8)
	var measure := label("> mediu cada ilha antes de encostar em qualquer coisa", "mono", 34, CYAN, Vector2(-1, 670))
	await typewrite(measure, 40.0)
	await at_bar(43.5)
	await fade_out_all(0.2)

	# G · 04 CONSTRUÇÃO — montagem + git log (73–88 s) -----------------------------------------------------
	set_energy(1.4)
	await chapter(3, "04", "CONSTRUÇÃO", "oceano, vento, luz, interface, web")
	var log_panel := terminal(Rect2(1300, 120, 560, 840), "git log --oneline")
	var montage := [
		["v10_ripple.png", "// ondas de verdade: a mesma conta no shader e na física"],
		["v6_bow_wave_port.png", "// spray na proa, porque sim"],
		["v7_logpose.png", "// Log Pose apontando a próxima ilha (claro)"],
		["winmask_island_sobre.png", "// isso é uma máscara de janelas. confia."],
		["markers_0_z+.png", "// cada luz posicionada por raycast"],
		["v10_night_island_1.png", "// pra janelinha acender no lugar certo"],
		["v10_overview.png", "// o planeta gira, o universo não"],
		["v10_hud_island_panel.png", "// interface refeita umas 5 vezes (no mínimo)"],
	]
	for i in range(montage.size()):
		var shot := picture("res://Documentation/Previews/" + montage[i][0], Rect2(60, 140, 1180, 660), CYAN)
		fly_in(shot, Vector2(-300 if i % 2 == 0 else 300, 0), -6.0 if i % 2 == 0 else 6.0)
		sfx("whoosh", -16.0, 1.3)
		stage.create_tween().tween_property(shot, "scale", Vector2.ONE * 1.05, BAR)
		var cap := label(montage[i][1], "mono", 32, GOLD, Vector2(64, 830), 1180, HORIZONTAL_ALIGNMENT_LEFT)
		typewrite(cap, 70.0, false)
		var commit := term_line(log_panel, GIT_LOG[i], CYAN if i % 2 == 0 else INK, 22)
		typewrite(commit, 80.0, true)
		await wait(BAR * 1.25 - 0.25)
		stage.create_tween().tween_property(shot, "modulate:a", 0.0, 0.2)
		stage.create_tween().tween_property(cap, "modulate:a", 0.0, 0.2)
		await wait(0.25)
		shot.queue_free()
		cap.queue_free()
	var last := term_line(log_panel, GIT_LOG[8], GOLD, 22)
	await typewrite(last, 80.0, true)
	await at_bar(55.5)
	await fade_out_all(0.2)

	# H · 05 DEU ERRADO — o vale da música (93–110 s) -------------------------------------------------------
	set_energy(0.6)
	grid.tint = RED
	await chapter(4, "05", "DEU ERRADO", "muita coisa. tipo, MUITA.")
	sfx("fuse", -12.0)
	var fails := [
		["O NAVIO AFUNDAVA.", "medi a linha d'água na unha: -0,38 -> +0,05"],
		["O CLOUDFLARE CORTAVA O JOGO NO MEIO.", "agora o navegador monta o jogo em partes"],
		["NO CELULAR, TUDO BRANCO.", "o cache do Godot resolveu pular a importação"],
		["O CELULAR DE UM AMIGO TRAVOU INTEIRO.", "versão leve + gráficos que se ajustam sozinhos (foi mal!)"],
	]
	for i in range(fails.size()):
		var y := 170.0 + i * 205.0
		var stamp_bg := ColorRect.new()
		stamp_bg.color = RED
		stamp_bg.position = Vector2(150, y + 12)
		stamp_bg.size = Vector2(110, 46)
		stage.add_child(stamp_bg)
		pop(stamp_bg, 1.6)
		var stamp := label("ERRO", "mono", 30, DEEP, Vector2(160, y + 16), 120)
		pop(stamp, 1.0)
		var fail := label(fails[i][0], "black", 58, INK, Vector2(300, y), 1500, HORIZONTAL_ALIGNMENT_LEFT)
		slam(fail, "explosion", -12.0, 16.0)
		glitch(0.7, 0.35)
		await wait(BAR)
		var fix := label("✓  " + fails[i][1], "mono", 32, GOLD, Vector2(304, y + 90), 1550, HORIZONTAL_ALIGNMENT_LEFT)
		sfx("bell", -6.0, 1.0 + i * 0.06)
		await typewrite(fix, 50.0, false)
		await wait(BAR * 0.7)
	await at_bar(66.0)
	await fade_out_all(0.25)
	grid.tint = CYAN

	# I · TRIPULAÇÃO (117–122 s) ---------------------------------------------------------------------
	set_energy(1.2)
	say("feito a várias mãos:", "serif", 76, INK, 230)
	var members := [["MESHY.AI", "modelos 3D", GOLD], ["CODEX", "agente de código · MCP", INK], ["CLAUDE", "agente de código · MCP", CYAN]]
	for i in range(members.size()):
		var cx := 160.0 + i * 560.0
		var box := Brackets.new()
		box.color = members[i][2]
		box.position = Vector2(cx, 380)
		box.size = Vector2(500, 260)
		stage.add_child(box)
		pop(box, 0.6)
		var who := label(members[i][0], "black", 80, members[i][2], Vector2(cx, 440), 500)
		slam(who, "cannon_small", -12.0, 6.0)
		var role := label(members[i][1], "mono", 28, MIST, Vector2(cx, 560), 500)
		pop(role)
		await wait(BEAT * 2.0)
	await at_bar(72.5)
	await fade_out_all(0.2)

	# J · O RESULTADO — gameplay subindo até o pico (122–162 s) ----------------------------------------------
	set_energy(1.8)
	var result := label("O RESULTADO", "black", 190, INK, Vector2(-1, 420))
	slam(result, "cannon", -2.0, 30.0)
	do_flash(PARCH, 0.4)
	await wait(BAR * 1.0)
	await fade_out_all(0.1)
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1, 0.1, 1)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("World"), -6.0)
	wave_wipe(CYAN, 0.3, 0.0, 0.45)
	await wait(0.31)
	grid.modulate.a = 0.0
	var rec := outlined(label("● AO VIVO  ·  GAMEPLAY REAL", "mono", 26, RED, Vector2(70, 60), 900, HORIZONTAL_ALIGNMENT_LEFT), 8)
	live_caption("NAVEGUE.", "> a chalupa boia nas mesmas ondas que você vê")
	await wait(BAR * 2.2)
	await _clear_captions(rec)
	world.ship.test_controls = Vector3(0.6, 0.0, 0)
	world.naval.call("fire")
	live_caption("ATIRE.", "> sim, tem desafio de canhão")
	await wait(BAR * 1.6)
	await _clear_captions(rec)
	world.ship.test_controls = Vector3.ZERO
	world.toggle_map()
	await wait(1.6)
	live_caption("GIRE O MUNDO.", "> o mapa é o planeta inteiro")
	var spin_end := now() + BAR * 1.6
	while now() < spin_end:
		await process_frame
		world.camera.drag_orbit(Vector2(-9, 6))
	await at_bar(82.0)
	await _clear_captions(rec)
	var visits := [[1, "EXPERIÊNCIA.", "> cada ilha guarda uma parte do currículo"], [3, "PROJETOS.", "> puxados direto do meu GitHub"], [4, "CONTATO.", "> com Den Den Mushi no farol, óbvio"]]
	for v in visits:
		world.hud.island_pressed.emit(v[0])
		sfx("whoosh", -14.0)
		await wait(2.3)
		world.hud.show_island(v[0], false)
		live_caption(v[1], v[2])
		await wait(BAR * 3.0 - 2.3)
		await _clear_captions(rec)
	world.select_time("night")
	live_caption("E DE NOITE...", "> o farol acende")
	await at_bar(94.0)
	await _clear_captions(rec)
	rec.queue_free()
	grid.modulate.a = 1.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("World"), -16.0)

	# K · EU NO PROCESSO (161–168 s) ----------------------------------------------------------------------
	set_energy(1.5)
	var mine := [["eu escrevi o brief.", INK], ["aprovei (e reprovei) cada asset.", INK], ["testei tudo no PC e no celular.", INK], ["e falei \"não\" MUITAS vezes.", GOLD]]
	for i in range(mine.size()):
		var l := label(mine[i][0], "serif", 72, mine[i][1], Vector2(-1, 200 + i * 120))
		pop(l, 0.85)
		sfx("blip", -12.0, 1.0 + i * 0.1)
		await wait(BEAT * 3.0)
	var ai := label("A IA CODOU JUNTO. AS DECISÕES FORAM MINHAS.", "black", 60, CYAN, Vector2(-1, 760), 1800)
	slam(ai, "boom", -6.0, 10.0)
	await at_bar(100.5)
	await fade_out_all(0.2)

	# L · ASSINATURA no pico (169–180 s) ----------------------------------------------------------------
	route.visible = true
	route.modulate.a = 0.35
	route.progress = 5.0
	route.reached = 6
	for i in range(6):
		route.ping(i)
	sfx("cannon", -2.0)
	do_flash(PARCH, 0.5)
	shake(24.0, 0.5)
	var me := label("Pedro D. Ferreira", "serif", 150, INK, Vector2(-1, 200))
	slam(me, "", 0.0, 0.0)
	var role2 := label("Data Engineer & Cybersecurity Student", "roman", 52, GOLD, Vector2(-1, 390))
	pop(role2)
	await wait(1.0)
	var li := label("in   Pedro D. Ferreira", "mono", 44, INK, Vector2(560, 530), 900, HORIZONTAL_ALIGNMENT_LEFT)
	await typewrite(li, 34.0)
	var gh := label("gh   github.com/DATAdotPDF", "mono", 44, CYAN, Vector2(560, 610), 900, HORIZONTAL_ALIGNMENT_LEFT)
	await typewrite(gh, 34.0)
	var code := label("código, arquitetura e o processo inteiro estão lá", "sans", 30, MIST, Vector2(-1, 720))
	pop(code)
	var made := label("feito junto com Meshy.ai · Codex · Claude  —  em Godot", "sans", 28, MIST, Vector2(-1, 780))
	pop(made)
	await at_bar(104.5)
	var otaku := label("#otakusnotopo", "black", 96, GOLD, Vector2(-1, 880))
	slam(otaku, "cannon", -3.0, 20.0)
	await at_bar(106.25)
	var out := ColorRect.new()
	out.color = Color.BLACK
	out.size = SCREEN
	out.modulate.a = 0.0
	stage.add_child(out)
	stage.create_tween().tween_property(out, "modulate:a", 1.0, BAR)
	await at_bar(107.5)
	quit()

func _clear_captions(keep: Node) -> void:
	for child in stage.get_children():
		if child != keep and child is CanvasItem:
			stage.create_tween().tween_property(child, "modulate:a", 0.0, 0.15)
	await wait(0.15)
	for child in stage.get_children():
		if child != keep:
			child.queue_free()
