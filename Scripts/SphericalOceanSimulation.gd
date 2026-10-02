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
var island_radii := PackedFloat32Array()
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
	return lerpf(0.08, 1.0, factor)

## Campo Lagrangiano no ponto de repouso p (|p| = radius):
## xyz = deslocamento tangente, w = altura radial (sem as perturbações).
func _swell(p: Vector3) -> Vector4:
	var n := p.normalized()
	var coast := _coast_factor(p)
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
		disp += g * (float(item.steepness) * a * cos(phi))
	return Vector4(disp.x, disp.y, disp.z, height)

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
