extends Node3D

const ASSETS := [
	"res://Assets/Meshy_AI_island_1_about_harbor_0929193106_image-to-3d-texture.glb",
	"res://Assets/Meshy_AI_island_2_experience_f_0929193424_image-to-3d-texture.glb",
	"res://Assets/Meshy_AI_island_3_formation_po_0929193844_image-to-3d-texture.glb",
	"res://Assets/Meshy_AI_island_4_projects_shi_0929194206_image-to-3d-texture.glb",
	"res://Assets/Meshy_AI_island_5_contact_ligh_0929194453_image-to-3d-texture.glb"
]

func _ready() -> void:
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 55.0
	add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -45, 0)
	light.light_energy = 1.8
	add_child(light)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.62, 0.72, 0.82)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	add_child(environment)
	for index in range(ASSETS.size()):
		var model := (load(ASSETS[index]) as PackedScene).instantiate() as Node3D
		add_child(model)
		var bounds := _bounds(model)
		var fit := 18.0 / maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		model.scale = Vector3.ONE * fit
		model.position = -bounds.get_center() * fit
		for view_index in range(3):
			var eye: Vector3
			match view_index:
				0: eye = Vector3(0, 12, 42)
				1: eye = Vector3(42, 12, 0)
				_: eye = Vector3(0, 42, 0.01)
			camera.global_position = eye
			camera.look_at(Vector3.ZERO, Vector3.UP if view_index < 2 else Vector3.BACK)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var path := "user://axis_island_%02d_view_%d.png" % [index + 1, view_index]
			var error := get_viewport().get_texture().get_image().save_png(path)
			print("AXIS_AUDIT ", index + 1, " view=", view_index, " path=", ProjectSettings.globalize_path(path), " error=", error)
		model.queue_free()
		await get_tree().process_frame

func _bounds(node: Node3D) -> AABB:
	var total := AABB()
	var found := false
	for candidate in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := candidate as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var relative: Transform3D = node.global_transform.affine_inverse() * mesh.global_transform
		var part: AABB = relative * mesh.get_aabb()
		total = total.merge(part) if found else part
		found = true
	return total
