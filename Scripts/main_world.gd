@tool
extends Node3D

const Shore = preload("res://Scripts/Shoreline.gd")
const NavalGame = preload("res://Scripts/NavalGame.gd")
const Sign = preload("res://Scenes/IslandTitleSign.tscn")
const Waves = preload("res://Scripts/SphericalOceanSimulation.gd")
const IslandEffects = preload("res://Scripts/IslandEffects.gd")
const Sloop = preload("res://Scripts/sloop.gd")
const SeaAmbience = preload("res://Scripts/SeaAmbience.gd")
const Scale = preload("res://Scripts/WorldScale.gd")
const LogPose = preload("res://Scenes/LogPose_HUD.tscn")
const WindRibbon = preload("res://Scenes/WindRibbon.tscn")
const PortfolioCamera = preload("res://Scripts/PortfolioCameraController.gd")
const OceanPatchScript = preload("res://Scripts/OceanPatch.gd")
const TouchControlsScript = preload("res://Scripts/TouchControls.gd")
const PortfolioHUDScript = preload("res://Scripts/UI/PortfolioHUD.gd")
const CloudLayerScript = preload("res://Scripts/CloudLayer.gd")
const SHIP_LENGTH := 4.8
const SEABED_DEPTH := 25.0
const CORE_DEPTH := 30.0
const ISLANDS := [
	{"name":"Sobre", "file":"Optimized/island_sobre.glb", "width":28.0},
	{"name":"Experiência", "file":"Optimized/island_experiencia.glb", "width":32.0},
	{"name":"Formação", "file":"Optimized/island_formacao.glb", "width":30.0},
	{"name":"Projetos", "file":"Optimized/island_projetos.glb", "width":32.0},
	{"name":"Contato", "file":"Optimized/island_contato.glb", "width":26.0}
]
const SHIP_PATH := "res://Assets/Optimized/sloop_clean_sail.glb"

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
@export var day_duration := 1800.0
@export_range(0.0, 1.0) var day_phase := 0.12
var environment: Environment
var lantern: OmniLight3D
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
var sail_materials: Array[ShaderMaterial] = []
var sail_model: Node3D
var wind_streaks: Node3D
var bow_wave_meshes: Array[MeshInstance3D] = []
var islands: Array[Node3D] = []
var hud: CanvasLayer
var intro_orbit := false
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

func _connect_layout() -> void:
	var layout := Scale.layout()
	if not layout.changed.is_connected(_on_layout_changed):
		layout.changed.connect(_on_layout_changed)

func _on_layout_changed() -> void:
	planet_radius = Scale.radius()
	if Engine.is_editor_hint():
		_update_editor_world()

