@tool
extends Node

## Espelho em CPU do campo de ondas de Shaders/ocean_waves.gdshaderinc.
## Mesma fonte de parâmetros (WorldScale.wave_components), então o barco, as boias
## e os projéteis flutuam exatamente na onda que aparece na tela.

const Scale = preload("res://Scripts/WorldScale.gd")
const MAX_RIPPLES := 32
const MAX_WAKE := 24
const RIPPLE_LIFETIME := 5.0

var radius: float = 800.0
var wave_scale := 1.0
var simulation_time := 0.0
var materials: Array[ShaderMaterial] = []
var wake: Array[Vector4] = []
var ripples: Array[Vector4] = []
var ripple_info: Array[Vector4] = []
var island_centers := PackedVector3Array()
## Tempestades locais (Weather/StormCell): ondas maiores dentro do raio de cada uma (até 4).
const MAX_STORMS := 6
var storm_data: Array[Vector4] = []   # xyz = centro na superfície, w = raio
var storm_strengths: Array[float] = []
var island_radii := PackedFloat32Array()
## Ilhas/rochas do mapa com mar calmo em volta (iguais ao calm_spots do shader): xyz = direção, w = raio.
const MAX_CALM := 16
var calm_spots: Array[Vector4] = []
## Funil do redemoinho do kraken (mesma conta do shader): centro, raio e profundidade.
var whirl := Vector4.ZERO
var whirl_depth := 0.0
var components: Array[Dictionary] = []
## Ponto vivo da esteira (popa do barco), ligado ao último ponto gravado:
## evita o rastro 'desconectado' do casco.
var wake_head := Vector3.ZERO
## Arrasto contínuo na água (mouse/dedo segurado).
const MAX_STROKE := 24
const STROKE_LIFETIME := 3.0
var stroke: Array[Vector4] = []
var wake_head_active := false
## Pontos de esteira enviados ao shader (o celular usa menos: cada ponto é um laço por pixel).
var wake_limit := MAX_WAKE

func _ready() -> void:
	process_physics_priority = -20
	refresh_from_layout()
	var layout := Scale.layout()
	if not layout.changed.is_connected(refresh_from_layout):
		layout.changed.connect(refresh_from_layout)

func refresh_from_layout() -> void:
	radius = Scale.radius()
	wave_scale = Scale.layout().wave_scale()
	components = Scale.wave_components()
	for material in materials:
		Scale.push_wave_uniforms(material)

func register_material(material: ShaderMaterial) -> void:
	if material == null:
		return
	if not materials.has(material):
		materials.append(material)
	Scale.push_wave_uniforms(material)
	material.set_shader_parameter("ocean_time", simulation_time)
	material.set_shader_parameter("use_simulation_time", not Engine.is_editor_hint())

func set_islands(centers: PackedVector3Array, radii: PackedFloat32Array) -> void:
	island_centers = centers
	island_radii = radii
	for material in materials:
		material.set_shader_parameter("island_centers", centers)
		material.set_shader_parameter("island_radii", radii)

func set_calm_spots(spots: Array[Vector4]) -> void:
	calm_spots = spots.slice(0, MAX_CALM)
	var packed: Array[Vector4] = calm_spots.duplicate()
	packed.resize(MAX_CALM)
	for i in range(calm_spots.size(), MAX_CALM):
		packed[i] = Vector4.ZERO
	for material in materials:
		material.set_shader_parameter("calm_spots", packed)
		material.set_shader_parameter("calm_count", calm_spots.size())

func set_whirl(center: Vector3, whirl_radius: float, depth: float) -> void:
	whirl = Vector4(center.x, center.y, center.z, whirl_radius)
	whirl_depth = depth
	for material in materials:
		material.set_shader_parameter("whirl_data", whirl)
		material.set_shader_parameter("whirl_depth", whirl_depth)

