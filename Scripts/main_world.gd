@tool
extends Node3D

## Névoa de profundidade (m): em tempo bom só começa em FOG_BEGIN e fecha em FOG_END — tudo até
## ~300 m fica com a cor e a textura do modelo (Pedro, 2026-10-16: a névoa exponencial deixava baleia
## e ilhas quase brancas). Na tempestade ela vem para perto (FOG_STORM_*), como antes.
const FOG_BEGIN := 320.0
const FOG_END := 1600.0
const FOG_STORM_BEGIN := 25.0
const FOG_STORM_END := 380.0
const Shore = preload("res://Scripts/Shoreline.gd")
const NavalGame = preload("res://Scripts/NavalGame.gd")
const Sign = preload("res://Scenes/IslandTitleSign.tscn")
const Waves = preload("res://Scripts/SphericalOceanSimulation.gd")
const IslandEffects = preload("res://Scripts/IslandEffects.gd")
const GraphicsQuality = preload("res://Scripts/GraphicsQuality.gd")
const Sloop = preload("res://Scripts/sloop.gd")
const SeaAmbience = preload("res://Scripts/SeaAmbience.gd")
const Scale = preload("res://Scripts/WorldScale.gd")
const LogPose = preload("res://Scenes/LogPose_HUD.tscn")
const WindRibbon = preload("res://Scenes/WindRibbon.tscn")
const PortfolioCamera = preload("res://Scripts/PortfolioCameraController.gd")
const OceanPatchScript = preload("res://Scripts/OceanPatch.gd")
const TouchControlsScript = preload("res://Scripts/TouchControls.gd")
const PortfolioHUDScript = preload("res://Scripts/UI/PortfolioHUD.gd")
const RouteLineScript = preload("res://Scripts/RouteLine.gd")
const WeatherScript = preload("res://Scripts/Weather.gd")
const SeagullsScript = preload("res://Scripts/Seagulls.gd")
const SailForceDebugScript = preload("res://Scripts/SailForceDebug.gd")
const SeaLifeScript = preload("res://Scripts/SeaLife.gd")
const SeaBeastsScript = preload("res://Scripts/SeaBeasts.gd")
const GhostShipScript = preload("res://Scripts/GhostShip.gd")
const KrakenEventScript = preload("res://Scripts/KrakenEvent.gd")
const WorldDecorScript = preload("res://Scripts/WorldDecor.gd")
const EasterEggScreenScript = preload("res://Scripts/UI/EasterEggScreen.gd")
const SunFlareScript = preload("res://Scripts/SunFlare.gd")
const HDTexturesScript = preload("res://Scripts/HDTextures.gd")
const SkyCloudsScript = preload("res://Scripts/SkyClouds.gd")
const SHIP_LENGTH := 4.8
const SEABED_DEPTH := 25.0
const CORE_DEPTH := 30.0
const ISLANDS := [
	{"name":"Sobre", "file":"Optimized/Islands/island_sobre_parts.glb", "width":28.0},
	{"name":"Experiência", "file":"Optimized/Islands/island_experiencia_parts.glb", "width":32.0},
	{"name":"Formação", "file":"Optimized/Islands/island_formacao_parts.glb", "width":30.0},
	{"name":"Projetos", "file":"Optimized/Islands/island_projetos_parts.glb", "width":32.0},
	{"name":"Contato", "file":"Optimized/Islands/island_contato_parts.glb", "width":26.0}
]
const SHIP_PATH := "res://Assets/Optimized/sloop_clean_sail.glb"
## Pesos de madeira pendurados na amurada e na popa (Tools/extract_sloop_pendants.py), no mesmo
## espaço do modelo do barco; balançam como pêndulos (_swing_pendants).
const PENDANTS_PATH := "res://Assets/Optimized/sloop_pendants.glb"

## Configuração do mundo (raio, vento, ondas, lat/lon das ilhas). Edite aqui ou
## direto em Config/world_layout.tres: a cena 3D do editor se atualiza sozinha.
@export var world_layout: WorldLayout:
	get:
		return Scale.layout()
	set(value):
		if value != null and value != Scale.layout():
			Scale._layout = value
			_connect_layout()
			_update_editor_world()
## Um dia inteiro (12 min): dá para ver nascer e pôr do sol numa travessia entre duas ilhas.
@export var day_duration := 720.0
@export_range(0.0, 1.0) var day_phase := 0.12
var environment: Environment
var lantern: OmniLight3D
const LANTERN_POSITION := Vector3(0.0, 1.95, 2.2)
var lantern_swing := Vector2.ZERO
## [nó, ângulo (Vector2), velocidade angular, posição anterior, velocidade anterior, comprimento]
var pendants: Array[Dictionary] = []
## Carregamento na web: quando o mundo ficou jogável (ver _report_ready_to_page).
var build_started_msec := 0
var build_done_msec := 0
var frames_since_build := 0
var smooth_frames := 0
var ready_reported := false
var lantern_swing_vel := Vector2.ZERO
var lantern_prev_pos := Vector3.ZERO
var lantern_prev_vel := Vector3.ZERO
var lantern_enabled := true
var clock: Node
var wind_manager: Node
var music: AudioStreamPlayer
var sea_ambience: Node3D
var music_button: Button
var playlist: Array[String] = []
var music_bag: Array[String] = []
var current_track := ""
var web_music := false
var track_history: Array[String] = []
var history_index := -1
var music_paused := false
var web_music_timer := 0.0
var naval: Node3D
var time_mode := "auto"
var time_buttons: Array[Button] = []
var water_held := false
var water_cursor := Vector2.ZERO
var last_touch_point := Vector3.INF
var ocean: Node
var ocean_patch: MeshInstance3D
var ship: CharacterBody3D
var camera: PortfolioCamera
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_material: ShaderMaterial
var bow_wave_materials: Array[ShaderMaterial] = []
var water_droplets: GPUParticles3D
var droplet_emitters: Array[GPUParticles3D] = []
var sail_materials: Array[ShaderMaterial] = []
var flag_phase := 0.0
var sail_phase := 0.0
var smoothed_cloth_speed := 0.0
var sail_model: Node3D
# Leme na popa: gira no próprio eixo (dobradiça no cadaste) conforme o timão.
var rudder: Node3D
var rudder_rest := Basis.IDENTITY
const RUDDER_MAX_ANGLE := deg_to_rad(30.0)
var wind_streaks: Node3D
var bow_wave_meshes: Array[MeshInstance3D] = []
var islands: Array[Node3D] = []
var hud: CanvasLayer
var intro_orbit := false
var space_view := 0.0
var map_beacons: Array[MeshInstance3D] = []
var space_backdrop: CanvasLayer
var route_line: MeshInstance3D
var log_pose: Node3D
@export_group("Editor Planet")
@export_node_path("MeshInstance3D") var ocean_mesh_path: NodePath = ^"OceanMesh"
@export_node_path("MeshInstance3D") var ocean_patch_path: NodePath = ^"OceanPatch"
@export_node_path("MeshInstance3D") var seabed_mesh_path: NodePath = ^"SeabedMesh"
@export_node_path("Node3D") var island_anchors_path: NodePath = ^"IslandAnchors"
@export_node_path("CharacterBody3D") var player_ship_path: NodePath = ^"PlayerShip"
@export_node_path("Camera3D") var camera_path: NodePath = ^"CameraPivot/FollowCamera"
## Reposiciona a chalupa no spawn do layout ao editar (desligue para mover à mão).
@export var editor_snap_ship_to_spawn := true
## Mostra o cartão de apresentação com o globo ao abrir (desligue para testes).
@export var show_intro_on_start := true
var planet_radius := 800.0
var graphics: Node
## Clima (Weather/StormCell/Seagulls). storm_gloom: 0 fora das tempestades, 1 no miolo; storm_flash: clarão do relâmpago.
var weather: Node3D
var seagulls: Node3D
var sea_life: Node3D
## Bestas do mar (baleia, caranguejo, gigante) nos circuitos do WorldDecor.
var sea_beasts: Node3D
var ghost_ship: Node3D
var kraken_event: Node3D
## Pontos de interesse entre as ilhas (faróis, rochas, naufrágios, boias...).
var world_decor: Node3D
var easter_egg: CanvasLayer
## Números da viagem (cartões dos easter eggs): tempo navegando e distância percorrida.
var adventure_seconds := 0.0
## Mapa: sol no espaço e lado da noite do globo (mostra o planeta girando na frente do sol).
var map_sun: MeshInstance3D
var night_side: MeshInstance3D
var night_side_material: ShaderMaterial
var sky_text_timer := 0.0
var distance_sailed := 0.0
var storm_gloom := 0.0
var storm_flash := 0.0
## Clarão só do céu e da névoa (trovão distante).
var sky_flash := 0.0

func _connect_layout() -> void:
	var layout := Scale.layout()
	if not layout.changed.is_connected(_on_layout_changed):
		layout.changed.connect(_on_layout_changed)

func _on_layout_changed() -> void:
	planet_radius = Scale.radius()
	if Engine.is_editor_hint():
		_update_editor_world()

func _ready() -> void:
	build_started_msec = Time.get_ticks_msec()
	# Toda malha do jogo em resolução máxima (o LOD automático colapsava os modelos do Meshy).
	get_tree().node_added.connect(_force_full_detail)
	for node in find_children("*", "GeometryInstance3D", true, false):
		_force_full_detail(node)
	planet_radius = Scale.radius()
	_connect_layout()
	if Engine.is_editor_hint():
		_update_editor_world()
		return
	clock = get_node("/root/DayNightCycle")
	clock.day_duration_seconds = day_duration
	wind_manager = get_node_or_null("/root/WindManager")
	ocean = Waves.new()
	ocean.name = "OceanSimulation"
	add_child(ocean)
	_build_ocean()
	# Depois que céu, luzes, barco e efeitos existem.
	_setup_graphics.call_deferred()
	_build_islands()
	_update_island_coasts()
	_build_ship()
	_build_lighting()
	_build_bow_wave()
	_build_wind_streaks()
	_build_weather()
	_setup_cloud_shadows()
	_build_map_beacons()
	_build_space_backdrop()
	route_line = RouteLineScript.new()
	route_line.name = "RouteLine"
	route_line.ship = ship
	route_line.ocean = ocean
	add_child(route_line)
	_build_hud()
	_build_log_pose()
	_build_audio()
	camera = get_node_or_null(camera_path) as PortfolioCamera
	if camera == null:
		camera = PortfolioCamera.new()
		camera.name = "FollowCamera"
		add_child(camera)
	camera.boat = ship
	camera.islands = islands
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = 65.0
	camera.near = 0.15
	camera.far = planet_radius * 4.5
	camera.current = true
	camera.snap_to_boat()
	_build_titles()
	naval = NavalGame.new()
	naval.name = "NavalGame"
	naval.world = self
	add_child(naval)
	naval.time_attack_finished.connect(func(completed: bool, hits: int, total: int, seconds_used: float, _events: Array[Dictionary]):
		hud.show_race_result(completed, hits, total, seconds_used))
	camera.island_visit_started.connect(_on_island_visit_started)
	var touch := TouchControlsScript.new()
	touch.name = "TouchControls"
	touch.ship = ship
	touch.naval = naval
	touch.camera = camera
	add_child(touch)
	# Abertura (como no nazarejose): o globo gira atrás do cartão de apresentação.
	# Um link direto (?ilha= / ?modo=) pula a abertura.
	var search := str(JavaScriptBridge.eval("window.location.search", true)) if OS.has_feature("web") else ""
	if search.contains("perf"):
		_build_perf_overlay()
	var deeplink := search.length() > 1 and not search.begins_with("?perf")
	if deeplink:
		_apply_web_deeplink.call_deferred()
	elif show_intro_on_start:
		ship.enabled = false
		hud.show_intro(true)
		# Órbita cinematográfica em volta da ilha de spawn, deslocada para o lado do cartão.
		intro_orbit = true
		camera.focus_island(islands[clampi(Scale.layout().spawn_island, 0, islands.size() - 1)])
		camera.h_offset = -15.0 if get_viewport().get_visible_rect().size.x > get_viewport().get_visible_rect().size.y else 0.0
	build_done_msec = Time.get_ticks_msec()
	# Página: mundo montado; agora vêm os primeiros quadros (compilação dos shaders).
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__worldBuilt && window.__worldBuilt(%d)" % (build_done_msec - build_started_msec), true)
	print("WORLD_READY radius=", planet_radius, " ship_length=", SHIP_LENGTH, " islands=", islands.size(), " max_wave=", snappedf(Scale.max_wave_height(), 0.01))

