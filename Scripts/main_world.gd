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
const OCEAN_RADIUS := Scale.OCEAN_RADIUS
const SHIP_LENGTH := 4.8
const ISLANDS := [
	{"name":"Sobre", "file":"Meshy_AI_island_1_about_harbor_0929193106_image-to-3d-texture.glb", "width":28.0},
	{"name":"Experiência", "file":"Meshy_AI_island_2_experience_f_0929193424_image-to-3d-texture.glb", "width":32.0},
	{"name":"Formação", "file":"Meshy_AI_island_3_formation_po_0929193844_image-to-3d-texture.glb", "width":30.0},
	{"name":"Projetos", "file":"Meshy_AI_island_4_projects_shi_0929194206_image-to-3d-texture.glb", "width":32.0},
	{"name":"Contato", "file":"Meshy_AI_island_5_contact_ligh_0929194453_image-to-3d-texture.glb", "width":26.0}
]
const SHIP_PATH := "res://Assets/(Chalupe Op2) Meshy_AI_clean_sail_pirate_slo_0929203741_image-to-3d-texture.glb"
@export var day_duration := 1800.0
@export_range(0.0, 1.0) var day_phase := 0.12
var environment: Environment
var lantern: OmniLight3D
var lantern_enabled := true
var clock: Node
var music: AudioStreamPlayer
var sea_ambience: Node3D
var music_button: Button
var playlist: Array[String] = []
var music_bag: Array[String] = []
var current_track := ""
var naval: Node3D
var time_mode := "auto"
var time_buttons: Array[Button] = []
var water_held := false
var water_cursor := Vector2.ZERO
var touch_timer := 0.0
var ocean: Node
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
var status: Label
var log_pose: Node3D
@export_group("Editor Planet")
@export_node_path("MeshInstance3D") var ocean_mesh_path: NodePath = ^"OceanMesh"
@export_node_path("MeshInstance3D") var seabed_mesh_path: NodePath = ^"SeabedMesh"
@export_node_path("Node3D") var island_anchors_path: NodePath = ^"IslandAnchors"
@export_node_path("CharacterBody3D") var player_ship_path: NodePath = ^"PlayerShip"
@export_node_path("Camera3D") var camera_path: NodePath = ^"CameraPivot/FollowCamera"
var planet_radius := 200.0
var wave_strength := 3.0
var wavelength_scale := 1.0
var wind_speed := 1.0
var wind_direction := Vector3(0.9, 0.15, 0.3)

func _read_ocean_settings() -> void:
	var ocean_node := get_node_or_null(ocean_mesh_path) as MeshInstance3D
	if ocean_node == null:
		return
	var sphere := ocean_node.mesh as SphereMesh
	if sphere != null:
		planet_radius = sphere.radius
	var material := ocean_node.material_override as ShaderMaterial
	if material == null:
		return
	wave_strength = float(material.get_shader_parameter("wave_strength"))
	wavelength_scale = float(material.get_shader_parameter("wavelength_scale"))
	wind_speed = float(material.get_shader_parameter("wave_speed"))
	wind_direction = material.get_shader_parameter("wind_direction")
	if wind_direction.length_squared() < 0.0001:
		wind_direction = Vector3.FORWARD

func _on_ocean_mesh_changed() -> void:
	if not Engine.is_editor_hint():
		return
	_read_ocean_settings()
	_update_editor_ocean()

