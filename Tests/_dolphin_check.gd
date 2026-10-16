extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.35, 0.45, 0.55)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color.WHITE
	root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); root.add_child(sun)
	var d: Node3D = (load("res://Assets/Optimized/Creatures/dolphin.glb") as PackedScene).instantiate()
	root.add_child(d)
	var cam := Camera3D.new(); root.add_child(cam); cam.make_current()
	cam.look_at_from_position(Vector3(4.2, 0.2, 0), Vector3.ZERO)
	var p := d.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sk := d.find_child("Skeleton3D", true, false) as Skeleton3D
	print("SKEL bones=", sk.get_bone_count(), " anims=", p.get_animation_list())
	var mi := d.find_child("*", true, false)
	for m in d.find_children("*", "MeshInstance3D", true, false):
		print("MESH ", m.name, " skin=", m.skin != null, " skeleton=", m.skeleton)
	p.play("Swim_Leap")
	var len := p.current_animation_length
	for k in 5:
		var t := len * k / 5.0
		p.seek(t, true)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://Builds/Creatures/_godot_dolphin_%d.png" % k))
		print("POSE t=%.2f tail=%s" % [t, sk.get_bone_global_pose(sk.find_bone("Tail_03")).origin])
	quit()