func set_storms(data: Array[Vector4], strengths: Array[float]) -> void:
	storm_data = data
	storm_strengths = strengths
	var packed := PackedVector4Array(data)
	packed.resize(MAX_STORMS)
	var packed_strength := PackedFloat32Array(strengths)
	packed_strength.resize(MAX_STORMS)
	for material in materials:
		material.set_shader_parameter("storm_data", packed)
		material.set_shader_parameter("storm_strengths", packed_strength)
		material.set_shader_parameter("storm_count", mini(data.size(), MAX_STORMS))

## x = máscara da tempestade mais forte no ponto, y = badness dela (mesma conta do storm_eval).
func storm_at(point: Vector3) -> Vector2:
	var best := Vector2.ZERO
	for i in mini(storm_data.size(), MAX_STORMS):
		var s := storm_data[i]
		var m := 1.0 - smoothstep(s.w * 0.95, s.w * 1.45, point.distance_to(Vector3(s.x, s.y, s.z)))
		if m * storm_strengths[i] > best.x * best.y:
			best = Vector2(m, storm_strengths[i])
	return best

## Badness local (0..4) no ponto.
func badness_at(point: Vector3) -> float:
	var s := storm_at(point)
	return s.x * s.y

## Ganho de altura das ondas: 1 fora das tempestades (mesma conta do shader).
func storm_factor(point: Vector3) -> float:
	return 1.0 + 0.35 * badness_at(point)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulation_time += delta
	for i in range(wake.size() - 1, -1, -1):
		wake[i].w -= delta / 7.0
		if wake[i].w <= 0.0:
			wake.remove_at(i)
	for i in range(stroke.size() - 1, -1, -1):
		stroke[i].w += delta
		if stroke[i].w > STROKE_LIFETIME:
			stroke.remove_at(i)
	for i in range(ripples.size() - 1, -1, -1):
		ripples[i].w += delta
		if ripples[i].w > RIPPLE_LIFETIME:
			ripples.remove_at(i)
			ripple_info.remove_at(i)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var interpolation_delay := (1.0 - Engine.get_physics_interpolation_fraction()) / float(Engine.physics_ticks_per_second)
	var render_time := maxf(0.0, simulation_time - interpolation_delay)
	var live := wake.duplicate()
	if wake_head_active and not live.is_empty():
		var head := wake_head.normalized() * radius
		live.append(Vector4(head.x, head.y, head.z, 1.0))
	while live.size() > wake_limit:
		live.pop_front()
	var packed_wake := PackedVector4Array(live)
	packed_wake.resize(MAX_WAKE)
	var packed_stroke := PackedVector4Array(stroke)
	packed_stroke.resize(MAX_STROKE)
	var packed_ripples := PackedVector4Array(ripples)
	packed_ripples.resize(MAX_RIPPLES)
	var packed_info := PackedVector4Array(ripple_info)
	packed_info.resize(MAX_RIPPLES)
	for material in materials:
		material.set_shader_parameter("ocean_time", render_time)
		material.set_shader_parameter("wake_points", packed_wake)
		material.set_shader_parameter("wake_count", live.size())
		material.set_shader_parameter("ripple_points", packed_ripples)
		material.set_shader_parameter("ripple_info", packed_info)
		material.set_shader_parameter("ripple_count", ripples.size())
		material.set_shader_parameter("stroke_points", packed_stroke)
		material.set_shader_parameter("stroke_count", stroke.size())

func _coast_factor(point: Vector3) -> float:
	var factor := 1.0
	for i in range(mini(island_centers.size(), island_radii.size())):
		if island_radii[i] <= 0.0:
			continue
		var chord := point.distance_to(island_centers[i] * radius)
		factor = minf(factor, smoothstep(island_radii[i] * 0.7, island_radii[i] + 25.0 * wave_scale, chord))
	for spot in calm_spots:
		var spot_chord := point.distance_to(Vector3(spot.x, spot.y, spot.z) * radius)
		factor = minf(factor, smoothstep(spot.w * 0.7, spot.w + 25.0 * wave_scale, spot_chord))
	if whirl_depth > 0.0:
		factor = minf(factor, lerpf(0.2, 1.0, smoothstep(whirl.w * 0.7, whirl.w * 1.15, point.distance_to(Vector3(whirl.x, whirl.y, whirl.z)))))
	return lerpf(0.08, 1.0, factor)