func _ready() -> void:
	_read_ocean_settings()
	if Engine.is_editor_hint():
		var ocean_node := get_node_or_null(ocean_mesh_path) as MeshInstance3D
		if ocean_node != null and ocean_node.mesh is SphereMesh:
			var sphere := ocean_node.mesh as SphereMesh
			if not sphere.changed.is_connected(_on_ocean_mesh_changed):
				sphere.changed.connect(_on_ocean_mesh_changed)
		_update_editor_ocean()
		return
	clock = get_node("/root/DayNightCycle")
	clock.day_duration_seconds = day_duration
	ocean = Waves.new()
	ocean.name = "OceanSimulation"
	ocean.radius = planet_radius
	ocean.wave_strength = wave_strength
	ocean.wavelength_scale = wavelength_scale
	ocean.wave_speed = wind_speed
	add_child(ocean)
	_build_ocean()
	_build_islands()
	var coast_centers:=PackedVector3Array()
	var coast_radii:=PackedFloat32Array()
	for i in range(islands.size()):
		coast_centers.append(islands[i].position.normalized())
		coast_radii.append(float(ISLANDS[i].width)*0.46)
	ocean.island_centers = coast_centers
	ocean.island_radii = coast_radii
	for material in ocean.materials:
		material.set_shader_parameter("island_centers",coast_centers)
		material.set_shader_parameter("island_radii",coast_radii)
		material.set_shader_parameter("shore_screen_enabled",1.0)
	_build_ship()
	_build_lighting()
	_build_bow_wave()
	_build_wind_streaks()
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
	camera.far = 1500.0
	camera.current = true
	camera.snap_to_boat()
	_build_titles()
	naval = NavalGame.new()
	naval.name = "NavalGame"
	naval.world = self
	add_child(naval)
	camera.island_visit_started.connect(_on_island_visit_started)
	print("WORLD_READY radius=", OCEAN_RADIUS, " ship_length=4.8 islands=5 solid_colliders=5")

func _update_editor_ocean() -> void:
	var ocean_node := get_node_or_null(ocean_mesh_path) as MeshInstance3D
	if ocean_node != null:
		var ocean_material := ocean_node.material_override as ShaderMaterial
		if ocean_material != null:
			if Engine.is_editor_hint():
				ocean_material.set_shader_parameter("boat_cutout_enabled", false)
				ocean_material.set_shader_parameter("use_simulation_time", false)
				var anchors := get_node_or_null(island_anchors_path) as Node3D
				if anchors != null:
					var centers := PackedVector3Array()
					var radii := PackedFloat32Array()
					for index in range(mini(anchors.get_child_count(), ISLANDS.size())):
						var anchor := anchors.get_child(index) as Node3D
						centers.append(anchor.global_position.normalized())
						radii.append(float(ISLANDS[index].width) * 0.46)
					ocean_material.set_shader_parameter("island_centers", centers)
					ocean_material.set_shader_parameter("island_radii", radii)
			ocean_material.set_shader_parameter("planet_radius", planet_radius)
	var wind_node := get_node_or_null("WindRibbonSystem")
	if wind_node != null:
		wind_node.wind_direction = wind_direction
	var bed_node := get_node_or_null(seabed_mesh_path) as MeshInstance3D
	if bed_node != null:
		var bed_sphere := bed_node.mesh as SphereMesh
		if bed_sphere != null:
			bed_sphere.radius = planet_radius - 5.0
			bed_sphere.height = (planet_radius - 5.0) * 2.0
	var core := get_node_or_null("PlanetCore/CollisionShape3D") as CollisionShape3D
	if core != null:
		var core_sphere := core.shape as SphereShape3D
		if core_sphere != null:
			core_sphere.radius = planet_radius - 4.0