# --- Editor: o mundo inteiro acompanha o layout sem precisar do Play ---------------

func _update_editor_world() -> void:
	if not is_inside_tree():
		return
	planet_radius = Scale.radius()
	_apply_planet_geometry()
	var anchors := get_node_or_null(island_anchors_path)
	if anchors != null and anchors.has_method("apply_layout"):
		anchors.apply_layout()
	var materials := _ocean_materials()
	for material in materials:
		Scale.push_wave_uniforms(material)
		material.set_shader_parameter("boat_cutout_enabled", false)
		material.set_shader_parameter("use_simulation_time", false)
	_push_island_coasts(materials)
	var ship_node := get_node_or_null(player_ship_path) as Node3D
	if ship_node != null and editor_snap_ship_to_spawn:
		ship_node.global_transform = _spawn_transform()
	var wind_node := get_node_or_null("WindRibbonSystem")
	if wind_node != null:
		wind_node.set("wind_direction", Scale.wind_axis())
	_place_editor_cameras(ship_node)

func _apply_planet_geometry() -> void:
	var ocean_node := get_node_or_null(ocean_mesh_path) as MeshInstance3D
	if ocean_node != null:
		var sphere := ocean_node.mesh as SphereMesh
		if sphere != null and not is_equal_approx(sphere.radius, planet_radius):
			sphere.radius = planet_radius
			sphere.height = planet_radius * 2.0
		ocean_node.extra_cull_margin = Scale.max_wave_height() + 4.0
	var bed_node := get_node_or_null(seabed_mesh_path) as MeshInstance3D
	if bed_node != null:
		var bed_sphere := bed_node.mesh as SphereMesh
		if bed_sphere != null:
			bed_sphere.radius = planet_radius - SEABED_DEPTH
			bed_sphere.height = (planet_radius - SEABED_DEPTH) * 2.0
	var core := get_node_or_null("PlanetCore/CollisionShape3D") as CollisionShape3D
	if core != null and core.shape is SphereShape3D:
		(core.shape as SphereShape3D).radius = planet_radius - CORE_DEPTH

func _ocean_materials() -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	for path in [ocean_mesh_path, ocean_patch_path]:
		var node := get_node_or_null(path) as MeshInstance3D
		if node != null and node.material_override is ShaderMaterial and not result.has(node.material_override):
			result.append(node.material_override)
	return result

func _island_coast_data() -> Array:
	var centers := PackedVector3Array()
	var radii := PackedFloat32Array()
	var anchors := get_node_or_null(island_anchors_path)
	if anchors != null:
		for index in range(mini(anchors.get_child_count(), ISLANDS.size())):
			var anchor := anchors.get_child(index) as Node3D
			centers.append(anchor.global_position.normalized())
			radii.append(float(ISLANDS[index].width) * 0.46)
	return [centers, radii]

func _push_island_coasts(materials: Array[ShaderMaterial]) -> void:
	var data := _island_coast_data()
	for material in materials:
		material.set_shader_parameter("island_centers", data[0])
		material.set_shader_parameter("island_radii", data[1])

func _update_island_coasts() -> void:
	var data := _island_coast_data()
	ocean.set_islands(data[0], data[1])

var calm_timer := 0.0

## Mar calmo em volta das ilhas/rochas/POIs do mapa como nas 5 ilhas (assim dá para nivelar cada uma
## na água certa). Só as fixas: boias, caixas e o que flutua/paira ficam no mar normal. O shader tem
## lugar para 16: vão as 16 mais perto do barco, refeitas 2× por segundo (a tartaruga anda).
func _update_calm_spots(delta: float) -> void:
	calm_timer -= delta
	if calm_timer > 0.0 or world_decor == null or ocean == null or not ocean.has_method("set_calm_spots"):
		return
	calm_timer = 0.5
	var eye: Vector3 = ship.global_position
	var near: Array = []
	for item in world_decor.items:
		if bool(item.get("float", false)) or float(item.get("hover", 0.0)) > 0.0:
			continue
		var root: Node3D = item.root
		if not is_instance_valid(root):
			continue
		var d := root.global_position.distance_to(eye)
		if d < 700.0:
			near.append([d, root.global_position.normalized(), float(item.get("radius", 10.0))])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var spots: Array[Vector4] = []
	for entry in near.slice(0, 16):
		var dir: Vector3 = entry[1]
		spots.append(Vector4(dir.x, dir.y, dir.z, entry[2]))
	ocean.set_calm_spots(spots)

## Spawn: a spawn_distance metros da ilha escolhida, proa voltada para ela.
func _spawn_transform() -> Transform3D:
	var layout := Scale.layout()
	var index := clampi(layout.spawn_island, 0, maxi(layout.islands.size() - 1, 0))
	if layout.islands.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3.UP * planet_radius)
	var island_basis := Scale.anchor_transform(layout.islands[index], planet_radius).basis
	var island_up := island_basis.y
	var outward := island_basis.z.rotated(island_up, deg_to_rad(layout.spawn_bearing_deg))
	var axis := island_up.cross(outward).normalized()
	var up := island_up.rotated(axis, layout.spawn_distance / planet_radius).normalized()
	var heading := (island_up - up * up.dot(island_up)).normalized()
	return Transform3D(Basis(heading.cross(up).normalized(), up, -heading), up * planet_radius)

func _place_editor_cameras(ship_node: Node3D) -> void:
	if ship_node == null:
		return
	var up := ship_node.global_position.normalized()
	var forward := -ship_node.global_basis.z
	var eye := ship_node.global_position - forward * 12.0 + up * 5.0
	for path in [^"CameraPivot", ^"OceanPreviewCamera"]:
		var node := get_node_or_null(path) as Node3D
		if node == null:
			continue
		node.global_position = eye
		node.look_at(ship_node.global_position + up * 1.5, up)
	var follow := get_node_or_null(camera_path) as Camera3D
	if follow != null:
		follow.transform = Transform3D.IDENTITY
		follow.far = planet_radius * 4.5
	var preview := get_node_or_null("OceanPreviewCamera") as Camera3D
	if preview != null:
		preview.far = planet_radius * 4.5

# --- Construção em runtime ------------------------------------------------------------

## Qualidade gráfica automática (ver Scripts/GraphicsQuality.gd) + escolha no menu.
func _setup_graphics() -> void:
	graphics = GraphicsQuality.new()
	graphics.name = "GraphicsQuality"
	add_child(graphics)
	graphics.setup(self)
	if hud:
		hud.set_graphics_state(graphics.mode, GraphicsQuality.TIER_NAMES[graphics.tier])
		hud.graphics_pressed.connect(graphics.set_mode)
		graphics.tier_changed.connect(func(tier: int, automatic: bool):
			hud.set_graphics_state(graphics.mode, GraphicsQuality.TIER_NAMES[tier])
			if automatic:
				hud.show_toast("Gráficos ajustados para %s · mude no menu ☰" % GraphicsQuality.TIER_NAMES[tier]))
## Diagnóstico (?perf=1): números do quadro na tela e no console, para medir no aparelho real.
func _build_perf_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(8, 70)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.YELLOW)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(func():
		var text := "fps %d | cpu %.1f ms | fís %.1f ms\ndraw %d | obj %d | tri %dk | vram %d MB | %s" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
			int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
			("lite" if OS.has_feature("mobile_lite") else "full") + (" · " + GraphicsQuality.TIER_NAMES[graphics.tier] if graphics else "")]
		label.text = text
		print("PERF ", text.replace("\n", " | ")))


func _build_ocean() -> void:
	_apply_planet_geometry()
	var ocean_mesh := get_node_or_null(ocean_mesh_path) as MeshInstance3D
	if ocean_mesh.material_override == null:
		var material := ShaderMaterial.new()
		material.shader = load("res://Shaders/ocean.gdshader")
		ocean_mesh.material_override = material
	ocean_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean.register_material(ocean_mesh.material_override)
	ocean_patch = get_node_or_null(ocean_patch_path) as MeshInstance3D
	if ocean_patch == null:
		ocean_patch = MeshInstance3D.new()
		ocean_patch.name = "OceanPatch"
		ocean_patch.set_script(OceanPatchScript)
		var patch_material := ShaderMaterial.new()
		patch_material.shader = load("res://Shaders/ocean_patch.gdshader")
		ocean_patch.material_override = patch_material
		add_child(ocean_patch)
	ocean.register_material(ocean_patch.material_override)

func _model_bounds(node: Node3D) -> AABB:
	var total := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var relative: Transform3D = node.global_transform.affine_inverse() * mesh.global_transform
		var bounds: AABB = relative * mesh.get_aabb()
		total = bounds if first else total.merge(bounds)
		first = false
	return total

