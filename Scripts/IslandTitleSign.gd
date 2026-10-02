@tool
extends Node3D

const TITLES := ["SOBRE","EXPERIÊNCIA","FORMAÇÃO","PROJETOS","CONTATO"]
const PLATES := [
	"res://Assets/Optimized/title_sobre.glb",
	"res://Assets/Optimized/title_experiencia.glb",
	"res://Assets/Optimized/title_formacao.glb",
	"res://Assets/Optimized/title_projetos.glb",
	"res://Assets/Optimized/title_contato.glb"
]
const Shore = preload("res://Scripts/Shoreline.gd")
const PortfolioCamera = preload("res://Scripts/PortfolioCameraController.gd")
@export var island_index := 0
var island: Node3D
var boat: Node3D
var elapsed := 0.0
var proximity_timer := 0.0
var revealed := false
var reveal_amount := 0.0
var reveal_tween: Tween
var base_position := Vector3.ZERO
var meshes: Array[MeshInstance3D] = []
var title_materials: Array[StandardMaterial3D] = []
var title_light: OmniLight3D
@onready var label: Label3D = $TitleText

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	base_position = position
	proximity_timer = island_index*0.04
	var model := (load(PLATES[island_index]) as PackedScene).instantiate() as Node3D
	model.name = "NameplateMesh"
	add_child(model)
	var bounds := AABB()
	var first := true
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var b: AABB = model.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		meshes.append(mesh)
		for surface in range(mesh.mesh.get_surface_count()):
			var original: Material = mesh.get_active_material(surface)
			if original is StandardMaterial3D:
				var paint := original.duplicate() as StandardMaterial3D
				paint.emission_enabled = true
				paint.emission = Color("ffb84a")
				paint.emission_texture = paint.albedo_texture
				# A névoa deixava a placa fosca na visita de dia.
				paint.disable_fog = true
				mesh.set_surface_override_material(surface,paint)
				title_materials.append(paint)
	var factor := 8.0/bounds.size.x
	model.scale = Vector3.ONE*factor
	model.position = -bounds.get_center()*factor
	label.text = TITLES[island_index]
	label.visible = false
	label.name="TitleLabel"
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	label.line_spacing=-4.0
	label.font_size=54
	var widest:=1.0
	for line in label.text.split("\n"):
		widest=maxf(widest,ThemeDB.fallback_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x)
	label.width=widest+8.0
	label.autowrap_mode=TextServer.AUTOWRAP_WORD
	label.pixel_size=minf(0.010,4.9/widest)
	label.position=Vector3(0,0.12,bounds.size.z*factor*0.5+0.05)
	label.modulate=Color("ffd700")
	label.outline_modulate=Color.BLACK
	label.outline_size=14
	label.no_depth_test=false
	# Preserve fitted world size when moving the label under the scaled imported mesh.
	if not meshes.is_empty() and not Engine.is_editor_hint():
		label.reparent(meshes[0],true)
	title_light = OmniLight3D.new()
	title_light.name = "TitleWarmLight"
	title_light.position = Vector3(0,0.5,2.0)
	title_light.omni_range = 4.5
	title_light.light_color = Color("ffe4a0")
	title_light.shadow_enabled = false
	add_child(title_light)
	if Engine.is_editor_hint():
		visible = true
		label.visible = true
		title_light.light_energy = 0.35
		set_process(false)
	else:
		visible = false

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if not boat or not island: return
	elapsed += delta
	proximity_timer -= delta
	if proximity_timer <= 0.0:
		proximity_timer = 0.2
		var distance := INF
		if island.global_position.distance_to(boat.global_position)<float(island.get_meta("navigation_radius"))+36.0:
			distance = Shore.distance_to_coast(island,boat.global_position)
		var navigation_camera := get_viewport().get_camera_3d() as PortfolioCamera
		var focused := navigation_camera and navigation_camera.target_island==island and navigation_camera.state in [PortfolioCamera.CameraState.FLYING,PortfolioCamera.CameraState.ISLAND_ORBIT]
		var inspecting_other := navigation_camera and navigation_camera.state in [PortfolioCamera.CameraState.FLYING,PortfolioCamera.CameraState.ISLAND_ORBIT] and navigation_camera.target_island!=island
		var show_sign := focused or (not inspecting_other and navigation_camera and navigation_camera.state==PortfolioCamera.CameraState.BOAT_FOLLOW and distance<35.0)
		if show_sign != revealed:
			revealed = show_sign
			if reveal_tween: reveal_tween.kill()
			reveal_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			reveal_tween.tween_property(self,"reveal_amount",1.0 if revealed else 0.0,0.65)
	visible = reveal_amount>0.005
	if not visible: return
	var night: float = get_node("/root/DayNightCycle").night_at(island.global_position)
	for material in title_materials: material.emission_energy_multiplier = lerpf(0.04,0.24,night)
	title_light.light_energy = lerpf(0.15,0.55,night)*reveal_amount
	position = base_position+Vector3.UP*sin(elapsed*1.2+island_index)*0.22
	var camera := get_viewport().get_camera_3d()
	if camera:
		# The whole sign faces the camera, so its text stays on the parchment.
		look_at(camera.global_position,global_position.normalized(),true)
		rotate_object_local(Vector3.FORWARD,sin(elapsed*0.7)*0.018)
	scale = Vector3.ONE*maxf(0.005,reveal_amount)
	label.modulate.a = reveal_amount
	for mesh in meshes: mesh.transparency = 1.0-reveal_amount