func _build_ocean() -> void:
	var body := get_node_or_null("PlanetCore") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "PlanetCore"
		add_child(body)
	var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		body.add_child(collision)
	var shape := collision.shape as SphereShape3D
	if shape == null:
		shape = SphereShape3D.new()
		collision.shape = shape
	shape.radius = OCEAN_RADIUS - 4.0
	var bed := get_node_or_null(seabed_mesh_path) as MeshInstance3D
	if bed == null:
		bed = MeshInstance3D.new()
		bed.name = "SeabedMesh"
		var bed_mesh := SphereMesh.new()
		bed_mesh.radius = OCEAN_RADIUS - 5.0
		bed_mesh.height = (OCEAN_RADIUS - 5.0) * 2.0
		bed_mesh.radial_segments = 128
		bed_mesh.rings = 64
		bed.mesh = bed_mesh
		var bed_material := StandardMaterial3D.new()
		bed_material.albedo_color = Color("202b35")
		bed_material.roughness = 1.0
		bed.material_override = bed_material
		add_child(bed)
	var ocean_mesh := get_node_or_null(ocean_mesh_path) as MeshInstance3D
	if ocean_mesh == null:
		ocean_mesh = MeshInstance3D.new()
		ocean_mesh.name = "OceanMesh"
		var sphere := SphereMesh.new()
		sphere.radius = OCEAN_RADIUS
		sphere.height = OCEAN_RADIUS * 2.0
		sphere.radial_segments = 384
		sphere.rings = 192
		ocean_mesh.mesh = sphere
		add_child(ocean_mesh)
	var material := ocean_mesh.material_override as ShaderMaterial
	if material == null:
		material = ShaderMaterial.new()
		material.shader = load("res://Shaders/ocean.gdshader")
		ocean_mesh.material_override = material
	material.set_shader_parameter("planet_radius", OCEAN_RADIUS)
	ocean.register_material(material)
	ocean_mesh.extra_cull_margin = 6.0
	ocean_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update_editor_ocean()

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
	for index in range(ISLANDS.size()):
		var data: Dictionary = ISLANDS[index]
		var mount := get_node(island_anchors_path).get_child(index) as Node3D
		mount.set_meta("section", data.name)
		var model := mount.get_node_or_null("IslandModel") as Node3D
		var created_model := model == null
		if model == null:
			model = (load("res://Assets/" + data.file) as PackedScene).instantiate() as Node3D
			model.name = "IslandModel"
			mount.add_child(model)
		var bounds := _model_bounds(model)
		var factor: float = model.scale.x
		if created_model:
			factor = float(data.width) / maxf(bounds.size.x, bounds.size.z)
			model.scale = Vector3.ONE * factor
		if index == 0:
			_remove_harbor_baked_water(model, bounds, factor)
		# Leave only the lowest half metre below the waterline.
		if created_model:
			model.position.y = -bounds.position.y * factor - 0.5
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
		Shore.build(mount,model,OCEAN_RADIUS)
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
		var spawn_up := (get_node(island_anchors_path).get_child(0) as Node3D).position.normalized()
		var spawn_axis := spawn_up.cross(Vector3.UP).normalized()
		ship.position = spawn_up.rotated(spawn_axis, 44.0 / OCEAN_RADIUS) * OCEAN_RADIUS
		add_child(ship)
	ship.ocean = ocean
	ship.islands = islands
	ship.wind_direction = wind_direction
	ship.wind_strength = clampf(wind_speed, 0.0, 1.0)
	var first_up := (get_node(island_anchors_path).get_child(0) as Node3D).position.normalized()
	ship.heading = first_up.slide(ship.position.normalized()).normalized()
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
	lantern.light_color = Color("ffe48a")
	lantern.omni_range = 5.0

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
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.84, 0.9)
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	node.environment = environment
	sun = get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		add_child(sun)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0
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
		grid.subdivide_width = 63
		grid.subdivide_depth = 15
		mesh.mesh = grid
		mesh.custom_aabb = AABB(Vector3(-4,-2,-4), Vector3(8,6,8))
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = load("res://Shaders/BowWaveSheet.gdshader")
		material.set_shader_parameter("side", side)
		material.set_shader_parameter("foam_pattern",load("res://Shaders/wind_waker_foam.png"))
		material.set_shader_parameter("ocean_radius",OCEAN_RADIUS)
		mesh.material_override = material
		ship.float_visual.add_child(mesh)
		bow_wave_materials.append(material)
		bow_wave_meshes.append(mesh)
	water_droplets = GPUParticles3D.new()
	water_droplets.name = "WaterDroplets"
	water_droplets.position = Vector3(0,0.38,-1.48)
	water_droplets.amount = 12
	water_droplets.lifetime = 0.4
	water_droplets.emitting = false
	water_droplets.visibility_aabb = AABB(Vector3(-2,-2,-2),Vector3(4,4,4))
	var droplet_motion := ParticleProcessMaterial.new()
	droplet_motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	droplet_motion.emission_box_extents = Vector3(0.55,0.03,0.08)
	droplet_motion.direction = Vector3(0,1,0)
	droplet_motion.spread = 36.0
	droplet_motion.initial_velocity_min = 1.2
	droplet_motion.initial_velocity_max = 2.2
	droplet_motion.gravity = Vector3(0,-5.0,0)
	water_droplets.process_material = droplet_motion
	var drop_mesh := SphereMesh.new()
	drop_mesh.radius = 0.025
	drop_mesh.height = 0.05
	drop_mesh.radial_segments = 6
	drop_mesh.rings = 3
	var drop_material := StandardMaterial3D.new()
	drop_material.albedo_color = Color(0.82,0.96,0.99,0.85)
	drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
	wind_streaks.wind_direction = wind_direction

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "NavigationHUD"
	add_child(layer)
	var instructions := Label.new()
	instructions.text = "NAVIO  W/S acelera e freia · A/D vira · Shift impulso\nBÚSSOLA  ilha mais próxima · 1–5 visita · 0/Esc barco · Tab globo\nÁGUA  arraste esquerdo · CÂMERA  arraste direito\nCANHÃO  Q/E gira · R/F inclina · Espaço atira"
	instructions.position = Vector2(24, 20)
	instructions.add_theme_font_size_override("font_size", 16)
	instructions.add_theme_color_override("font_color", Color(0.91,0.96,1.0))
	instructions.add_theme_color_override("font_shadow_color", Color(0.0,0.02,0.06,0.95))
	instructions.add_theme_constant_override("shadow_offset_x", 1)
	instructions.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(instructions)
	status = Label.new()
	status.position = Vector2(24, 116)
	status.add_theme_font_size_override("font_size", 16)
	status.add_theme_color_override("font_color", Color(0.91,0.96,1.0))
	status.add_theme_color_override("font_shadow_color", Color(0.0,0.02,0.06,0.95))
	status.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(status)
	var mode_bar := HBoxContainer.new()
	mode_bar.position = Vector2(24, 220)
	mode_bar.add_theme_constant_override("separation", 8)
	layer.add_child(mode_bar)
	var free_button := Button.new()
	free_button.text = "Navegar livre"
	free_button.focus_mode = Control.FOCUS_NONE
	free_button.pressed.connect(_return_to_navigation)
	mode_bar.add_child(free_button)
	for index in range(islands.size()):
		var island_button := Button.new()
		island_button.text = "%d %s" % [index + 1, ISLANDS[index].name]
		island_button.focus_mode = Control.FOCUS_NONE
		island_button.pressed.connect(_select_island.bind(index))
		mode_bar.add_child(island_button)
	var attack_button := Button.new()
	attack_button.text = "Time Attack · 3 min"
	attack_button.focus_mode = Control.FOCUS_NONE
	attack_button.pressed.connect(_start_time_attack)
	mode_bar.add_child(attack_button)
	var panel := HBoxContainer.new()
	panel.position = Vector2(get_viewport().get_visible_rect().size.x-220,244)
	get_viewport().size_changed.connect(func(): panel.position.x=get_viewport().get_visible_rect().size.x-220)
	layer.add_child(panel)
	for mode in ["auto","day","night"]:
		var button := Button.new()
		button.text = {"auto":"Ciclo","day":"Dia","night":"Noite"}[mode]
		button.toggle_mode = true
		button.button_pressed = mode==time_mode
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(select_time.bind(mode))
		panel.add_child(button)
		time_buttons.append(button)
	music_button = Button.new()
	music_button.text = "Próxima música (N)"
	music_button.position = Vector2(get_viewport().get_visible_rect().size.x-185,284)
	music_button.focus_mode = Control.FOCUS_NONE
	music_button.pressed.connect(next_track)
	get_viewport().size_changed.connect(func(): music_button.position.x=get_viewport().get_visible_rect().size.x-185)
	layer.add_child(music_button)