## Campo Lagrangiano no ponto de repouso p (|p| = radius):
## xyz = deslocamento tangente, w = altura radial (sem as perturbações).
## Mesma torção em espiral e mesmo perfil de Rankine do shader (whirl_twist/whirl_profile).
func _whirl_twist(p: Vector3) -> Vector3:
	if whirl_depth <= 0.0:
		return p
	var c3 := Vector3(whirl.x, whirl.y, whirl.z)
	var d := p.distance_to(c3)
	if d >= whirl.w:
		return p
	var k := clampf(1.0 - d / whirl.w, 0.0, 1.0)
	var angle := whirl_depth * 0.22 * pow(k, 1.6)
	return p.rotated(c3.normalized(), angle)

func _whirl_profile(d: float, big_r: float) -> float:
	var rc2 := (big_r * 0.2) * (big_r * 0.2)
	var fr := rc2 / (big_r * big_r + rc2)
	return maxf((rc2 / (d * d + rc2) - fr) / (1.0 - fr), 0.0)

func _swell(p: Vector3) -> Vector4:
	p = _whirl_twist(p)
	var n := p.normalized()
	var badness := badness_at(p)
	var storm_amp := 1.0 + 0.35 * badness
	var storm_q := (1.0 + 0.08 * badness) / storm_amp
	var coast := _coast_factor(p) * storm_amp
	var disp := Vector3.ZERO
	var height := 0.0
	for idx in range(components.size()):
		var item: Dictionary = components[idx]
		var d: Vector3 = item.dir
		var g := d - n * n.dot(d)
		var w := Scale.calm_factor(g.length()) * coast
		var d2: Vector3 = components[(idx + 2) % components.size()].dir
		w *= 0.55 + 0.75 * (0.5 + 0.5 * sin(float(item.k) * 0.19 * p.dot(d2) + float(item.k) * 0.07 * p.dot(d) - float(item.omega) * 0.05 * simulation_time + float(item.phase) * 2.7))
		var phi: float = float(item.k) * p.dot(d) - float(item.omega) * simulation_time + float(item.phase)
		var a: float = float(item.amplitude) * w
		height += a * sin(phi)
		disp += g * (float(item.steepness) * storm_q * a * cos(phi))
	var chop_disp: Array = []
	var chop := _chop(p, n, badness, _coast_factor(p), chop_disp)
	if not chop_disp.is_empty():
		disp += chop_disp[0]
		height += chop.x
	if whirl_depth > 0.0:
		var d := p.distance_to(Vector3(whirl.x, whirl.y, whirl.z))
		if d < whirl.w:
			height -= whirl_depth * _whirl_profile(d, whirl.w)
	return Vector4(disp.x, disp.y, disp.z, height)

## Oitava curta do mar picado (mesma conta do shader). Vector2(altura, crest); disp somado em out_disp.
func _chop(p: Vector3, n: Vector3, badness: float, calm_coast: float, out_disp: Array) -> Vector2:
	var chop := clampf(0.2 + badness / 4.0, 0.0, 1.0)
	if chop <= 0.01:
		return Vector2.ZERO
	var height := 0.0
	var crest := 0.0
	var disp := Vector3.ZERO
	var count := components.size()
	for idx in range(count):
		var item: Dictionary = components[idx]
		var d: Vector3 = ((item.dir as Vector3) + (components[(idx + 1) % count].dir as Vector3) * 0.6).normalized()
		var g := d - n * n.dot(d)
		var k := float(item.k) * 2.6
		var w := Scale.calm_factor(g.length()) * calm_coast * chop
		var phi := k * p.dot(d) - float(item.omega) * 1.6125 * simulation_time + float(item.phase) * 3.1
		var a := float(item.amplitude) * 0.3 * w
		height += a * sin(phi)
		disp += g * (float(item.steepness) * 0.8 * a * cos(phi))
		crest += float(item.steepness) * 0.8 * a * k * sin(phi)
	out_disp.append(disp)
	return Vector2(height, crest)

