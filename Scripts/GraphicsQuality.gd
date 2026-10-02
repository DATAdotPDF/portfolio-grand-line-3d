extends Node

## Qualidade gráfica em 3 níveis (Baixo / Médio / Alto), em três camadas:
## 1. Palpite: a página (godot_shell.html) olha o aparelho antes do download e manda
##    window.__portfolioGraphics = {mode, tier}; o pacote leve já parte do Baixo.
## 2. Medição: no modo Auto, se o FPS real ficar abaixo de LOW_FPS por alguns segundos,
##    desce um nível sozinho (nunca sobe sozinho, para não ficar oscilando).
## 3. Escolha: o menu (☰) força Auto/Alto/Médio/Baixo; fica salvo no navegador.

signal tier_changed(tier: int, automatic: bool)

enum { LOW, MEDIUM, HIGH }
const TIER_NAMES := ["Baixo", "Médio", "Alto"]
const MODE_TIERS := {"baixo": LOW, "medio": MEDIUM, "alto": HIGH}
const LOW_FPS := 24
const LOW_SECONDS := 4
const START_GRACE := 6

var world: Node
var tier := HIGH
var mode := "auto"
var base := {}
var low_seconds := 0
var grace := START_GRACE

func setup(owner_world: Node) -> void:
	world = owner_world
	_capture_base()
	# O navio fica sempre perto da câmera: compensa o limiar de LOD para as velas finas não sumirem.
	if is_instance_valid(world.ship):
		for mesh in world.ship.find_children("*", "GeometryInstance3D", true, false):
			(mesh as GeometryInstance3D).lod_bias = 8.0
	var hint := _read_hint()
	mode = str(hint.get("mode", "auto"))
	if MODE_TIERS.has(mode):
		tier = MODE_TIERS[mode]
	elif MODE_TIERS.has(str(hint.get("tier", ""))):
		tier = MODE_TIERS[str(hint.tier)]
	else:
		mode = "auto"
		tier = LOW if OS.has_feature("mobile_lite") else HIGH
	get_tree().node_added.connect(_tune_node)
	apply(tier)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_watch_fps)
	add_child(timer)
	print("GRAPHICS mode=%s tier=%s" % [mode, TIER_NAMES[tier]])

## Menu: "auto", "alto", "medio" ou "baixo".
func set_mode(new_mode: String) -> void:
	mode = new_mode
	low_seconds = 0
	grace = START_GRACE
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.setItem('portfolioGraphics', '%s'); } catch (e) {}" % mode)
	if MODE_TIERS.has(mode):
		apply(MODE_TIERS[mode])
	tier_changed.emit(tier, false)

func _watch_fps() -> void:
	if mode != "auto" or tier == LOW:
		return
	if grace > 0:
		grace -= 1
		return
	low_seconds = low_seconds + 1 if Engine.get_frames_per_second() < LOW_FPS else 0
	if low_seconds >= LOW_SECONDS:
		low_seconds = 0
		grace = START_GRACE
		apply(tier - 1)
		print("GRAPHICS auto -> %s" % TIER_NAMES[tier])
		tier_changed.emit(tier, true)

func _read_hint() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var raw := str(JavaScriptBridge.eval("JSON.stringify(window.__portfolioGraphics || {})", true))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}

func _capture_base() -> void:
	var viewport: Viewport = world.get_viewport()
	base = {
		"scale_mode": viewport.scaling_3d_mode, "scale": viewport.scaling_3d_scale, "msaa": viewport.msaa_3d,
		"lod": viewport.mesh_lod_threshold, "max_fps": Engine.max_fps, "ticks": Engine.physics_ticks_per_second,
		"steps": Engine.max_physics_steps_per_frame, "wake": world.ocean.wake_limit, "shadow": true,
	}
	if is_instance_valid(world.ocean_patch):
		base.patch_radius = world.ocean_patch.patch_radius
		base.patch_resolution = world.ocean_patch.resolution
	if is_instance_valid(world.sky_material):
		base.clouds = world.sky_material.get_shader_parameter("clouds_samples")
		base.cloud_shadow = world.sky_material.get_shader_parameter("shadow_samples")
	if world.environment != null:
		base.reflections = world.environment.reflected_light_source
		if world.environment.sky != null:
			base.radiance = world.environment.sky.radiance_size

func apply(new_tier: int) -> void:
	tier = clampi(new_tier, LOW, HIGH)
	var viewport: Viewport = world.get_viewport()
	var low := tier == LOW
	var high := tier == HIGH
	viewport.scaling_3d_mode = base.scale_mode if high else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = base.scale if high else (0.8 if tier == MEDIUM else 0.6)
	viewport.msaa_3d = base.msaa if high else Viewport.MSAA_DISABLED
	# LODs gerados no import: limiar maior troca para malhas mais simples mais cedo.
	viewport.mesh_lod_threshold = base.lod if high else (3.0 if tier == MEDIUM else 6.0)
	# 30 fps estáveis travam menos do que 45 oscilando; física a 30 Hz (interpolada) custa metade.
	Engine.max_fps = 30 if low else (60 if tier == MEDIUM else base.max_fps)
	Engine.physics_ticks_per_second = 30 if low else base.ticks
	Engine.max_physics_steps_per_frame = 3 if low else base.steps
	world.ocean.wake_limit = 10 if low else (16 if tier == MEDIUM else base.wake)
	if is_instance_valid(world.ocean_patch) and base.has("patch_radius"):
		world.ocean_patch.patch_radius = 150.0 if low else (200.0 if tier == MEDIUM else base.patch_radius)
		world.ocean_patch.resolution = 72 if low else (128 if tier == MEDIUM else base.patch_resolution)
	if is_instance_valid(world.sky_material) and base.has("clouds"):
		world.sky_material.set_shader_parameter("clouds_samples", 4 if low else (6 if tier == MEDIUM else base.clouds))
		world.sky_material.set_shader_parameter("shadow_samples", 1 if not high else base.cloud_shadow)
	if world.environment != null and base.has("reflections"):
		world.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if low else base.reflections
		if world.environment.sky != null and base.has("radiance"):
			world.environment.sky.radiance_size = Sky.RADIANCE_SIZE_32 if low else base.radiance
	if is_instance_valid(world.sun):
		world.sun.shadow_enabled = high
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		_tune_node(node)
		stack.append_array(node.get_children())

## Partículas pela metade e sem a luz decorativa das placas no Baixo (cada luz é mais uma passada no WebGL).
func _tune_node(node: Node) -> void:
	if node is GPUParticles3D:
		if not node.has_meta("base_amount"):
			node.set_meta("base_amount", node.amount)
		var target := maxi(2, int(node.get_meta("base_amount")) / 2) if tier == LOW else int(node.get_meta("base_amount"))
		if node.amount != target:
			node.amount = target
	elif node is OmniLight3D and node.name == "TitleWarmLight":
		node.visible = tier != LOW