func _select_island(index: int) -> void:
	if is_instance_valid(camera) and index >= 0 and index < islands.size():
		camera.focus_island(islands[index])

func _on_island_visit_started(_index: int) -> void:
	if is_instance_valid(naval) and bool(naval.get("time_attack_mode")):
		naval.call("leave_time_attack")

func _return_to_navigation() -> void:
	if is_instance_valid(naval):
		naval.call("leave_time_attack")
	if is_instance_valid(camera):
		camera.return_to_boat()

func _start_time_attack() -> void:
	if is_instance_valid(camera):
		if camera.state != PortfolioCamera.CameraState.BOAT_FOLLOW:
			camera.return_to_boat()
			await camera.transition_tween.finished
	if is_instance_valid(naval):
		naval.call("start_time_attack")

func _build_log_pose() -> void:
	var hud := LogPose.instantiate()
	add_child(hud)
	log_pose = hud.get_node("MarginContainer/SubViewportContainer/SubViewport/LogPose_Master")
	log_pose.player_sloop = ship
	log_pose.islands_parent = get_node(island_anchors_path)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not ship or not camera:
		return
	var render_transform: Transform3D = ship.get_global_transform_interpolated()
	var render_position: Vector3 = render_transform.origin
	var render_forward: Vector3 = -render_transform.basis.z
	var up := render_position.normalized()
	var wind_world := wind_direction.slide(up).normalized()
	var local_wind := sail_model.global_basis.inverse()*wind_world
	for cloth in sail_materials:
		cloth.set_shader_parameter("wind_direction",local_wind.normalized())
		cloth.set_shader_parameter("boat_speed",ship.measured_speed)
		cloth.set_shader_parameter("wind_strength",0.075+minf(ship.measured_speed,12.0)*0.004)
	sky_material.set_shader_parameter("local_up", camera.global_position.normalized())
	_update_day(delta)
	if water_held:
		touch_timer -= delta
		if touch_timer <= 0.0:
			_touch_water(water_cursor)
			touch_timer = 0.22
	for material in ocean.materials:
		material.set_shader_parameter("boat_position", render_position)
		material.set_shader_parameter("boat_forward", render_forward)
		material.set_shader_parameter("boat_right", render_forward.cross(up))
		material.set_shader_parameter("boat_cutout_enabled", true)
		material.set_shader_parameter("turn", ship.turn_input)
	var visual_transform: Transform3D = ship.float_visual.get_global_transform_interpolated()
	var bow_forward: Vector3 = -visual_transform.basis.z.normalized()
	var front_height: float = ocean.height_at(visual_transform.origin + bow_forward * 1.75)
	var back_height: float = ocean.height_at(visual_transform.origin - bow_forward * 1.10)
	for material in bow_wave_materials:
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
	water_droplets.emitting = ship.measured_speed > 3.0
	lantern.visible = lantern_enabled and clock.night_at(render_position)>0.05
	lantern.light_energy = 2.0*clock.night_at(render_position)
	var nearest := INF
	var section := ""
	for island in islands:
		var distance := acos(clampf(up.dot(island.position.normalized()), -1.0, 1.0)) * OCEAN_RADIUS
		if distance < nearest:
			nearest = distance
			section = island.get_meta("section")
	status.text = "%s · %.0f m    |    %.1f m/s    |    %d FPS" % [section, nearest, ship.measured_speed, Engine.get_frames_per_second()]

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera.drag_orbit(event.relative)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_5:
			camera.focus_island(islands[event.physical_keycode - KEY_1])
		elif event.physical_keycode == KEY_TAB:
			camera.show_overview()
		elif event.physical_keycode == KEY_B:
			camera.return_to_boat()
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		music.stream_paused = not music.stream_paused
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_N:
		next_track()
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_L:
		lantern_enabled = not lantern_enabled
	if event is InputEventMouseMotion:
		water_cursor = event.position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		water_held = event.pressed
		water_cursor = event.position
		if water_held:
			_touch_water(water_cursor)
			touch_timer = 0.22

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		water_held = false