func _ready() -> void:
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
	_build_islands()
	_update_island_coasts()
	_build_ship()
	_build_lighting()
	_build_bow_wave()
	_build_wind_streaks()
	var clouds := CloudLayerScript.new()
	clouds.name = "CloudLayer"
	clouds.ship = ship
	clouds.clock = clock
	clouds.ocean_materials = ocean.materials
	add_child(clouds)
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
	camera.island_visit_started.connect(_on_island_visit_started)
	var touch := TouchControlsScript.new()
	touch.name = "TouchControls"
	touch.ship = ship
	touch.naval = naval
	touch.camera = camera
	add_child(touch)
	# Abertura (como no nazarejose): o globo gira atrás do cartão de apresentação.
	# Um link direto (?ilha= / ?modo=) pula a abertura.
	var deeplink := OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search", true)).length() > 1
	if deeplink:
		_apply_web_deeplink.call_deferred()
	elif show_intro_on_start:
		ship.enabled = false
		hud.show_intro(true)
		# Órbita cinematográfica em volta da ilha de spawn, deslocada para o lado do cartão.
		intro_orbit = true
		camera.focus_island(islands[clampi(Scale.layout().spawn_island, 0, islands.size() - 1)])
		camera.h_offset = -15.0 if get_viewport().get_visible_rect().size.x > get_viewport().get_visible_rect().size.y else 0.0
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
		var effects := IslandEffects.new()
		effects.name = "IslandEffects"
		effects.index = index
		effects.model = model
		effects.bounds = bounds
		effects.factor = factor
		mount.add_child(effects)
		islands.append(mount)

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
		var lod := ImporterMesh.from_mesh(replacement)
		lod.generate_lods(60.0,0.0,[])
		instance.mesh = lod.get_mesh()

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
	for instance in model.find_children("*", "MeshInstance3D", true, false):
		for surface in range(instance.mesh.get_surface_count()):
			var old: Material = instance.get_active_material(surface)
			if old is StandardMaterial3D and old.albedo_texture:
				var cloth := ShaderMaterial.new()
				cloth.shader = load("res://Shaders/sail_wind.gdshader")
				cloth.set_shader_parameter("albedo_map",old.albedo_texture)
				cloth.set_shader_parameter("bottom",bounds.position.y)
				cloth.set_shader_parameter("height",bounds.size.y)
				cloth.set_shader_parameter("jolly_roger",load("res://Assets/JollyRoger.png"))
				instance.set_surface_override_material(surface,cloth)
				sail_materials.append(cloth)
	lantern = visual.get_node_or_null("CabinLantern") as OmniLight3D
	if lantern == null:
		lantern = OmniLight3D.new()
		lantern.name = "CabinLantern"
		visual.add_child(lantern)
	lantern.position = Vector3(0,1.1,0.5)
	lantern.light_color = Color(1.0, 0.6, 0.26)
	lantern.omni_range = 2.4
	lantern.omni_attenuation = 1.6
	lantern.shadow_enabled = false
	if lantern.get_node_or_null("Flame") == null:
		# Chama do lampião: pequena e emissiva, para a luz parecer vir de dentro do barco.
		var flame := MeshInstance3D.new()
		flame.name = "Flame"
		var bulb := SphereMesh.new()
		bulb.radius = 0.05
		bulb.height = 0.1
		bulb.radial_segments = 8
		bulb.rings = 4
		flame.mesh = bulb
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(1.0, 0.72, 0.35)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.6, 0.25)
		flame.material_override = glow
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lantern.add_child(flame)

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
	sky_material.set_shader_parameter("sun_disk_size", 0.0012)
	sky_material.set_shader_parameter("sun_bloom", 0.08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.84, 0.9)
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = 0.0022
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.0
	node.environment = environment
	sun = get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		add_child(sun)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	moon = get_node_or_null("MoonLight") as DirectionalLight3D
	if moon == null:
		moon = DirectionalLight3D.new()
		moon.name = "MoonLight"
		add_child(moon)
	moon.light_color = Color(0.43,0.59,0.86)

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
	water_droplets = GPUParticles3D.new()
	water_droplets.name = "WaterDroplets"
	# Gotas soltas das cristas das folhas da proa (Seagazer). Quantidade segue a
	# velocidade; a gravidade é atualizada para a vertical local em _process.
	water_droplets.position = Vector3(0,0.55,-1.1)
	water_droplets.amount = 14
	water_droplets.lifetime = 0.75
	water_droplets.emitting = false
	water_droplets.visibility_aabb = AABB(Vector3(-4,-3,-4),Vector3(8,6,8))
	var droplet_motion := ParticleProcessMaterial.new()
	droplet_motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	droplet_motion.emission_box_extents = Vector3(1.0,0.08,0.7)
	droplet_motion.direction = Vector3(0,1,0.35)
	droplet_motion.spread = 50.0
	droplet_motion.initial_velocity_min = 1.6
	droplet_motion.initial_velocity_max = 3.4
	droplet_motion.gravity = Vector3(0,-9.8,0)
	droplet_motion.scale_min = 0.6
	droplet_motion.scale_max = 1.5
	water_droplets.process_material = droplet_motion
	var drop_mesh := QuadMesh.new()
	drop_mesh.size = Vector2(0.11, 0.11)
	var drop_material := ShaderMaterial.new()
	drop_material.shader = load("res://Shaders/water_drop.gdshader")
	drop_mesh.material = drop_material
	water_droplets.draw_pass_1 = drop_mesh
	ship.float_visual.add_child(water_droplets)

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
	window.content_scale_size = Vector2i(480, 854) if screen.x < screen.y else Vector2i(1152, 648)
	# Log Pose menor em tela em pé, para não cobrir a masthead.
	var pose := get_node_or_null("LogPose_HUD/MarginContainer") as Control
	if pose != null:
		var side := 120.0 if screen.x < screen.y else 220.0
		pose.offset_left = -side - 12.0
		pose.offset_right = -12.0
		pose.offset_top = 12.0
		pose.offset_bottom = 12.0 + side
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
	hud.time_attack_pressed.connect(_start_time_attack)
	hud.time_mode_pressed.connect(select_time)
	hud.next_track_pressed.connect(next_track)
	hud.panel_closed.connect(_return_to_navigation)
	hud.start_sailing.connect(_start_sailing)
	hud.set_time_mode(time_mode)