func _build_islands() -> void:
	var anchors := get_node(island_anchors_path)
	if anchors.has_method("apply_layout"):
		anchors.apply_layout()
	for index in range(ISLANDS.size()):
		var data: Dictionary = ISLANDS[index]
		var mount := anchors.get_child(index) as Node3D
		var model := mount.get_node_or_null("IslandModel") as Node3D
		if model == null:
			model = (load("res://Assets/" + data.file) as PackedScene).instantiate() as Node3D
			model.name = "IslandModel"
			var raw := _model_bounds(model)
			model.scale = Vector3.ONE * float(data.width) / maxf(raw.size.x, raw.size.z)
			mount.add_child(model)
			if anchors.has_method("apply_layout"):
				anchors.apply_layout()
		if not mount.has_meta("section"):
			mount.set_meta("section", data.name)
		var bounds := _model_bounds(model)
		var factor: float = model.scale.x
		if index == 0:
			_remove_harbor_baked_water(model, bounds, factor)
		var waterline_fraction: float = maxf(0.0,
			-(model.position.y + bounds.position.y * factor)
			/ maxf(bounds.size.y * factor, 0.001))
		mount.set_meta("waterline_fraction", waterline_fraction)
		# Footprint metadata for reference only. Navigation uses the actual coast walls.
		var footprint := Vector2(maxf(absf(bounds.position.x), absf(bounds.end.x)), maxf(absf(bounds.position.z), absf(bounds.end.z))).length() * factor
		mount.set_meta("navigation_radius", footprint + SHIP_LENGTH * 0.5 + 0.4)
		# Static triangle collision follows the actual island silhouette.
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh:
				mesh.create_trimesh_collision()
		Shore.build(mount, model, planet_radius)
		var harbor := Area3D.new()
		harbor.name = "HarborArea"
		harbor.collision_layer = 0
		harbor.collision_mask = 2
		var zone := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = float(data.width) * 0.5 + 6.0
		zone.shape = shape
		harbor.add_child(zone)
		mount.add_child(harbor)
		_tone_down_island(model)
		var effects := IslandEffects.new()
		effects.name = "IslandEffects"
		effects.index = index
		effects.model = model
		effects.bounds = bounds
		effects.factor = factor
		mount.add_child(effects)
		islands.append(mount)

## As ilhas do Meshy vêm com texturas muito claras sob o sol toon: escurece um pouco.
func _tone_down_island(model: Node3D) -> void:
	for instance in model.find_children("*", "MeshInstance3D", true, false):
		for surface in range(instance.mesh.get_surface_count()):
			var material := instance.get_active_material(surface) as StandardMaterial3D
			if material and not material.has_meta("toned"):
				material.albedo_color = Color(0.8, 0.8, 0.82)
				material.roughness = maxf(material.roughness, 0.85)
				material.metallic_specular = 0.2
				material.set_meta("toned", true)

func _remove_harbor_baked_water(model: Node3D, bounds: AABB, _factor: float) -> void:
	# Remove baked turquoise water triangles from a runtime copy. Keep pier vertices intact.
	for instance in model.find_children("*", "MeshInstance3D", true, false):
		var original: Mesh = instance.mesh
		var replacement := ArrayMesh.new()
		var relative: Transform3D = model.global_transform.affine_inverse() * instance.global_transform
		for surface in range(original.get_surface_count()):
			var arrays := original.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var material: Material = instance.get_active_material(surface)
			var colors: Image
			if material is StandardMaterial3D and material.albedo_texture:
				colors = material.albedo_texture.get_image()
				if colors.is_compressed():
					colors.decompress()
			var kept := PackedInt32Array()
			for triangle in range(0,indices.size(),3):
				var ia := indices[triangle]
				var ib := indices[triangle+1]
				var ic := indices[triangle+2]
				var point := relative * ((vertices[ia]+vertices[ib]+vertices[ic])/3.0)
				var height := (point.y-bounds.position.y)/bounds.size.y
				var water := false
				if colors and height < 0.245:
					var uv := (uvs[ia]+uvs[ib]+uvs[ic])/3.0
					var color := colors.get_pixel(clampi(int(uv.x*colors.get_width()),0,colors.get_width()-1),clampi(int(uv.y*colors.get_height()),0,colors.get_height()-1))
					water = color.g > color.r*1.04 and color.b > color.r*1.09
				if not water:
					kept.append_array(PackedInt32Array([ia,ib,ic]))
			arrays[Mesh.ARRAY_INDEX] = kept
			replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			replacement.surface_set_material(surface,original.surface_get_material(surface))
		# Sem LOD gerado (simplificava a malha do Meshy e deixava as faces "quebradas").
		instance.mesh = replacement

var ripple_timer := 0.0
var ripple_cursor := 0

## Tudo o que se mexe encostado na água faz ondinhas (ocean.touch, as mesmas do tiro na água):
## boias e caixas balançando, nadadeiras da tartaruga e o casco do navio fantasma. Só perto da
## câmera e poucas por vez (o mar tem 32 ondinhas no total, divididas com os tiros).
func _update_contact_ripples(delta: float) -> void:
	ripple_timer -= delta
	if ripple_timer > 0.0 or world_decor == null or ocean == null or not ocean.has_method("touch"):
		return
	ripple_timer = 0.45
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else ship.global_position
	var items: Array = world_decor.items
	if items.is_empty():
		return
	# Boias e caixas: até 2 por vez, em rodízio.
	var sent := 0
	for k in items.size():
		ripple_cursor = (ripple_cursor + 1) % items.size()
		var item: Dictionary = items[ripple_cursor]
		if not bool(item.get("float", false)):
			continue
		var root_node: Node3D = item.root
		if is_instance_valid(root_node) and root_node.global_position.distance_to(eye) < 90.0:
			ocean.touch(root_node.global_position, 0.07, 1.6)
			sent += 1
			if sent >= 2:
				break
	# Tartaruga: as nadadeiras batendo na superfície.
	var turtle: Dictionary = world_decor.get("turtle")
	if not turtle.is_empty():
		var t_root: Node3D = turtle.item.root
		if is_instance_valid(t_root) and t_root.global_position.distance_to(eye) < 220.0:
			var up := t_root.global_position.normalized()
			var side := t_root.global_basis.x.slide(up).normalized()
			var fwd := (-t_root.global_basis.z).slide(up).normalized()
			var r := float(turtle.item.get("radius", 20.0))
			var flip := 1.0 if Engine.get_process_frames() % 2 == 0 else -1.0
			ocean.touch(t_root.global_position + side * flip * r * 0.9 + fwd * r * 0.3, 0.22, 2.4)
	# Navio fantasma navegando.
	if is_instance_valid(ghost_ship) and ghost_ship.visible and bool(ghost_ship.get("active")):
		if ghost_ship.global_position.distance_to(eye) < 140.0:
			ocean.touch(ghost_ship.global_position, 0.15, 2.2)

func _force_full_detail(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).lod_bias = maxf((node as GeometryInstance3D).lod_bias, 2.0)
	if node is MeshInstance3D:
		_tame_meshy_metal.call_deferred(node)

## Os modelos do Meshy vêm com metallic = 1 × textura de metal: pedra, madeira, musgo e carne viravam
## metal espelhado, refletiam o céu claro e ficavam quase brancos (tartaruga, baleia colosso).
## Nada disso é metal: o fator cai para quase zero (sobra um brilho leve) e o especular baixa.
## O barco tem materiais próprios e fica de fora. Cada material é ajustado uma vez (recurso dividido).
func _tame_meshy_metal(node: Node) -> void:
	var mesh := node as MeshInstance3D
	if not is_instance_valid(mesh) or mesh.mesh == null or (is_instance_valid(ship) and ship.is_ancestor_of(mesh)):
		return
	for i in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(i) as StandardMaterial3D
		if material == null or material.has_meta("metal_tamed"):
			continue
		material.set_meta("metal_tamed", true)
		if material.metallic > 0.3 and material.metallic_texture != null:
			material.metallic = 0.08
			material.metallic_specular = minf(material.metallic_specular, 0.3)

func _build_ship() -> void:
	ship = get_node_or_null(player_ship_path) as CharacterBody3D
	if ship == null:
		ship = Sloop.new()
		ship.name = "PlayerShip"
		add_child(ship)
	var spawn := _spawn_transform()
	ship.global_transform = spawn
	ship.ocean = ocean
	ship.islands = islands
	ship.heading = -spawn.basis.z
	var visual := ship.get_node_or_null("HullVisualContainer") as Node3D
	if visual == null:
		visual = Node3D.new()
		visual.name = "HullVisualContainer"
		ship.add_child(visual)
	ship.float_visual = visual
	var model := visual.get_node_or_null("ShipModel") as Node3D
	var created_model := model == null
	if model == null:
		model = (load(SHIP_PATH) as PackedScene).instantiate() as Node3D
		model.name = "ShipModel"
		visual.add_child(model)
	sail_model = model
	_attach_pendants(model)
	rudder = model.find_child("Rudder", true, false) as Node3D
	if rudder:
		rudder_rest = rudder.basis
	var bounds := _model_bounds(model)
	if created_model:
		var factor := SHIP_LENGTH / bounds.size.x
		model.scale = Vector3.ONE * factor
		model.rotation.y = -PI * 0.5
		model.position.y = -(bounds.position.y + bounds.size.y * 0.12) * factor
	var collider := ship.get_node_or_null("HullCollision") as CollisionShape3D
	if collider == null:
		collider = CollisionShape3D.new()
		collider.name = "HullCollision"
		ship.add_child(collider)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.60
	capsule.height = 3.8
	collider.shape = capsule
	collider.rotation.x = PI * 0.5
	collider.position.y = 0.3
	# O modelo vem em partes (Hull, Sail_Main, Sail_Stern, Flag, Rudder): só pano recebe o shader de vento,
	# e a Jolly Roger só na vela principal (antes ela vazava para a proa branca do casco).
	for instance in model.find_children("*", "MeshInstance3D", true, false):
		if not instance.name in ["Sail_Main", "Sail_Stern", "Flag"]:
			continue
		for surface in range(instance.mesh.get_surface_count()):
			var old: Material = instance.get_active_material(surface)
			if old is StandardMaterial3D and old.albedo_texture:
				var cloth := ShaderMaterial.new()
				cloth.shader = load("res://Shaders/sail_wind.gdshader")
				cloth.set_shader_parameter("albedo_map",old.albedo_texture)
				# Cada peça enche (ou tremula) pela própria caixa (espaço da malha, o mesmo do VERTEX no shader).
				var box: AABB = instance.mesh.get_aabb()
				cloth.set_shader_parameter("part", ["Sail_Main", "Sail_Stern", "Flag"].find(instance.name))
				cloth.set_shader_parameter("sail_min", box.position)
				cloth.set_shader_parameter("sail_max", box.end)
				cloth.set_shader_parameter("jolly_roger",load("res://Assets/JollyRoger.png"))
				cloth.set_shader_parameter("emblem", 1.0 if instance.name == "Sail_Main" else 0.0)
				instance.set_surface_override_material(surface,cloth)
				sail_materials.append(cloth)
	# Lampião de popa (o barco do Wind Waker não tem luz própria; a ideia aqui é nossa):
	# pendurado na popa, ilumina convés e velas e aparece de longe como um ponto quente.
	lantern = visual.get_node_or_null("CabinLantern") as OmniLight3D
	if lantern == null:
		lantern = OmniLight3D.new()
		lantern.name = "CabinLantern"
		visual.add_child(lantern)
	lantern.position = LANTERN_POSITION
	lantern.light_color = Color(1.0, 0.62, 0.28)
	lantern.omni_range = 7.5
	lantern.omni_attenuation = 1.3
	lantern.shadow_enabled = false
	if lantern.get_node_or_null("Body") == null:
		lantern.add_child(_build_lantern_body())

