extends MultiMeshInstance3D

## Spray nas cristas (ideia do GodotOceanWaves: spray só onde há espuma). Sem compute shader:
## a cada quadro sorteia alguns pontos do mar perto do barco, mede a compressão da crista na
## CPU (ocean.crest_at, a mesma conta da espuma do shader) e, onde a onda está se fechando,
## solta uns tufos que sobem com o vento, caem e se desfazem. Só com badness (tempestade).
## Simulação em GDScript num MultiMesh: funciona igual no WebGL2.

const MAX_PUFFS := 160

@export var search_radius := 38.0
@export var gravity := 7.0

var weather: Node
var rng := RandomNumberGenerator.new()
var positions := PackedVector3Array()
var velocities := PackedVector3Array()
var ages := PackedFloat32Array()
var lives := PackedFloat32Array()
var sizes := PackedFloat32Array()
var count := 0

func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rng.seed = 919
	positions.resize(MAX_PUFFS)
	velocities.resize(MAX_PUFFS)
	ages.resize(MAX_PUFFS)
	lives.resize(MAX_PUFFS)
	sizes.resize(MAX_PUFFS)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var blob := GradientTexture2D.new()
	blob.fill = GradientTexture2D.FILL_RADIAL
	blob.fill_from = Vector2(0.5, 0.5)
	blob.fill_to = Vector2(0.5, 0.0)
	blob.width = 64
	blob.height = 64
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	blob.gradient = gradient
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = blob
	material.albedo_color = Color(0.9, 0.95, 0.96)
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# Depois do mar (que vai para a fila transparente por ler a profundidade).
	material.render_priority = 1
	quad.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = MAX_PUFFS
	multimesh.visible_instance_count = 0

func _physics_process(delta: float) -> void:
	if weather == null or not is_instance_valid(weather.ship) or weather.ocean == null:
		return
	var ocean: Node = weather.ocean
	var ship: Node3D = weather.ship
	var center: Vector3 = ship.global_position
	var up := center.normalized()
	var badness: float = ocean.badness_at(center)
	if badness > 0.6:
		_spawn(ocean, center, up, badness)
	_simulate(delta)

func _spawn(ocean: Node, center: Vector3, up: Vector3, badness: float) -> void:
	var t1 := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var t2 := up.cross(t1).normalized()
	var threshold := lerpf(0.9, 0.5, clampf(badness / 4.0, 0.0, 1.0))
	var wind: Vector3 = weather.world.wind_at(center) if weather.world.has_method("wind_at") else Vector3.ZERO
	for attempt in int(badness * 3.0):
		if count >= MAX_PUFFS:
			return
		var angle := rng.randf_range(0.0, TAU)
		var dist := sqrt(rng.randf()) * search_radius + 4.0
		var probe := center + (t1 * cos(angle) + t2 * sin(angle)) * dist
		var crest: float = ocean.crest_at(probe)
		if crest < threshold:
			continue
		var surface: Vector3 = ocean.surface_at(probe)
		var local_up := surface.normalized()
		var bursts := rng.randi_range(2, 4)
		for b in bursts:
			if count >= MAX_PUFFS:
				return
			var i := count
			count += 1
			positions[i] = surface + local_up * 0.2 + (t1 * rng.randf_range(-1, 1) + t2 * rng.randf_range(-1, 1)) * 0.8
			velocities[i] = local_up * rng.randf_range(2.0, 4.5) * (0.6 + crest * 0.5) + wind * rng.randf_range(3.0, 6.0)
			ages[i] = 0.0
			lives[i] = rng.randf_range(0.9, 1.7)
			sizes[i] = rng.randf_range(0.7, 1.3) * (0.8 + badness * 0.15)

## Respingo pontual (golfinho/peixe entrando ou saindo d'água). strength ~0.3 (peixe) a 1 (golfinho).
func burst(at: Vector3, count_wanted: int, strength := 1.0, size_scale := 1.0) -> void:
	var up := at.normalized()
	var t1 := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var t2 := up.cross(t1).normalized()
	for b in count_wanted:
		if count >= MAX_PUFFS:
			return
		var i := count
		count += 1
		var side := (t1 * rng.randf_range(-1, 1) + t2 * rng.randf_range(-1, 1))
		positions[i] = at + side * 0.3 * strength
		velocities[i] = up * rng.randf_range(1.5, 3.5) * strength + side * rng.randf_range(0.5, 1.5) * strength
		ages[i] = 0.0
		lives[i] = rng.randf_range(0.5, 0.9)
		sizes[i] = rng.randf_range(0.35, 0.6) * (0.5 + strength * 0.5) * size_scale

func _simulate(delta: float) -> void:
	var i := 0
	while i < count:
		ages[i] += delta
		if ages[i] >= lives[i]:
			# Remove trocando pelo último (mantém os vivos no começo do MultiMesh).
			count -= 1
			positions[i] = positions[count]
			velocities[i] = velocities[count]
			ages[i] = ages[count]
			lives[i] = lives[count]
			sizes[i] = sizes[count]
			continue
		var up := positions[i].normalized()
		velocities[i] += -up * gravity * delta
		velocities[i] *= exp(-1.2 * delta)
		positions[i] += velocities[i] * delta
		var t := ages[i] / lives[i]
		var size := sizes[i] * lerpf(0.6, 2.4, t)
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), positions[i]))
		multimesh.set_instance_color(i, Color(1, 1, 1, sin(t * PI) * 0.75))
		i += 1
	multimesh.visible_instance_count = count