func _touch_water(cursor: Vector2) -> void:
	var origin := camera.project_ray_origin(cursor)
	var direction := camera.project_ray_normal(cursor)
	var b := origin.dot(direction)
	var discriminant := b*b - origin.length_squared() + OCEAN_RADIUS*OCEAN_RADIUS
	if discriminant < 0.0:
		return
	var distance := -b - sqrt(discriminant)
	if distance > 0.0:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * distance, 3)
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			ocean.touch(origin + direction * distance)

func _build_audio() -> void:
	sea_ambience = SeaAmbience.new()
	sea_ambience.name = "SeaAmbience"
	sea_ambience.ship = ship
	sea_ambience.ocean = ocean
	add_child(sea_ambience)
	music = AudioStreamPlayer.new()
	music.name = "BackgroundMusic"
	music.volume_db = -18.0
	add_child(music)
	for file in DirAccess.get_files_at("res://Assets/Sound"):
		if file.get_extension().to_lower() in ["mp3","ogg","wav"]:
			playlist.append("res://Assets/Sound/"+file)
	music.finished.connect(next_track)
	next_track()

func next_track() -> void:
	if playlist.is_empty(): return
	var was_paused := music.stream_paused
	if music_bag.is_empty():
		music_bag.assign(playlist)
		music_bag.shuffle()
		if music_bag.size()>1 and music_bag.back()==current_track:
			var swap := music_bag[0]
			music_bag[0] = music_bag[-1]
			music_bag[-1] = swap
	current_track = music_bag.pop_back()
	if music_button: music_button.tooltip_text = "Tocando: "+current_track.get_file().get_basename()
	var track := load(current_track) as AudioStream
	if track is AudioStreamMP3 or track is AudioStreamOggVorbis: track.loop=false
	elif track is AudioStreamWAV: track.loop_mode=AudioStreamWAV.LOOP_DISABLED
	music.stream = track
	music.play()
	music.stream_paused = was_paused