## Tempestades (espalhadas entre as ilhas, longe das rotas) e gaivotas.
## Avisa a página (Export/godot_shell.html) que o mundo está jogável de verdade: montado e já
## desenhando quadros rápidos (os shaders compilam nos primeiros quadros, escondidos atrás do
## cartão). Antes o cartão sumia quando o motor iniciava, e o jogo ficava travado alguns segundos.
func _report_ready_to_page() -> void:
	if ready_reported or build_done_msec == 0:
		return
	frames_since_build += 1
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	# 20 quadros depois de montar, e 5 seguidos sem engasgo (< 50 ms), ou 8 s de teto.
	smooth_frames = smooth_frames + 1 if get_process_delta_time() < 0.05 else 0
	var waited := Time.get_ticks_msec() - build_done_msec
	if not ((frames_since_build >= 20 and smooth_frames >= 5) or waited > 8000):
		return
	ready_reported = true
	var info := {"build_ms": build_done_msec - build_started_msec, "warmup_ms": waited, "frames": frames_since_build}
	print("PAGE_READY ", info, " frame_ms=", snappedf(frame_ms, 0.1))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__worldReady && window.__worldReady(%s)" % JSON.stringify(info), true)

## Lampião como pêndulo (comprimento ~0,4 m): pendurado na vertical do mundo e empurrado pela
## aceleração do ponto de pendura (arrancada, freada, curva, sobe-e-desce e rolagem nas ondas).
func _swing_lantern(delta: float) -> void:
	if delta <= 0.0:
		return
	var visual: Node3D = ship.float_visual
	var anchor: Vector3 = lantern.global_position
	var vel := (anchor - lantern_prev_pos) / delta
	var accel := (vel - lantern_prev_vel) / delta
	lantern_prev_pos = anchor
	lantern_prev_vel = vel
	if accel.length() > 60.0:  # teleporte/primeiro quadro
		accel = Vector3.ZERO
	var basis_world: Basis = visual.global_basis.orthonormalized()
	var local_accel := basis_world.inverse() * accel
	var up_world := anchor.normalized()
	# Ângulo de "pendurado reto" no referencial do barco (compensa a inclinação do casco).
	var up_local := basis_world.inverse() * up_world
	var rest := Vector2(atan2(-up_local.z, up_local.y), atan2(up_local.x, up_local.y))
	# Pêndulo: θ'' = -(g/L)·(θ - repouso) - amortecimento·θ' - a/L.
	var g_over_l := 9.8 / 0.4
	var drive := Vector2(local_accel.z, -local_accel.x) / 0.4
	lantern_swing_vel += (-(lantern_swing - rest) * g_over_l - lantern_swing_vel * 1.6 - drive * 0.35) * delta
	lantern_swing += lantern_swing_vel * delta
	lantern_swing = lantern_swing.clamp(Vector2(-0.7, -0.7), Vector2(0.7, 0.7))
	lantern.rotation = Vector3(lantern_swing.x, 0.0, lantern_swing.y)

