extends MultiMeshInstance3D

## Nuvens fofas em 3D sobre o globo. Os pontos são fixos no planeta (rede de
## Fibonacci), então o barco passa por baixo delas; só as mais próximas são
## desenhadas. As sombras na água são falsas (no shader do mar), por desempenho.

const Scale = preload("res://Scripts/WorldScale.gd")
const LATTICE := 1400
const DRAWN := 22
const PUFFS := 7
const SHADOWS := 12

@export var cloud_height := 85.0
@export var coverage := 0.5
@export var refresh_distance := 35.0

var ship: Node3D
var ocean_materials: Array[ShaderMaterial] = []
var clock: Node
var material: ShaderMaterial
var anchors := PackedVector3Array()
var sizes := PackedFloat32Array()
var drawn_centers: Array[Vector3] = []
var drawn_sizes: Array[float] = []
var last_refresh := Vector3.INF

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 14
	puff.rings = 7
	material = ShaderMaterial.new()
	material.shader = load("res://Shaders/cloud_puff.gdshader")
	puff.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = puff
	multimesh.instance_count = DRAWN * PUFFS
	custom_aabb = AABB(Vector3.ONE * -5000.0, Vector3.ONE * 10000.0)
	# Rede de Fibonacci: cobre o globo de forma uniforme; parte dos pontos fica vazia.
	var rng := RandomNumberGenerator.new()
	rng.seed = 731
	for i in range(LATTICE):
		var y := 1.0 - 2.0 * (float(i) + 0.5) / float(LATTICE)
		var angle := float(i) * 2.39996323
		var r := sqrt(1.0 - y * y)
		var keep := rng.randf() < coverage
		var size := rng.randf_range(0.7, 1.4)
		if keep:
			anchors.append(Vector3(cos(angle) * r, y, sin(angle) * r))
			sizes.append(size)

func _process(_delta: float) -> void:
	if not is_instance_valid(ship):
		return
	var radius := Scale.radius()
	if last_refresh == Vector3.INF or ship.global_position.distance_to(last_refresh) > refresh_distance:
		_refresh(radius)
	var sun: Vector3 = clock.sun_direction if clock else Vector3.UP
	var daylight: float = 1.0 - (float(clock.night_at(ship.global_position)) if clock else 0.0)
	material.set_shader_parameter("sun_direction", sun)
	material.set_shader_parameter("daylight", daylight)
	_push_shadows(radius, sun, daylight)

func _refresh(radius: float) -> void:
	last_refresh = ship.global_position
	var up := ship.global_position.normalized()
	var order: Array = []
	for i in range(anchors.size()):
		var d := up.dot(anchors[i])
		if d > 0.6:
			order.append([d, i])
	order.sort_custom(func(a, b): return a[0] > b[0])
	drawn_centers.clear()
	drawn_sizes.clear()
	var slot := 0
	for entry in order.slice(0, DRAWN):
		var i: int = entry[1]
		var n := anchors[i]
		var size: float = sizes[i] * 14.0
		var center := n * (radius + cloud_height + size * 0.4)
		drawn_centers.append(center)
		drawn_sizes.append(size)
		var basis := Scale.surface_basis(n, float(i) * 37.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 977 + 13
		for p in range(PUFFS):
			# Bolhas maiores no meio, menores e mais baixas nas bordas: silhueta "fofa".
			var spread := float(p) / float(PUFFS - 1) * 2.0 - 1.0
			var offset := basis.x * spread * size * 1.3 + basis.z * rng.randf_range(-0.5, 0.5) * size + basis.y * (1.0 - absf(spread)) * size * 0.35
			var puff_size := size * (1.0 - absf(spread) * 0.45) * rng.randf_range(0.75, 1.05)
			var puff_basis := basis.scaled(Vector3(puff_size, puff_size * 0.72, puff_size))
			multimesh.set_instance_transform(slot, Transform3D(puff_basis, center + offset))
			slot += 1
	while slot < multimesh.instance_count:
		multimesh.set_instance_transform(slot, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		slot += 1

## Sombra falsa: projeta o centro de cada nuvem no mar, na direção do sol.
func _push_shadows(radius: float, sun: Vector3, daylight: float) -> void:
	var packed := PackedVector4Array()
	for i in range(mini(drawn_centers.size(), SHADOWS)):
		var center := drawn_centers[i]
		var n := center.normalized()
		var height := center.length() - radius
		var elevation := sun.dot(n)
		if elevation < 0.15:
			continue
		var ground := (center - sun * (height / elevation)).normalized() * radius
		packed.append(Vector4(ground.x, ground.y, ground.z, drawn_sizes[i] * 1.6))
	var count := packed.size()
	packed.resize(SHADOWS)
	for ocean in ocean_materials:
		ocean.set_shader_parameter("cloud_shadows", packed)
		ocean.set_shader_parameter("cloud_shadow_count", count)
		ocean.set_shader_parameter("cloud_shadow_strength", 0.28 * daylight)