## Compressão da crista no ponto (a mesma 'crest' do shader; > ~0.6 = onda se fechando).
## Aproximada no ponto de repouso, sem inverter o deslocamento: serve para o spray.
func crest_at(position: Vector3) -> float:
	var p := position.normalized() * radius
	var n := p.normalized()
	var badness := badness_at(p)
	var storm_amp := 1.0 + 0.35 * badness
	var storm_q := (1.0 + 0.08 * badness) / storm_amp
	var coast := _coast_factor(p) * storm_amp
	var crest := 0.0
	for idx in range(components.size()):
		var item: Dictionary = components[idx]
		var d: Vector3 = item.dir
		var g := d - n * n.dot(d)
		var w := Scale.calm_factor(g.length()) * coast
		var d2: Vector3 = components[(idx + 2) % components.size()].dir
		w *= 0.55 + 0.75 * (0.5 + 0.5 * sin(float(item.k) * 0.19 * p.dot(d2) + float(item.k) * 0.07 * p.dot(d) - float(item.omega) * 0.05 * simulation_time + float(item.phase) * 2.7))
		var phi: float = float(item.k) * p.dot(d) - float(item.omega) * simulation_time + float(item.phase)
		crest += float(item.steepness) * storm_q * float(item.amplitude) * w * float(item.k) * sin(phi)
	return crest + _chop(p, n, badness, _coast_factor(p), []).y

func ripple_height_at(p: Vector3) -> float:
	var result := 0.0
	for i in range(ripples.size()):
		var ripple := ripples[i]
		var info := ripple_info[i]
		var age := ripple.w
		var dist := p.distance_to(Vector3(ripple.x, ripple.y, ripple.z))
		var sigma := 0.9 + 0.55 * age
		var x := dist - info.y * age
		var k := TAU / (2.2 + 0.35 * age)
		var envelope := exp(-x * x / (2.0 * sigma * sigma))
		var amp := info.x * exp(-age * 0.9) / (1.0 + 0.12 * dist) * smoothstep(0.0, 0.08, age)
		result += amp * envelope * -cos(k * x)
	return result

func field_at(source: Vector3) -> Vector4:
	return _swell(source.normalized() * radius)

## Altura da superfície acima do ponto (Euleriana): inverte o deslocamento
## horizontal do Gerstner com duas iterações de ponto fixo.
func height_at(position: Vector3) -> float:
	var target := position.normalized() * radius
	var rest := target
	for _i in range(2):
		var f := _swell(rest)
		rest = (target - Vector3(f.x, f.y, f.z)).normalized() * radius
	return _swell(rest).w + ripple_height_at(target)

func surface_at(position: Vector3) -> Vector3:
	return position.normalized() * (radius + height_at(position))

func displaced_at(position: Vector3) -> Vector3:
	return surface_at(position)

func add_wake(position: Vector3) -> void:
	var point := position.normalized() * radius
	wake.append(Vector4(point.x, point.y, point.z, 1.0))
	if wake.size() > MAX_WAKE:
		wake.pop_front()

## strength em metros; speed = velocidade de expansão da frente (m/s).
func touch(position: Vector3, strength := 0.45, speed := 3.2) -> void:
	var point := position.normalized() * radius
	ripples.append(Vector4(point.x, point.y, point.z, 0.0))
	ripple_info.append(Vector4(strength, speed, 0.0, 0.0))
	if ripples.size() > MAX_RIPPLES:
		ripples.pop_front()
		ripple_info.pop_front()

## Acrescenta um ponto ao sulco do arrasto. new_stroke = começa um traço novo.
func drag(position: Vector3, new_stroke := false) -> void:
	var point := position.normalized() * radius
	if new_stroke and not stroke.is_empty():
		# Traço novo não se liga ao anterior: envelhece o antigo de uma vez.
		stroke.clear()
	stroke.append(Vector4(point.x, point.y, point.z, 0.0))
	if stroke.size() > MAX_STROKE:
		stroke.pop_front()