func select_time(mode: String) -> void:
	time_mode = mode
	water_held = false
	for i in range(time_buttons.size()): time_buttons[i].button_pressed = ["auto","day","night"][i]==mode
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
			var model: Node3D = islands[i].get_node("IslandModel")
			var bounds := _model_bounds(model)
			title_sign.position.y = maxf(25.0 if i==4 else 12.0,model.position.y+bounds.end.y*model.scale.y+3.0)
			islands[i].add_child(title_sign)
		title_sign.set("island_index", i)
		title_sign.set("island", islands[i])
		title_sign.set("boat", ship)

func _update_day(_delta: float) -> void:
	day_phase = clock.time_of_day
	if time_mode!="auto":
		clock.sun_direction = camera.global_position.normalized()*(1.0 if time_mode=="day" else -1.0)
	var toward_sun: Vector3 = clock.sun_direction
	sun.basis = Basis.looking_at(-toward_sun, Vector3.RIGHT if absf(toward_sun.x)<0.95 else Vector3.UP)
	var elevation := camera.global_position.normalized().dot(toward_sun)
	var daylight := smoothstep(-0.16, 0.24, elevation)
	sun.light_energy = 1.15 * daylight
	moon.basis = Basis.looking_at(toward_sun, Vector3.RIGHT if absf(toward_sun.x)<0.95 else Vector3.UP)
	moon.light_energy = 0.32 * (1.0-daylight)
	sun.light_color = Color(1.0,0.57,0.31).lerp(Color(1.0,0.96,0.87), smoothstep(0.0,0.55,elevation))
	environment.ambient_light_color = Color(0.23,0.34,0.58).lerp(Color(0.69,0.79,0.89), daylight)
	environment.ambient_light_energy = lerpf(0.3, 0.55, daylight)