func _attach_pendants(model: Node3D) -> void:
	if not ResourceLoader.exists(PENDANTS_PATH) or model.find_child("Pendants", false, false):
		return
	var scene: Node3D = (load(PENDANTS_PATH) as PackedScene).instantiate()
	scene.name = "Pendants"
	model.add_child(scene)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.28, 0.15)
	wood.roughness = 0.8
	for node in scene.find_children("Pendant_*", "", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		mesh.material_override = wood
		var length := maxf(0.2, mesh.get_aabb().size.y * model.scale.y)
		pendants.append({"node": mesh, "rest": mesh.basis, "swing": Vector2.ZERO, "vel": Vector2.ZERO,
			"prev_pos": Vector3.ZERO, "prev_vel": Vector3.ZERO, "length": length})

## Pêndulos dos pesos de madeira: mesma conta do lampião (aceleração do ponto de fixação e
## inclinação do casco), cada um com o seu comprimento; balançam com o roll e o pitch nas ondas.
func _swing_pendants(delta: float) -> void:
	if delta <= 0.0:
		return
	for p in pendants:
		var node: MeshInstance3D = p.node
		var anchor: Vector3 = node.global_position
		var vel: Vector3 = (anchor - (p.prev_pos as Vector3)) / delta
		var accel: Vector3 = (vel - (p.prev_vel as Vector3)) / delta
		p.prev_pos = anchor
		p.prev_vel = vel
		if accel.length() > 60.0:
			accel = Vector3.ZERO
		var parent_basis: Basis = (node.get_parent() as Node3D).global_basis.orthonormalized()
		var local_accel := parent_basis.inverse() * accel
		var up_local := parent_basis.inverse() * anchor.normalized()
		var rest := Vector2(atan2(-up_local.z, up_local.y), atan2(up_local.x, up_local.y))
		var length: float = p.length
		var swing: Vector2 = p.swing
		var swing_vel: Vector2 = p.vel
		swing_vel += (-(swing - rest) * (9.8 / length) - swing_vel * 1.2 - Vector2(local_accel.z, -local_accel.x) / length * 0.35) * delta
		swing += swing_vel * delta
		swing = swing.clamp(Vector2(-0.8, -0.8), Vector2(0.8, 0.8))
		p.swing = swing
		p.vel = swing_vel
		node.basis = Basis.from_euler(Vector3(swing.x, 0.0, swing.y)) * (p.rest as Basis)

## Respingo em "V" dos dois lados da proa (batida em onda ou queda de salto).
func _on_ship_splash(at: Vector3, strength: float) -> void:
	if weather == null or weather.spray == null:
		return
	var right: Vector3 = ship.heading.cross(at.normalized()).normalized()
	# Lençol em "V" (como no Sea of Thieves): muitos tufos grandes jogados para fora e para cima.
	for side in [-1.0, 1.0]:
		weather.spray.burst(at + right * side * 1.1, int(4.0 + 4.0 * strength), strength * 1.6, 2.2)

## Corpo do lampião: alça, tampa e base escuras, vidro quente emissivo e um halo aditivo
## (billboard) que deixa o ponto de luz visível de longe. Pendura abaixo do ponto da luz.
func _build_lantern_body() -> Node3D:
	var body := Node3D.new()
	body.name = "Body"
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.12, 0.1, 0.09)
	iron.roughness = 0.8
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(1.0, 0.78, 0.45)
	var parts := [
		# [malha, posição, material]
		[_cylinder(0.11, 0.0, 0.06, 6), Vector3(0, -0.06, 0), iron],      # tampa (cone)
		[_cylinder(0.08, 0.08, 0.2, 6), Vector3(0, -0.2, 0), glass],      # vidro
		[_cylinder(0.1, 0.1, 0.04, 6), Vector3(0, -0.32, 0), iron],       # base
		[_cylinder(0.012, 0.012, 0.12, 4), Vector3(0, 0.02, 0), iron],   # alça
	]
	for part in parts:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = part[0]
		mesh_instance.position = part[1]
		mesh_instance.material_override = part[2]
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if part[2] == glass:
			mesh_instance.name = "Glass"
		body.add_child(mesh_instance)
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
	halo.mesh = quad
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(0.5, 0.0)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	glow.gradient = ramp
	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_material.albedo_texture = glow
	halo_material.albedo_color = Color(1.0, 0.7, 0.35, 0.0)
	halo_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	halo_material.render_priority = 2
	halo.material_override = halo_material
	halo.position = Vector3(0, -0.2, 0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(halo)
	return body

func _cylinder(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh

func _build_weather() -> void:
	# Ilhas/rochas do mapa antes do clima: os ciclones e tempestades desviam delas.
	world_decor = WorldDecorScript.new()
	world_decor.name = "WorldDecor"
	world_decor.world = self
	world_decor.planet_radius = planet_radius
	add_child(world_decor)
	weather = WeatherScript.new()
	weather.name = "Weather"
	weather.world = self
	weather.ship = ship
	weather.ocean = ocean
	weather.planet_radius = planet_radius
	add_child(weather)
	seagulls = SeagullsScript.new()
	seagulls.name = "Seagulls"
	seagulls.world = self
	seagulls.ship = ship
	seagulls.planet_radius = planet_radius
	add_child(seagulls)
	ship.splash.connect(_on_ship_splash)
	sea_life = SeaLifeScript.new()
	sea_life.name = "SeaLife"
	sea_life.world = self
	sea_life.ship = ship
	sea_life.ocean = ocean
	sea_life.planet_radius = planet_radius
	add_child(sea_life)
	sea_beasts = SeaBeastsScript.new()
	sea_beasts.name = "SeaBeasts"
	sea_beasts.world = self
	sea_beasts.ship = ship
	sea_beasts.ocean = ocean
	sea_beasts.planet_radius = planet_radius
	add_child(sea_beasts)
	# Site: texturas originais (até 4K) dos modelos perto do barco; sem manifesto (editor) fica parado.
	var hd_textures := HDTexturesScript.new()
	hd_textures.name = "HDTextures"
	hd_textures.world = self
	add_child(hd_textures)
	# Navio fantasma: só à noite, em mar aberto.
	ghost_ship = GhostShipScript.new()
	ghost_ship.name = "GhostShip"
	ghost_ship.world = self
	ghost_ship.ship = ship
	ghost_ship.ocean = ocean
	ghost_ship.planet_radius = planet_radius
	add_child(ghost_ship)
	# Encontro com o kraken (redemoinho para escapar) e o cartão dos easter eggs.
	kraken_event = KrakenEventScript.new()
	kraken_event.name = "KrakenEvent"
	kraken_event.world = self
	add_child(kraken_event)
	easter_egg = EasterEggScreenScript.new()
	easter_egg.name = "EasterEggScreen"
	easter_egg.world = self
	add_child(easter_egg)
	# Flare do sol (estudo do Wind Waker).
	var flare := SunFlareScript.new()
	flare.name = "SunFlare"
	flare.world = self
	add_child(flare)
	# Nuvens do céu com os tufos volumétricos (estudo do vrkumo do Wind Waker).
	var sky_clouds := SkyCloudsScript.new()
	sky_clouds.name = "SkyClouds"
	sky_clouds.world = self
	sky_clouds.planet_radius = planet_radius
	add_child(sky_clouds)
	# Setas de força da vela: só rodando pelo editor do Godot (F3), nunca no site.
	if OS.has_feature("editor"):
		var debug_arrows := SailForceDebugScript.new()
		debug_arrows.name = "SailForceDebug"
		debug_arrows.ship = ship
		add_child(debug_arrows)

func _build_lighting() -> void:
	var node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if node == null:
		node = WorldEnvironment.new()
		node.name = "WorldEnvironment"
		add_child(node)
	environment = node.environment
	if environment == null:
		environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := environment.sky
	if sky == null:
		sky = Sky.new()
		environment.sky = sky
	sky_material = sky.sky_material as ShaderMaterial
	if sky_material == null:
		sky_material = ShaderMaterial.new()
		sky_material.shader = load("res://Shaders/radial_sky.gdshader")
		sky.sky_material = sky_material
	# Disco solar discreto (o padrão do shader dava ~13° de raio).
	sky_material.set_shader_parameter("sun_disk_size", 0.00018)
	sky_material.set_shader_parameter("sun_bloom", 0.08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.84, 0.9)
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	# Profundidade (não exponencial): a densidade não conta, só o começo e o fim.
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = FOG_BEGIN
	environment.fog_depth_end = FOG_END
	environment.fog_depth_curve = 1.0
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.0
	node.environment = environment
	sun = get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		add_child(sun)
	sun.light_energy = 1.0
	# Sombras: o nível de gráficos (GraphicsQuality) desliga abaixo do Alto.
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	moon = get_node_or_null("MoonLight") as DirectionalLight3D
	if moon == null:
		moon = DirectionalLight3D.new()
		moon.name = "MoonLight"
		add_child(moon)
	moon.light_color = Color(0.43,0.59,0.86)

## Colunas de luz sobre as ilhas, só na visão do mapa (as ilhas são pequenas no globo).
## Imagem de espaço profundo atrás da cena 3D (só no mapa), preenchendo a tela sem esticar.
func _build_space_backdrop() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SpaceBackdrop"
	layer.layer = -100
	add_child(layer)
	var image := TextureRect.new()
	image.texture = load("res://Shaders/Meshy_AI_deep-space-panoramic-skybox.png")
	image.set_anchors_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(image)
	space_backdrop = layer
	layer.visible = false

func _build_map_beacons() -> void:
	for island in islands:
		var beacon := MeshInstance3D.new()
		beacon.name = "MapBeacon"
		var column := CylinderMesh.new()
		column.top_radius = 3.0
		column.bottom_radius = 9.0
		column.height = 90.0
		column.radial_segments = 12
		beacon.mesh = column
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.91, 0.76, 0.45, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.disable_fog = true
		beacon.material_override = mat
		beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beacon.position = Vector3(0, 45.0, 0)
		beacon.visible = false
		island.add_child(beacon)
		map_beacons.append(beacon)
	# Você está aqui: coluna vermelha sobre a chalupa.
	var you := MeshInstance3D.new()
	var pin := CylinderMesh.new()
	pin.top_radius = 2.5
	pin.bottom_radius = 0.5
	pin.height = 70.0
	you.mesh = pin
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color("e04050")
	red.disable_fog = true
	you.material_override = red
	you.position = Vector3(0, 35.0, 0)
	you.visible = false
	ship.add_child(you)
	map_beacons.append(you)

func _setup_cloud_shadows() -> void:
	var shape: Texture2D = sky_material.get_shader_parameter("cloud_shape_sampler") if sky_material else null
	var axis := Scale.wind_axis()
	var u := axis.cross(Vector3.UP).normalized() if absf(axis.y) < 0.95 else axis.cross(Vector3.FORWARD).normalized()
	var v := axis.cross(u).normalized()
	for material in ocean.materials:
		material.set_shader_parameter("cloud_shadow_tex", shape)
		material.set_shader_parameter("cloud_axis_u", u)
		material.set_shader_parameter("cloud_axis_v", v)

func _build_bow_wave() -> void:
	for side in [-1.0, 1.0]:
		var mesh := MeshInstance3D.new()
		mesh.name = "BowWave_Left" if side < 0.0 else "BowWave_Right"
		var grid := PlaneMesh.new()
		# Grade de 64×24 vértices por lado (estilo Seagazer).
		grid.subdivide_width = 62
		grid.subdivide_depth = 22
		mesh.mesh = grid
		mesh.custom_aabb = AABB(Vector3(-4,-2,-4), Vector3(8,6,8))
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = load("res://Shaders/BowWaveSheet.gdshader")
		material.set_shader_parameter("side", side)
		material.set_shader_parameter("foam_pattern",load("res://Shaders/wind_waker_foam.png"))
		material.set_shader_parameter("ocean_radius",planet_radius)
		mesh.material_override = material
		ship.float_visual.add_child(mesh)
		bow_wave_materials.append(material)
		bow_wave_meshes.append(mesh)
	# Gotas: poucas, saindo para fora do casco a partir das cristas das folhas da proa.
	var drop_mesh := QuadMesh.new()
	drop_mesh.size = Vector2(0.06, 0.06)
	var drop_material := ShaderMaterial.new()
	drop_material.shader = load("res://Shaders/water_drop.gdshader")
	drop_mesh.material = drop_material
	for side in [-1.0, 1.0]:
		var emitter := GPUParticles3D.new()
		emitter.name = "WaterDroplets_" + ("L" if side < 0.0 else "R")
		emitter.position = Vector3(side * 0.95, 0.4, -1.2)
		emitter.amount = 4
		emitter.lifetime = 0.6
		emitter.emitting = false
		emitter.local_coords = false
		emitter.visibility_aabb = AABB(Vector3(-4, -3, -4), Vector3(8, 6, 8))
		var motion := ParticleProcessMaterial.new()
		motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		motion.emission_box_extents = Vector3(0.05, 0.05, 0.5)
		# Bem abertas para fora (como o borrifo real da proa), pouco para cima, um pouco para trás.
		motion.direction = Vector3(side * 1.8, 0.7, 0.45)
		motion.spread = 12.0
		motion.initial_velocity_min = 2.0
		motion.initial_velocity_max = 3.2
		motion.gravity = Vector3(0, -9.8, 0)
		motion.scale_min = 0.6
		motion.scale_max = 1.2
		emitter.process_material = motion
		emitter.draw_pass_1 = drop_mesh
		ship.float_visual.add_child(emitter)
		droplet_emitters.append(emitter)
	water_droplets = droplet_emitters[0]

func _build_wind_streaks() -> void:
	wind_streaks = get_node_or_null("WindRibbonSystem") as Node3D
	if wind_streaks == null:
		wind_streaks = WindRibbon.instantiate() as Node3D
		wind_streaks.name = "WindRibbonSystem"
		add_child(wind_streaks)
	wind_streaks.boat = ship

## Celular em pé: base de UI em retrato, para a interface não encolher a ~1/3.
func _fit_ui_to_screen() -> void:
	var window := get_tree().root
	var screen := Vector2(window.size)
	var portrait := screen.x < screen.y
	window.content_scale_size = Vector2i(480, 854) if portrait else Vector2i(1152, 648)
	# Log Pose pequeno no canto inferior esquerdo (no celular, acima dos controles).
	var pose := get_node_or_null("LogPose_HUD/MarginContainer") as Control
	if pose != null:
		var side := 96.0 if portrait else 120.0
		# No toque a bússola sobe acima do joystick esquerdo (em pé e deitado; antes só em pé
		# sobrava espaço e, com o celular deitado, o joystick cobria a bússola).
		var touch := DisplayServer.is_touchscreen_available() or "touch" in OS.get_cmdline_user_args()
		var bottom_gap := (316.0 if portrait else 196.0) if touch else 14.0
		pose.anchor_left = 0.0
		pose.anchor_right = 0.0
		pose.anchor_top = 1.0
		pose.anchor_bottom = 1.0
		pose.offset_left = 12.0
		pose.offset_right = 12.0 + side
		pose.offset_bottom = -bottom_gap
		pose.offset_top = -bottom_gap - side
		(pose.get_child(0) as Control).custom_minimum_size = Vector2(side, side)

func _build_hud() -> void:
	_fit_ui_to_screen()
	get_tree().root.size_changed.connect(_fit_ui_to_screen)
	# Camada mantida com o nome antigo para compatibilidade com testes/ferramentas.
	var layer := CanvasLayer.new()
	layer.name = "NavigationHUD"
	add_child(layer)
	hud = PortfolioHUDScript.new()
	hud.name = "PortfolioHUD"
	add_child(hud)
	hud.free_sail_pressed.connect(_return_to_navigation)
	hud.island_pressed.connect(_select_island)
	hud.time_attack_pressed.connect(func(): hud.show_challenge_box())
	hud.challenge_confirmed.connect(_start_time_attack)
	hud.time_mode_pressed.connect(select_time)
	hud.next_track_pressed.connect(next_track)
	hud.prev_track_pressed.connect(prev_track)
	hud.toggle_music_pressed.connect(toggle_music_pause)
	hud.panel_closed.connect(_return_to_navigation)
	hud.start_sailing.connect(_start_sailing)
	hud.map_pressed.connect(toggle_map)
	hud.set_time_mode(time_mode)
## Links da landing: /world/?ilha=projetos abre direto na ilha; ?modo=regata inicia a regata.
func _apply_web_deeplink() -> void:
	var query := str(JavaScriptBridge.eval("window.location.search", true))
	var params := {}
	for pair in query.trim_prefix("?").split("&", false):
		var parts := pair.split("=")
		params[parts[0].uri_decode()] = parts[1].uri_decode() if parts.size() > 1 else ""
	print("DEEPLINK ", params)
	if params.has("medir"):
		_start_measure()
	await get_tree().create_timer(0.8).timeout
	var ids := ["sobre", "experiencia", "formacao", "projetos", "contato"]
	if params.has("ilha") and ids.has(params.ilha):
		_select_island(ids.find(params.ilha))
	elif params.get("modo", "") == "regata":
		_start_time_attack()

## ?medir (site): mede o tempo até o barco responder ao leme. Acelera sozinho desde o primeiro
## quadro e avisa a página (marca "steer") quando o casco passa de 0,5 m/s; depois devolve o controle.
func _start_measure() -> void:
	ship.controls_override = true
	ship.test_controls = Vector3(1.0, 0.0, 0.0)
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(func() -> void:
		if absf(float(ship.measured_speed)) < 0.5:
			return
		timer.queue_free()
		ship.test_controls = Vector3.ZERO
		ship.controls_override = false
		print("MEASURE steer speed=%.2f" % ship.measured_speed)
		JavaScriptBridge.eval("window.__portfolioMark && window.__portfolioMark('steer')", true)
		_measure_costs())

## ?medir: quanto cada parte custa no quadro. Espera o mundo assentar e desliga uma parte por vez
## (3 s cada), medindo o tempo médio de quadro; a diferença para a base é o custo dela. Também manda
## o tempo de scripts (process) e de física. Resultado na tela da página (__portfolioCost).
func _measure_costs() -> void:
	await get_tree().create_timer(30.0).timeout
	var probes := [["base", null, ""],
		["decoração (scripts)", world_decor, "process"], ["decoração (desenho)", world_decor, "visible"],
		["colossos (scripts)", sea_beasts, "process"], ["colossos (desenho)", sea_beasts, "visible"],
		["clima", weather, "process"], ["vida no mar", sea_life, "process"], ["gaivotas", seagulls, "process"],
		["mar perto (desenho)", ocean_patch, "visible"], ["mar (simulação)", ocean, "process"],
		["nuvens do céu", get_node_or_null("SkyClouds"), "visible"], ["barco (física)", ship, "physics"]]
	var results := []
	var base_ms := 0.0
	# Sem o teto de quadros (30 no Baixo) enquanto mede: com o teto, desligar uma parte não muda nada.
	var cap := Engine.max_fps
	Engine.max_fps = 0
	for probe in probes:
		var node: Node = probe[1]
		if probe[0] != "base" and not is_instance_valid(node):
			continue
		var mode: String = probe[2]
		var before: Variant = null
		if mode == "process":
			before = [node.is_processing(), node.is_physics_processing()]
			node.set_process(false)
			node.set_physics_process(false)
		elif mode == "visible":
			before = (node as Node3D).visible
			(node as Node3D).visible = false
		elif mode == "physics":
			before = node.is_physics_processing()
			node.set_physics_process(false)
		await get_tree().create_timer(0.6).timeout
		var frames := 0
		var t0 := Time.get_ticks_usec()
		var proc := 0.0
		var phys := 0.0
		while Time.get_ticks_usec() - t0 < 3000000:
			await get_tree().process_frame
			frames += 1
			proc += Performance.get_monitor(Performance.TIME_PROCESS)
			phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / maxi(frames, 1)
		if mode == "process":
			node.set_process(before[0])
			node.set_physics_process(before[1])
		elif mode == "visible":
			(node as Node3D).visible = before
		elif mode == "physics":
			node.set_physics_process(before)
		if probe[0] == "base":
			base_ms = ms
			results.append({"name": "base", "ms": snappedf(ms, 0.1), "process_ms": snappedf(proc * 1000.0 / maxi(frames, 1), 0.1),
				"physics_ms": snappedf(phys * 1000.0 / maxi(frames, 1), 0.1)})
		else:
			results.append({"name": probe[0], "saves_ms": snappedf(base_ms - ms, 0.1)})
		print("MEASURE cost ", results[-1])
		JavaScriptBridge.eval("window.__portfolioCost && window.__portfolioCost(%s)" % JSON.stringify(results), true)
	Engine.max_fps = cap

func _leave_intro() -> void:
	intro_orbit = false
	camera.h_offset = 0.0
	if hud and hud.intro_visible:
		hud.show_intro(false)
	ship.enabled = true

func _start_sailing() -> void:
	# Primeira entrada (saindo da abertura): chegada cinematográfica dando a volta no barco.
	camera.arrival_cinematic = intro_orbit
	_leave_intro()
	camera.return_to_boat()

func _select_island(index: int) -> void:
	_leave_intro()
	if is_instance_valid(camera) and index >= 0 and index < islands.size():
		camera.focus_island(islands[index])

func _on_island_visit_started(index: int) -> void:
	if intro_orbit:
		return
	if hud: hud.show_island(index, false)
	if is_instance_valid(naval) and bool(naval.get("time_attack_mode")):
		naval.call("leave_time_attack")

func _return_to_navigation() -> void:
	if hud: hud.hide_island()
	if is_instance_valid(naval):
		naval.call("leave_time_attack")
	if is_instance_valid(camera):
		camera.return_to_boat()

func _start_time_attack() -> void:
	_leave_intro()
	if is_instance_valid(camera):
		if camera.state != PortfolioCamera.CameraState.BOAT_FOLLOW:
			camera.return_to_boat()
			await camera.transition_tween.finished
	if is_instance_valid(naval):
		naval.call("start_time_attack")

func _build_log_pose() -> void:
	var pose_layer := LogPose.instantiate()
	add_child(pose_layer)
	log_pose = pose_layer.get_node("MarginContainer/SubViewportContainer/SubViewport/LogPose_Master")
	log_pose.player_sloop = ship
	log_pose.islands_parent = get_node(island_anchors_path)
	_fit_ui_to_screen()

func wind_at(point: Vector3) -> Vector3:
	if wind_manager != null:
		return wind_manager.wind_at(point)
	return Scale.wind_at(point)

## Vento em rosa dos ventos local (norte = rumo ao polo de Sobre) e nós.
func _wind_text(point: Vector3) -> String:
	var wind := wind_at(point)
	if wind.length() < 0.05:
		return "calmaria"
	var up := point.normalized()
	var north := Vector3.UP.slide(up)
	if north.length_squared() < 0.0001:
		north = Vector3.FORWARD.slide(up)
	north = north.normalized()
	var east := north.cross(up).normalized()
	var from := -wind.normalized()
	var bearing := fposmod(rad_to_deg(atan2(from.dot(east), from.dot(north))), 360.0)
	var names := ["N", "NE", "L", "SE", "S", "SO", "O", "NO"]
	return "%s  %d nós" % [names[int(round(bearing / 45.0)) % 8], int(round(wind.length() * 16.0))]

func _update_hud(section: String, nearest: float, nearest_index: int) -> void:
	# Destino: a ilha não visitada mais próxima (se todas visitadas, a mais próxima).
	var up := ship.global_position.normalized()
	var target_index := -1
	var target_distance := INF
	for i in range(islands.size()):
		if hud.visited.has(i):
			continue
		var d := up.angle_to(islands[i].global_position.normalized()) * planet_radius
		if d < target_distance:
			target_distance = d
			target_index = i
	if target_index < 0:
		target_index = nearest_index
		target_distance = nearest
	var target_name := str(islands[target_index].get_meta("section")) if target_index >= 0 else ""
	var target_node: Node3D = islands[target_index] if target_index >= 0 else null
	# No Desafio, a rota e o Log Pose levam até a boia mais próxima ainda não acertada.
	if is_instance_valid(naval) and naval.time_attack_running:
		var buoy: Node3D = naval.nearest_course_target(ship.global_position)
		if buoy != null:
			target_node = buoy
			target_name = "Boia"
			target_distance = up.angle_to(buoy.global_position.normalized()) * planet_radius
	hud.set_status(section, target_distance, ship.measured_speed, Engine.get_frames_per_second())
	hud.set_route(target_name, target_distance)
	if is_instance_valid(log_pose) and target_node != null:
		log_pose.target_override = target_node
	if is_instance_valid(ocean_patch):
		var visiting := camera.state in [PortfolioCamera.CameraState.ISLAND_ORBIT, PortfolioCamera.CameraState.FLYING] and is_instance_valid(camera.target_island)
		ocean_patch.follow_override = camera.target_island if visiting else null
	if is_instance_valid(route_line):
		route_line.target = target_node
		route_line.visible = camera.state == PortfolioCamera.CameraState.BOAT_FOLLOW and not hud.intro_visible
	var distances: Array = []
	for island in islands:
		distances.append(up.angle_to(island.global_position.normalized()) * planet_radius)
	hud.set_island_distances(distances)
	hud.update_map(camera, islands, camera.state == PortfolioCamera.CameraState.PLANET_OVERVIEW, ship)
	hud.set_wind(_wind_text(ship.global_position))
	sky_text_timer -= get_process_delta_time()
	if sky_text_timer <= 0.0:
		sky_text_timer = 0.5
		_update_sky_text()
	# Só BEM perto da costa (distância medida à linha d'água) o pergaminho abre sozinho.
	var coast := INF
	if nearest_index >= 0 and nearest < 160.0:
		coast = Shore.distance_to_coast(islands[nearest_index], ship.global_position)
	var close := coast < 30.0 and camera.state == PortfolioCamera.CameraState.BOAT_FOLLOW
	hud.set_approach(nearest_index if close else -1)
	hud.set_daylight(1.0 - clock.night_at(camera.global_position))
	if is_instance_valid(naval):
		var finished := ""
		if naval.time_attack_mode and not naval.time_attack_running:
			finished = "CONCLUÍDA" if naval.time_attack_hits.size() == naval.course_count else "FIM"
		hud.set_race(naval.time_attack_mode, naval.time_attack_remaining, naval.time_attack_hits.size(), naval.course_count, finished)
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not ship or not camera:
		return
	_report_ready_to_page()
	_update_calm_spots(delta)
	_update_contact_ripples(delta)
	if ship.enabled and not intro_orbit:
		adventure_seconds += delta
		distance_sailed += ship.measured_speed * delta
	var render_transform: Transform3D = ship.get_global_transform_interpolated()
	var render_position: Vector3 = render_transform.origin
	var render_forward: Vector3 = -render_transform.basis.z
	var up := render_position.normalized()
	var wind_world := wind_at(render_position)
	var local_wind := sail_model.global_basis.inverse() * wind_world
	if local_wind.length_squared() < 0.0001:
		local_wind = Vector3.FORWARD * 0.01
	if rudder:
		# Virar para boreste (D) leva a pá para boreste (mesmo lado da curva), como pediu o teste no jogo.
		rudder.basis = rudder_rest * Basis(Vector3.UP, ship.turn_input * RUDDER_MAX_ANGLE)
	# Fase das ondas do pano acumulada aqui: no shader era TIME * (velocidade…), e quando o barco
	# desacelerava a fase pulava e a bandeira tremulava "desesperada".
	var speed_ratio := clampf(ship.measured_speed / 12.5, 0.0, 1.0)
	smoothed_cloth_speed = lerpf(smoothed_cloth_speed, speed_ratio, 1.0 - exp(-1.5 * delta))
	flag_phase += delta * (3.0 + smoothed_cloth_speed * 6.0 + wind_world.length() * 1.5)
	sail_phase += delta * (5.0 + ship.measured_speed * 0.4)
	for cloth in sail_materials:
		cloth.set_shader_parameter("wind_direction",local_wind.normalized())
		cloth.set_shader_parameter("boat_speed",ship.measured_speed)
		cloth.set_shader_parameter("flag_phase", flag_phase)
		cloth.set_shader_parameter("sail_phase", sail_phase)
		cloth.set_shader_parameter("cloth_speed", smoothed_cloth_speed)
		cloth.set_shader_parameter("forward_local", (sail_model.global_basis.inverse() * render_forward).normalized())
		cloth.set_shader_parameter("wind_strength",(0.04+minf(ship.measured_speed,12.0)*0.004)+0.06*wind_world.length())
	sky_material.set_shader_parameter("local_up", camera.global_position.normalized())
	# Visão do globo (mapa): sem névoa nem nuvens, para o planeta inteiro aparecer.
	space_view = smoothstep(planet_radius * 1.15, planet_radius * 1.6, camera.global_position.length())
	sky_material.set_shader_parameter("space_view", space_view)
	# Mapa: fundo de espaço fixo em tela cheia; fora dele, o céu normal.
	var in_space := space_view > 0.5
	space_backdrop.visible = in_space
	environment.background_mode = Environment.BG_CANVAS if in_space else Environment.BG_SKY
	# No mapa (espaço) a névoa sai; na tempestade ela fecha perto do barco.
	var far := 1.0 + space_view * 20.0
	environment.fog_depth_begin = lerpf(FOG_BEGIN, FOG_STORM_BEGIN, storm_gloom) * far
	environment.fog_depth_end = lerpf(FOG_END, FOG_STORM_END, storm_gloom) * far
	for beacon in map_beacons:
		beacon.visible = space_view > 0.3
	# No mapa (M) os ciclones aparecem como as tempestades: o próprio funil, só que maior
	# (do espaço, 55 m de funil viravam um pontinho).
	if weather:
		for cyclone in weather.cyclones:
			if not cyclone.captured:
				cyclone.scale = Vector3.ONE * lerpf(1.0, 3.5, space_view)
	web_music_timer -= delta
	if web_music_timer <= 0.0:
		web_music_timer = 1.0
		_poll_web_music()
	_update_day(delta)
	if water_held:
		_drag_water(water_cursor)
	for material in ocean.materials:
		material.set_shader_parameter("boat_position", render_position)
		material.set_shader_parameter("boat_forward", render_forward)
		material.set_shader_parameter("boat_right", render_forward.cross(up))
		# Sem recorte: o buraco mostrava o fundo escuro sob a proa (o 'nariz preto').
		material.set_shader_parameter("boat_cutout_enabled", false)
	var visual_transform: Transform3D = ship.float_visual.get_global_transform_interpolated()
	var bow_forward: Vector3 = -visual_transform.basis.z.normalized()
	var front_height: float = ocean.height_at(visual_transform.origin + bow_forward * 1.75)
	var back_height: float = ocean.height_at(visual_transform.origin - bow_forward * 1.10)
	# Casco fora d'água (salto) ou água acima da linha d'água: a folha da proa some/limita.
	var hull_height: float = visual_transform.origin.length() - planet_radius
	var clearance: float = hull_height - (front_height + back_height) * 0.5
	var contact: float = 0.0 if ship.airborne else 1.0 - smoothstep(0.15, 0.45, clearance)
	# Cor da lâmina = cor do mar onde o barco está (horário, tempestade).
	var sea_material: ShaderMaterial = ocean.materials[0] if not ocean.materials.is_empty() else null
	# Parâmetro não definido no material volta null: usa o padrão do shader do mar.
	var deep_value = sea_material.get_shader_parameter("deep_ocean_color") if sea_material else null
	var shallow_value = sea_material.get_shader_parameter("shallow_ocean_color") if sea_material else null
	var sea_deep: Color = deep_value if deep_value is Color else Color(0.0, 0.3, 0.44)
	var sea_shallow: Color = shallow_value if shallow_value is Color else Color(0.03, 0.5, 0.55)
	var storm_tint := Color(0.4, 0.56, 0.5) * 1.3
	var gloom_here := storm_gloom
	sea_deep = sea_deep.lerp(sea_deep * storm_tint, gloom_here)
	sea_shallow = sea_shallow.lerp(sea_shallow * storm_tint, gloom_here)
	for material in bow_wave_materials:
		material.set_shader_parameter("water_deep_color", sea_deep)
		material.set_shader_parameter("water_body_color", sea_shallow)
		material.set_shader_parameter("contact", contact)
		material.set_shader_parameter("hull_height", hull_height)
		material.set_shader_parameter("ocean_radius",planet_radius)
		material.set_shader_parameter("boat_position",visual_transform.origin)
		material.set_shader_parameter("boat_forward",bow_forward)
		material.set_shader_parameter("boat_right",visual_transform.basis.x.normalized())
		material.set_shader_parameter("water_height_front",front_height)
		material.set_shader_parameter("water_height_back",back_height)
		material.set_shader_parameter("boat_speed",ship.measured_speed)
		material.set_shader_parameter("turn",ship.turn_input)
		material.set_shader_parameter("turn_bias",ship.turn_bias)
		# Escurece junto com o mar (noite e tempestade).
		material.set_shader_parameter("daylight",(1.0-clock.night_at(render_position)) * (1.0 - 0.55 * storm_gloom))
	for mesh in bow_wave_meshes:
		mesh.visible = ship.measured_speed > 0.4 and contact > 0.02
	# Mais gotas com velocidade e quando a proa mergulha na onda (slam).
	var bow_dip := clampf((back_height - front_height) * 0.8, 0.0, 1.0)
	for emitter in droplet_emitters:
		emitter.emitting = ship.measured_speed > 3.0 and contact > 0.5
		emitter.amount_ratio = clampf(ship.measured_speed / 16.0 + bow_dip * 0.3, 0.2, 0.75)
		(emitter.process_material as ParticleProcessMaterial).gravity = -visual_transform.origin.normalized() * 9.8
	(droplet_emitters[0].draw_pass_1.surface_get_material(0) as ShaderMaterial).set_shader_parameter("daylight", 1.0 - clock.night_at(render_position))
	var night_amount: float = clock.night_at(render_position)
	# Escuridão da tempestade também acende o lampião.
	var lantern_need := maxf(night_amount, storm_gloom * 0.8)
	# L apaga/acende só a chama: o lampião (corpo) continua pendurado.
	lantern.visible = true
	if not lantern_enabled:
		lantern_need = 0.0
	var flicker := 0.85 + 0.1 * sin(Time.get_ticks_msec() * 0.011) + 0.05 * sin(Time.get_ticks_msec() * 0.037)
	lantern.light_energy = 1.8 * lantern_need * flicker
	_swing_lantern(delta)
	_swing_pendants(delta)
	var glass_mesh := lantern.get_node_or_null("Body/Glass") as MeshInstance3D
	if glass_mesh:
		# Apagado: vidro escuro, como um lampião de verdade sem chama.
		var glow_amount := clampf(lantern_need * 3.0, 0.0, 1.0) * flicker
		(glass_mesh.material_override as StandardMaterial3D).albedo_color = Color(0.22, 0.2, 0.17).lerp(Color(1.0, 0.78, 0.45), glow_amount)
	var halo := lantern.get_node_or_null("Body/Halo") as MeshInstance3D
	if halo:
		(halo.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.7, 0.35, 0.55 * lantern_need * flicker)
	var nearest := INF
	var section := ""
	var nearest_index := -1
	for i in range(islands.size()):
		var island := islands[i]
		var distance := acos(clampf(up.dot(island.position.normalized()), -1.0, 1.0)) * planet_radius
		if distance < nearest:
			nearest = distance
			nearest_index = i
			section = island.get_meta("section")
	_update_hud(section, nearest, nearest_index)

## Tab é consumido pela navegação de foco da GUI; o mapa (M ou Tab) é tratado antes.
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not camera:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_TAB, KEY_M]:
		toggle_map()
		get_viewport().set_input_as_handled()

## Mapa 3D: tecla M/Tab ou o botão do globo no celular.
func toggle_map() -> void:
	if camera.state == PortfolioCamera.CameraState.PLANET_OVERVIEW:
		camera.return_to_boat()
	else:
		camera.show_overview()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	# Na abertura, começar a navegar pelo teclado já zarpa.
	if hud and hud.intro_visible and event is InputEventKey and event.pressed and event.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		_start_sailing()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera.drag_orbit(event.relative)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_5:
			camera.focus_island(islands[event.physical_keycode - KEY_1])
		elif event.physical_keycode == KEY_TAB:
			camera.show_overview()
		elif event.physical_keycode == KEY_B:
			camera.return_to_boat()
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_P:
		toggle_music_pause()
	if web_music and (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey) and event.is_pressed():
		_web_music("if (window.__portfolioMusicBlocked) { window.__portfolioMusicBlocked = false; a.play().catch(function(){}); }")
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_N:
		next_track()
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_L:
		lantern_enabled = not lantern_enabled
	if event is InputEventMouseMotion:
		water_cursor = event.position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		water_held = event.pressed
		water_cursor = event.position
		last_touch_point = Vector3.INF
		if water_held:
			var point: Vector3 = _water_point(water_cursor)
			if point != Vector3.INF:
				# Clique: um "pingo" mais forte que afunda e rebate.
				ocean.touch(point, 0.55, 3.0)
				ocean.drag(point, true)
				last_touch_point = point

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		water_held = false

func _water_point(cursor: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(cursor)
	var direction := camera.project_ray_normal(cursor)
	var b := origin.dot(direction)
	var discriminant := b*b - origin.length_squared() + planet_radius*planet_radius
	if discriminant < 0.0:
		return Vector3.INF
	var distance := -b - sqrt(discriminant)
	if distance <= 0.0:
		return Vector3.INF
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * distance, 3)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return Vector3.INF
	return origin + direction * distance

## Arrastar deixa um rastro contínuo: novas perturbações a cada ~1,2 m percorrido,
## com força proporcional à velocidade do gesto (mais orgânico que pulsos fixos).
func _drag_water(cursor: Vector2) -> void:
	# Segurar e arrastar: um sulco contínuo (como uma mão passando na água).
	var point := _water_point(cursor)
	if point == Vector3.INF:
		return
	if last_touch_point == Vector3.INF:
		ocean.drag(point, true)
		last_touch_point = point
		return
	if point.distance_to(last_touch_point) < 0.6:
		return
	ocean.drag(point)
	last_touch_point = point

func _build_audio() -> void:
	sea_ambience = SeaAmbience.new()
	sea_ambience.name = "SeaAmbience"
	sea_ambience.ship = ship
	sea_ambience.ocean = ocean
	sea_ambience.islands = islands
	add_child(sea_ambience)
	music = AudioStreamPlayer.new()
	music.name = "BackgroundMusic"
	music.volume_db = -18.0
	add_child(music)
	if OS.has_feature("web"):
		# Na web a música fica fora do .pck (110 MB) e é tocada pelo <audio> do
		# navegador, sob demanda, a partir de music/<arquivo> ao lado do index.html.
		web_music = true
		var manifest := FileAccess.get_file_as_string("res://Config/music_playlist.json")
		var parsed: Variant = JSON.parse_string(manifest)
		if parsed is Dictionary:
			for file in parsed.get("tracks", []):
				playlist.append(str(file))
		next_track()
		return
	# ResourceLoader enxerga os recursos também no export (DirAccess veria só .import/.remap).
	for file in ResourceLoader.list_directory("res://Assets/Sound"):
		if file.get_extension().to_lower() in ["mp3","ogg","wav"]:
			playlist.append("res://Assets/Sound/"+file)
	music.finished.connect(next_track)
	next_track()

func _web_music(command: String) -> Variant:
	var script := """(function(){
		var a = window.__portfolioMusic;
		if (!a) {
			a = new Audio(); a.volume = 0.126; a.preload = 'auto';
			a.addEventListener('ended', function(){ window.__portfolioMusicEnded = true; });
			window.__portfolioMusic = a;
		}
		%s
	})()""" % command
	return JavaScriptBridge.eval(script, true)

func _poll_web_music() -> void:
	if not web_music:
		return
	if bool(_web_music("var e = window.__portfolioMusicEnded === true; window.__portfolioMusicEnded = false; return e;")):
		next_track()

func toggle_music_pause() -> void:
	music_paused = not music_paused
	if web_music:
		_web_music("if (a.paused) { a.play().catch(function(){}); } else { a.pause(); }")
	else:
		music.stream_paused = music_paused
	if hud:
		hud.set_music_playing(not music_paused)

func next_track() -> void:
	if playlist.is_empty(): return
	if history_index < track_history.size() - 1:
		history_index += 1
		_play_track(track_history[history_index])
		return
	if music_bag.is_empty():
		music_bag.assign(playlist)
		music_bag.shuffle()
		if music_bag.size() > 1 and music_bag.back() == current_track:
			var swap := music_bag[0]
			music_bag[0] = music_bag[-1]
			music_bag[-1] = swap
	track_history.append(music_bag.pop_back())
	history_index = track_history.size() - 1
	_play_track(track_history[history_index])

func prev_track() -> void:
	if history_index > 0:
		history_index -= 1
		_play_track(track_history[history_index])

func _play_track(track_name: String) -> void:
	current_track = track_name
	music_paused = false
	if hud:
		hud.set_track(current_track.get_file().get_basename())
		hud.set_music_playing(true)
	if web_music:
		# Autoplay pode ser bloqueado até o primeiro gesto; o clique seguinte retoma.
		_web_music("a.src = 'music/' + encodeURIComponent(%s); a.play().catch(function(){ window.__portfolioMusicBlocked = true; });" % JSON.stringify(current_track))
		return
	var track := load(current_track) as AudioStream
	if track is AudioStreamMP3 or track is AudioStreamOggVorbis: track.loop = false
	elif track is AudioStreamWAV: track.loop_mode = AudioStreamWAV.LOOP_DISABLED
	music.stream = track
	music.play()
	music.stream_paused = false

func select_time(mode: String) -> void:
	time_mode = mode
	water_held = false
	if hud: hud.set_time_mode(mode)
	if mode=="auto":
		clock.paused = false
	else:
		# Manual mode remains day/night around the sailor anywhere on the sphere.
		clock.paused = true

func _build_titles() -> void:
	for i in range(islands.size()):
		var title_sign := islands[i].get_node_or_null("IslandTitleSign") as Node3D
		if title_sign == null:
			title_sign = Sign.instantiate()
			title_sign.set("island_index", i)
			islands[i].add_child(title_sign)
			var anchors := get_node(island_anchors_path)
			if anchors.has_method("apply_layout"):
				anchors.apply_layout()
		title_sign.set("island_index", i)
		title_sign.set("island", islands[i])
		title_sign.set("boat", ship)

## Hora local onde o barco está e quanto falta para o sol se pôr/nascer (HUD). O sol gira em
## volta do planeta (DayNightCycle): cada lugar do globo tem a sua hora.
func _update_sky_text() -> void:
	if time_mode != "auto":
		hud.set_sky(time_mode == "day", "DIA FIXO" if time_mode == "day" else "NOITE FIXA", "sol parado")
		return
	var up: Vector3 = ship.global_position.normalized()
	var elevation := up.dot(clock.sun_direction)
	var day := elevation > 0.0
	# Procura no futuro (passos de 1/240 do dia) a próxima vez que o sol cruza o horizonte.
	var steps := 0
	for i in range(1, 241):
		var angle: float = (float(clock.time_of_day) + float(i) / 240.0 - 0.5) * TAU
		var sun_dir := Vector3(0.35 * sin(angle), cos(angle), sin(angle)).normalized()
		if (up.dot(sun_dir) > 0.0) != day:
			steps = i
			break
	var seconds := float(steps) / 240.0 * day_duration
	var wait := ("%d min" % int(round(seconds / 60.0))) if seconds >= 60.0 else "instantes"
	# Hora local aproximada: subindo, 6h→12h; descendo, 12h→18h (e o mesmo à noite).
	var next_angle: float = (float(clock.time_of_day) + 1.0 / 240.0 - 0.5) * TAU
	var rising := up.dot(Vector3(0.35 * sin(next_angle), cos(next_angle), sin(next_angle)).normalized()) > elevation
	var e := asin(clampf(elevation, -1.0, 1.0)) / (PI * 0.5)
	var hour := fposmod((6.0 + 6.0 * e) if rising else (18.0 - 6.0 * e), 24.0)
	if steps == 0:
		hud.set_sky(day, "SOL" if day else "NOITE", "%02dh" % int(hour))
	elif day:
		hud.set_sky(true, "SOL", "%02dh · põe-se em %s" % [int(hour), wait])
	else:
		hud.set_sky(false, "NOITE", "%02dh · amanhece em %s" % [int(hour), wait])

## No mapa: o sol lá longe e o lado da noite do globo.
func _build_sun_view() -> void:
	night_side_material = ShaderMaterial.new()
	night_side_material.shader = preload("res://Shaders/night_side.gdshader")
	night_side_material.render_priority = 3
	var sphere := SphereMesh.new()
	sphere.radius = planet_radius + 4.0
	sphere.height = (planet_radius + 4.0) * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	night_side = MeshInstance3D.new()
	night_side.name = "NightSide"
	night_side.mesh = sphere
	night_side.material_override = night_side_material
	night_side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	night_side.visible = false
	add_child(night_side)
	var glow := Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 0.12, 0.35, 1.0])
	glow.colors = PackedColorArray([Color(1.0, 0.98, 0.9, 1.0), Color(1.0, 0.9, 0.6, 0.95), Color(1.0, 0.7, 0.35, 0.3), Color(1.0, 0.6, 0.3, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = glow
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 256
	texture.height = 256
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	material.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2(780, 780)
	quad.material = material
	map_sun = MeshInstance3D.new()
	map_sun.name = "MapSun"
	map_sun.mesh = quad
	map_sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map_sun.visible = false
	add_child(map_sun)

func _update_sun_view() -> void:
	if night_side == null:
		_build_sun_view()
	var in_map: bool = camera != null and int(camera.get("state")) == 3
	night_side.visible = in_map
	map_sun.visible = in_map
	if not in_map:
		return
	night_side_material.set_shader_parameter("sun_direction", clock.sun_direction)
	# O sol de verdade fica quase sempre fora do enquadramento: desenha o brilho no canto da tela
	# do lado em que ele está (direção projetada), bem longe atrás do globo.
	var view: Vector3 = -camera.global_basis.z
	var toward: Vector3 = (clock.sun_direction as Vector3).slide(view)
	toward = toward.normalized() if toward.length() > 0.01 else camera.global_basis.x
	var dir := (view * cos(deg_to_rad(30.0)) + toward * sin(deg_to_rad(30.0))).normalized()
	map_sun.global_position = camera.global_position + dir * 3000.0

func _update_day(_delta: float) -> void:
	_update_sun_view()
	day_phase = clock.time_of_day
	if time_mode!="auto":
		# Dia fixo: sol alto mas não no zênite (~55°), para ver o flare e luz lateral nas nuvens.
		var here := camera.global_position.normalized()
		var tilt := here.cross(Vector3.FORWARD if absf(here.z) < 0.9 else Vector3.RIGHT).normalized()
		clock.sun_direction = (here + tilt * 0.7).normalized()*(1.0 if time_mode=="day" else -1.0)
	var toward_sun: Vector3 = clock.sun_direction
	# O céu precisa da mesma direção do sol que a luz (antes ficava sempre de dia no polo).
	sky_material.set_shader_parameter("sun_direction", toward_sun)
	sun.basis = Basis.looking_at(-toward_sun, Vector3.RIGHT if absf(toward_sun.x)<0.95 else Vector3.UP)
	var elevation := camera.global_position.normalized().dot(toward_sun)
	var daylight := smoothstep(-0.16, 0.24, elevation)
	sun.light_energy = 1.15 * daylight * (1.0 - 0.7 * storm_gloom)
	moon.basis = Basis.looking_at(toward_sun, Vector3.RIGHT if absf(toward_sun.x)<0.95 else Vector3.UP)
	moon.light_energy = 0.32 * (1.0-daylight)
	sun.light_color = Color(1.0,0.57,0.31).lerp(Color(1.0,0.96,0.87), smoothstep(0.0,0.55,elevation))
	# Tempestade no estilo do Wind Waker: tudo puxa para verde-acinzentado; o clarão é azulado.
	# Clarão azulado da tempestade; vermelho quando é o kraken (Thunder.red).
	var flash_blue := Color(0.35, 0.63, 0.96).lerp(Color(1.0, 0.25, 0.2), float(weather.thunder.red) if weather and weather.get("thunder") else 0.0)
	environment.ambient_light_color = Color(0.23,0.34,0.58).lerp(Color(0.69,0.79,0.89), daylight).lerp(Color(0.44, 0.54, 0.5), storm_gloom * 0.75).lerp(flash_blue, storm_flash * 0.5)
	environment.ambient_light_energy = lerpf(0.3, 0.55, daylight) + storm_flash * 0.6
	environment.fog_light_color = Color(0.1, 0.14, 0.28).lerp(Color(0.74, 0.86, 0.95), daylight).lerp(Color(0.36, 0.44, 0.41) * maxf(daylight, 0.3), storm_gloom * 0.9).lerp(flash_blue, sky_flash * 0.3)
	sky_material.set_shader_parameter("storm_gloom", storm_gloom)
	sky_material.set_shader_parameter("storm_flash", sky_flash)
	# Reflexo do céu na água acompanha o horário (pastel de dia, quente no poente, azul à noite).
	var dusk := 1.0 - absf(smoothstep(-0.16, 0.4, elevation) * 2.0 - 1.0)
	var reflection := Color(0.12, 0.17, 0.36).lerp(Color(0.78, 0.85, 0.96), daylight).lerp(Color(1.0, 0.78, 0.68), dusk * 0.6)
	for material in ocean.materials:
		material.set_shader_parameter("night_amount", 1.0 - daylight)
		material.set_shader_parameter("cloud_shadow_strength", 0.2 * daylight * (1.0 - space_view))
		material.set_shader_parameter("sky_reflection_color", reflection)