## Links da landing: /world/?ilha=projetos abre direto na ilha; ?modo=regata inicia a regata.
func _apply_web_deeplink() -> void:
	var query := str(JavaScriptBridge.eval("window.location.search", true))
	var params := {}
	for pair in query.trim_prefix("?").split("&", false):
		var parts := pair.split("=")
		params[parts[0].uri_decode()] = parts[1].uri_decode() if parts.size() > 1 else ""
	print("DEEPLINK ", params)
	await get_tree().create_timer(0.8).timeout
	var ids := ["sobre", "experiencia", "formacao", "projetos", "contato"]
	if params.has("ilha") and ids.has(params.ilha):
		_select_island(ids.find(params.ilha))
	elif params.get("modo", "") == "regata":
		_start_time_attack()

func _leave_intro() -> void:
	intro_orbit = false
	camera.h_offset = 0.0
	if hud and hud.intro_visible:
		hud.show_intro(false)
	ship.enabled = true

func _start_sailing() -> void:
	_leave_intro()
	camera.return_to_boat()

func _select_island(index: int) -> void:
	_leave_intro()
	if is_instance_valid(camera) and index >= 0 and index < islands.size():
		camera.focus_island(islands[index])

func _on_island_visit_started(index: int) -> void:
	if intro_orbit:
		return
	if hud: hud.show_island(index)
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

func _update_hud(section: String, nearest: float, nearest_index: int) -> void:
	hud.set_status(section, nearest, ship.measured_speed, Engine.get_frames_per_second())
	# Perto de uma ilha (e navegando), oferece abrir a seção dela.
	var close := nearest_index >= 0 and nearest < 110.0 and camera.state == PortfolioCamera.CameraState.BOAT_FOLLOW
	hud.set_approach(nearest_index if close else -1)
	hud.set_daylight(1.0 - clock.night_at(camera.global_position))
	if is_instance_valid(naval):
		var finished := ""
		if naval.time_attack_mode and not naval.time_attack_running:
			finished = "CONCLUÍDA" if naval.time_attack_hits.size() == naval.course_count else "FIM"
		hud.set_race(naval.time_attack_mode, naval.time_attack_remaining, naval.time_attack_hits.size(), naval.course_count, finished)
	if ship.measured_speed > 1.0:
		hud.notify_player_input()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not ship or not camera:
		return
	var render_transform: Transform3D = ship.get_global_transform_interpolated()
	var render_position: Vector3 = render_transform.origin
	var render_forward: Vector3 = -render_transform.basis.z
	var up := render_position.normalized()
	var wind_world := wind_at(render_position)
	var local_wind := sail_model.global_basis.inverse() * wind_world
	if local_wind.length_squared() < 0.0001:
		local_wind = Vector3.FORWARD * 0.01
	for cloth in sail_materials:
		cloth.set_shader_parameter("wind_direction",local_wind.normalized())
		cloth.set_shader_parameter("boat_speed",ship.measured_speed)
		cloth.set_shader_parameter("wind_strength",(0.04+minf(ship.measured_speed,12.0)*0.004)+0.06*wind_world.length())
	sky_material.set_shader_parameter("local_up", camera.global_position.normalized())
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
		material.set_shader_parameter("boat_cutout_enabled", true)
	var visual_transform: Transform3D = ship.float_visual.get_global_transform_interpolated()
	var bow_forward: Vector3 = -visual_transform.basis.z.normalized()
	var front_height: float = ocean.height_at(visual_transform.origin + bow_forward * 1.75)
	var back_height: float = ocean.height_at(visual_transform.origin - bow_forward * 1.10)
	for material in bow_wave_materials:
		material.set_shader_parameter("ocean_radius",planet_radius)
		material.set_shader_parameter("boat_position",visual_transform.origin)
		material.set_shader_parameter("boat_forward",bow_forward)
		material.set_shader_parameter("boat_right",visual_transform.basis.x.normalized())
		material.set_shader_parameter("water_height_front",front_height)
		material.set_shader_parameter("water_height_back",back_height)
		material.set_shader_parameter("boat_speed",ship.measured_speed)
		material.set_shader_parameter("turn",ship.turn_input)
		material.set_shader_parameter("turn_bias",ship.turn_bias)
		material.set_shader_parameter("daylight",1.0-clock.night_at(render_position))
	for mesh in bow_wave_meshes:
		mesh.visible = ship.measured_speed > 0.4
	# Mais gotas com velocidade e quando a proa mergulha na onda (slam).
	var bow_dip := clampf((back_height - front_height) * 0.8, 0.0, 1.0)
	water_droplets.emitting = ship.measured_speed > 2.5
	water_droplets.amount_ratio = clampf(ship.measured_speed / 16.0 + bow_dip * 0.5, 0.1, 0.8)
	(water_droplets.process_material as ParticleProcessMaterial).gravity = -visual_transform.origin.normalized() * 9.8
	(water_droplets.draw_pass_1.surface_get_material(0) as ShaderMaterial).set_shader_parameter("daylight", 1.0 - clock.night_at(render_position))
	lantern.visible = lantern_enabled and clock.night_at(render_position)>0.05
	var flicker := 0.85 + 0.1 * sin(Time.get_ticks_msec() * 0.011) + 0.05 * sin(Time.get_ticks_msec() * 0.037)
	lantern.light_energy = 0.9 * clock.night_at(render_position) * flicker
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
		if camera.state == PortfolioCamera.CameraState.PLANET_OVERVIEW:
			camera.return_to_boat()
		else:
			camera.show_overview()
		get_viewport().set_input_as_handled()

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
	var point := _water_point(cursor)
	if point == Vector3.INF:
		return
	if last_touch_point == Vector3.INF:
		last_touch_point = point
		return
	var travelled := point.distance_to(last_touch_point)
	if travelled < 1.2:
		return
	var strength := clampf(0.18 + travelled * 0.05, 0.18, 0.5)
	ocean.touch(point, strength, 2.6 + minf(travelled, 6.0) * 0.25)
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
	if web_music:
		_web_music("if (a.paused) { a.play().catch(function(){}); } else { a.pause(); }")
	else:
		music.stream_paused = not music.stream_paused

