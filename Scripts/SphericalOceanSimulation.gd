extends Node

const Scale = preload("res://Scripts/WorldScale.gd")
const DIRECTIONS := [
	Vector3(0.866, 0.0, 0.5),
	Vector3(-0.5, 0.707, 0.5),
	Vector3(-0.3, -0.6, 0.74),
	Vector3(0.43, -0.27, -0.86)
]
const AMPLITUDES := [1.55, 0.18, 0.07, 0.03]
const WAVELENGTHS := [54.0, 32.0, 19.0, 11.0]
const OFFSETS := [0.0, 1.7, 3.8, 5.1]

@export var radius: float = Scale.OCEAN_RADIUS
@export var wave_strength: float = 3.0
@export var wavelength_scale: float = 1.0
@export var wave_speed: float = 1.0

var simulation_time := 0.0
var materials: Array[ShaderMaterial] = []
var wake: Array[Vector4] = []
var ripples: Array[Vector4] = []
var island_centers := PackedVector3Array()
var island_radii := PackedFloat32Array()

func _ready() -> void:
	process_physics_priority = -20

func register_material(material: ShaderMaterial) -> void:
	if not materials.has(material):
		materials.append(material)
	material.set_shader_parameter("planet_radius", radius)
	material.set_shader_parameter("wave_strength", wave_strength)
	material.set_shader_parameter("wavelength_scale", wavelength_scale)
	material.set_shader_parameter("wave_speed", wave_speed)
	material.set_shader_parameter("ocean_time", simulation_time)
	material.set_shader_parameter("use_simulation_time", true)

func _physics_process(delta: float) -> void:
	simulation_time += delta
	for i in range(wake.size() - 1, -1, -1):
		wake[i].w -= delta / 7.0
		if wake[i].w <= 0.0:
			wake.remove_at(i)
	for i in range(ripples.size() - 1, -1, -1):
		ripples[i].w += delta
		if ripples[i].w > 4.0:
			ripples.remove_at(i)

func _process(_delta: float) -> void:
	var interpolation_delay := (1.0 - Engine.get_physics_interpolation_fraction()) / float(Engine.physics_ticks_per_second)
	var render_time := maxf(0.0, simulation_time - interpolation_delay)
	var packed_wake := PackedVector4Array(wake)
	packed_wake.resize(24)
	var packed_ripples := PackedVector4Array(ripples)
	packed_ripples.resize(20)
	for material in materials:
		material.set_shader_parameter("ocean_time", render_time)
		material.set_shader_parameter("wake_points", packed_wake)
		material.set_shader_parameter("wake_count", wake.size())
		material.set_shader_parameter("ripple_points", packed_ripples)
		material.set_shader_parameter("ripple_count", ripples.size())

func _component(point: Vector3, index: int) -> float:
	var k := TAU / maxf(WAVELENGTHS[index] * wavelength_scale, 0.1)
	var omega := sqrt(9.8 * k)
	var direction: Vector3 = DIRECTIONS[index]
	var angle: float = k * point.dot(direction.normalized()) - omega * simulation_time * wave_speed + float(OFFSETS[index])
	var crest := 0.5 + 0.5 * sin(angle)
	return AMPLITUDES[index] * (pow(crest, 2.4) - 0.37)

func _wave_height(point: Vector3) -> float:
	var result := 0.0
	for index in range(DIRECTIONS.size()):
		result += _component(point, index)
	var coast_factor := 1.0
	for index in range(mini(island_centers.size(), island_radii.size())):
		var chord := point.distance_to(island_centers[index] * radius)
		coast_factor = minf(coast_factor, smoothstep(
			island_radii[index] * 0.6,
			island_radii[index] + 12.0,
			chord
		))
	return result * wave_strength * lerpf(0.08, 1.0, coast_factor)

func field_at(source: Vector3) -> Vector4:
	var point := source.normalized() * radius
	return Vector4(0.0, 0.0, 0.0, _wave_height(point))

func ripple_height_at(point: Vector3) -> float:
	var result := 0.0
	for ripple in ripples:
		var ring_distance := point.distance_to(Vector3(ripple.x, ripple.y, ripple.z)) - ripple.w * 2.4
		result += 0.12 * cos(ring_distance * 4.0) * exp(-ring_distance * ring_distance / 1.44) * (1.0 - ripple.w / 4.0) * smoothstep(0.0, 0.15, ripple.w)
	return result

func height_at(position: Vector3) -> float:
	var point := position.normalized() * radius
	return _wave_height(point) + ripple_height_at(point)

func surface_at(position: Vector3) -> Vector3:
	return position.normalized() * (radius + height_at(position))

func displaced_at(position: Vector3) -> Vector3:
	return surface_at(position)

func add_wake(position: Vector3) -> void:
	var point := position.normalized() * radius
	wake.append(Vector4(point.x, point.y, point.z, 1.0))
	if wake.size() > 24:
		wake.pop_front()

func touch(position: Vector3) -> void:
	var point := position.normalized() * radius
	ripples.append(Vector4(point.x, point.y, point.z, 0.01))
	if ripples.size() > 20:
		ripples.pop_front()
