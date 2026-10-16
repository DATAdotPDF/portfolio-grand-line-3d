extends MultiMeshInstance3D

## Nuvens do céu (estudo do vrkumo do Wind Waker: nuvens soltas num domo em volta da câmera,
## andando com o vento, que saem por um lado e voltam pelo outro). Cada nuvem é um cúmulo
## montado com os tufos volumétricos assados no Blender (Assets/Clouds/cloud_atlas.png, o mesmo
## das tempestades), em cartões virados para a câmera (Shaders/cloud_card.gdshader).
## ~1 em 5 vira torre (cúmulo alto empilhado). Somem dentro da tempestade e no mapa.

const CARD := preload("res://Shaders/cloud_card.gdshader")
const ATLAS := preload("res://Assets/Clouds/cloud_atlas.png")
const CLUSTERS := 64
const RANGE := 520.0        # raio do domo em volta da câmera (m, no chão)

var world: Node3D
var planet_radius := 800.0
var rng := RandomNumberGenerator.new()
var clouds: Array[Dictionary] = []
var cards_total := 0
var material: ShaderMaterial
var sort_timer := 0.0

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	rng.randomize()
	material = ShaderMaterial.new()
	material.shader = CARD
	material.set_shader_parameter("atlas", ATLAS)
	material.set_shader_parameter("near_fade", 15.0)
	material.set_shader_parameter("badness", 0.0)
	material.set_shader_parameter("lit_color", Color(1.0, 1.0, 1.0))
	material.set_shader_parameter("shade_color", Color(0.72, 0.78, 0.9))
	material.set_shader_parameter("base_color", Color(0.58, 0.64, 0.78))
	material_override = material
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	custom_aabb = AABB(Vector3.ONE * -1e5, Vector3.ONE * 2e5)

## Cúmulo novo: tufos em volta de um centro (local: x lateral, y altura, z profundidade).
func _make_cloud(eye_ground: Vector3, anywhere: bool) -> Dictionary:
	var up := eye_ground.normalized()
	var t1 := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var t2 := up.cross(t1).normalized()
	var angle := rng.randf_range(0.0, TAU)
	var dist := sqrt(rng.randf()) * RANGE if anywhere else RANGE * rng.randf_range(0.92, 1.0)
	var ground := (eye_ground + (t1 * cos(angle) + t2 * sin(angle)) * dist).normalized() * planet_radius
	var tower := rng.randf() < 0.25
	# Tamanhos variados: muitos médios, alguns enormes (como no céu do Wind Waker/Sea of Thieves).
	var width := rng.randf_range(60.0, 120.0) if rng.randf() < 0.7 else rng.randf_range(130.0, 220.0)
	var tiers := rng.randi_range(3, 5) if tower else rng.randi_range(2, 3)
	var parts: Array = []
	# (Sem lâmina na base: o fundo reto já vem dos tufos do atlas; a lâmina virava risco no céu.)
	for tier in tiers:
		var y := width * (0.22 + 0.24 * tier)
		var count := maxi(2, 5 - tier) if not tower else rng.randi_range(2, 3)
		var spread := width * (0.3 - 0.05 * tier)
		for k in count:
			var x := rng.randf_range(-spread, spread)
			var z := rng.randf_range(-spread, spread) * 0.6
			parts.append({"offset": Vector3(x, y + rng.randf_range(-3.0, 3.0), z), "size": width * rng.randf_range(0.75, 1.0) * (1.0 - 0.1 * tier),
				"variant": rng.randi() % 8, "height": clampf(0.25 + 0.75 * float(tier + 1) / float(tiers + 1), 0.0, 1.0), "aspect": 1.0})
	return {"dir": ground.normalized(), "altitude": rng.randf_range(70.0, 130.0), "parts": parts,
		"flip": rng.randf() < 0.5, "age": 0.0, "fade_in": 0.0 if not anywhere else 1.0}

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if world == null or camera == null or camera.global_position.length() < planet_radius * 0.5:
		return
	var space_view: float = float(world.get("space_view"))
	var gloom: float = clampf(float(world.get("storm_gloom")), 0.0, 1.0)
	visible = space_view < 0.3 and gloom < 0.95
	if not visible:
		return
	var eye := camera.global_position
	var eye_ground := eye.normalized() * planet_radius
	if clouds.is_empty():
		for i in CLUSTERS:
			clouds.append(_make_cloud(eye_ground, true))
		cards_total = 0
		for c in clouds:
			cards_total += (c.parts as Array).size()
		multimesh.instance_count = cards_total + 40  # folga para nuvens com mais tufos
	var wind: Vector3 = world.wind_at(eye_ground) if world.has_method("wind_at") else Vector3.ZERO
	if world.sun:
		var night := 1.0 - clampf(world.sun.light_energy / 1.15, 0.0, 1.0)
		material.set_shader_parameter("sun_direction", (-world.sun.global_basis.z).lerp(-eye.normalized(), night).normalized())
		material.set_shader_parameter("sun_color", world.sun.light_color.lerp(Color(0.55, 0.62, 0.8), night))
		material.set_shader_parameter("night", night)
	material.set_shader_parameter("badness", gloom * 3.0)
	for c in clouds:
		c.fade_in = minf(1.0, float(c.fade_in) + delta / 4.0)
		# Andam com o vento (devagar: ~1,5 m/s).
		var g: Vector3 = (c.dir as Vector3) * planet_radius + wind * 1.5 * delta
		var dist := g.distance_to(eye_ground)
		if dist > RANGE * 1.05:
			# Saiu pela borda: volta pelo lado oposto (como no vrkumo).
			var mirrored := (eye_ground * 2.0 - g).normalized() * planet_radius
			var back := (mirrored - eye_ground).normalized() * RANGE * 0.98
			g = (eye_ground + back).normalized() * planet_radius
			c.fade_in = 0.0
		c.dir = g.normalized()
	sort_timer -= delta
	if sort_timer <= 0.0:
		sort_timer = 0.15
		_rebuild(eye, eye_ground, gloom)

func _rebuild(eye: Vector3, eye_ground: Vector3, gloom: float) -> void:
	var items: Array = []
	for c in clouds:
		var up: Vector3 = c.dir
		var center: Vector3 = up * (planet_radius + float(c.altitude))
		var dist := (up * planet_radius).distance_to(eye_ground)
		var alpha: float = float(c.fade_in) * (1.0 - smoothstep(RANGE * 0.82, RANGE * 1.02, dist)) * (1.0 - gloom)
		if alpha <= 0.01:
			continue
		# Eixos locais da nuvem: lateral perpendicular ao olhar, para os tufos se espalharem na tela.
		var to_eye := (eye - center).slide(up).normalized()
		var side := up.cross(to_eye).normalized()
		for p in c.parts:
			var o: Vector3 = p.offset
			var pos := center + side * o.x + up * o.y + to_eye * o.z
			items.append([pos.distance_squared_to(eye), pos, p, alpha, c.flip])
	items.sort_custom(func(a, b): return a[0] > b[0])
	var count := mini(items.size(), multimesh.instance_count)
	for i in count:
		var it: Array = items[i]
		var p: Dictionary = it[2]
		var s: float = p.size
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s * float(p.aspect), s)), it[1]))
		multimesh.set_instance_color(i, Color((float(p.variant) + 0.01) / 16.0, p.height, 1.0 if it[4] else 0.0, it[3]))
	multimesh.visible_instance_count = count