func next_track() -> void:
	if playlist.is_empty(): return
	if web_music:
		if music_bag.is_empty():
			music_bag.assign(playlist)
			music_bag.shuffle()
		current_track = music_bag.pop_back()
		if hud: hud.set_track(current_track.get_basename())
		# Autoplay pode ser bloqueado até o primeiro gesto; o clique seguinte retoma.
		_web_music("a.src = 'music/' + encodeURIComponent(%s); a.play().catch(function(){ window.__portfolioMusicBlocked = true; });" % JSON.stringify(current_track))
		return
	var was_paused := music.stream_paused
	if music_bag.is_empty():
		music_bag.assign(playlist)
		music_bag.shuffle()
		if music_bag.size()>1 and music_bag.back()==current_track:
			var swap := music_bag[0]
			music_bag[0] = music_bag[-1]
			music_bag[-1] = swap
	current_track = music_bag.pop_back()
	if hud: hud.set_track(current_track.get_file().get_basename())
	var track := load(current_track) as AudioStream
	if track is AudioStreamMP3 or track is AudioStreamOggVorbis: track.loop=false
	elif track is AudioStreamWAV: track.loop_mode=AudioStreamWAV.LOOP_DISABLED
	music.stream = track
	music.play()
	music.stream_paused = was_paused

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

func _update_day(_delta: float) -> void:
	day_phase = clock.time_of_day
	if time_mode!="auto":
		clock.sun_direction = camera.global_position.normalized()*(1.0 if time_mode=="day" else -1.0)
	var toward_sun: Vector3 = clock.sun_direction
	# O céu precisa da mesma direção do sol que a luz (antes ficava sempre de dia no polo).
	sky_material.set_shader_parameter("sun_direction", toward_sun)
	sun.basis = Basis.looking_at(-toward_sun, Vector3.RIGHT if absf(toward_sun.x)<0.95 else Vector3.UP)
	var elevation := camera.global_position.normalized().dot(toward_sun)
	var daylight := smoothstep(-0.16, 0.24, elevation)
	sun.light_energy = 1.15 * daylight
	moon.basis = Basis.looking_at(toward_sun, Vector3.RIGHT if absf(toward_sun.x)<0.95 else Vector3.UP)
	moon.light_energy = 0.32 * (1.0-daylight)
	sun.light_color = Color(1.0,0.57,0.31).lerp(Color(1.0,0.96,0.87), smoothstep(0.0,0.55,elevation))
	environment.ambient_light_color = Color(0.23,0.34,0.58).lerp(Color(0.69,0.79,0.89), daylight)
	environment.ambient_light_energy = lerpf(0.3, 0.55, daylight)
	environment.fog_light_color = Color(0.1, 0.14, 0.28).lerp(Color(0.74, 0.86, 0.95), daylight)
	# Reflexo do céu na água acompanha o horário (pastel de dia, quente no poente, azul à noite).
	var dusk := 1.0 - absf(smoothstep(-0.16, 0.4, elevation) * 2.0 - 1.0)
	var reflection := Color(0.12, 0.17, 0.36).lerp(Color(0.78, 0.85, 0.96), daylight).lerp(Color(1.0, 0.78, 0.68), dusk * 0.6)
	for material in ocean.materials:
		material.set_shader_parameter("night_amount", 1.0 - daylight)
		material.set_shader_parameter("sky_reflection_color", reflection)
