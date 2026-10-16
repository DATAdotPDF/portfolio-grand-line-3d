extends SceneTree

## Clipe de um bicho sozinho (GLB importado no Godot, AnimationPlayer tocando em loop), câmera de lado.
## Mostra a deformação do esqueleto sem o mar escondendo nada.
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie X.avi
##      --script res://Tests/creature_clip.gd -- <glb> <clipe> <segundos>

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var glb: String = args[0] if args.size() > 0 else "dolphin"
	var clip: String = args[1] if args.size() > 1 else "Swim_Leap"
	var seconds: float = float(args[2]) if args.size() > 2 else 6.0
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.75, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.9, 0.95, 1.0)
	env.environment.ambient_light_energy = 0.6
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	root.add_child(sun)
	var creature: Node3D = (load("res://Assets/Optimized/Creatures/%s.glb" % glb) as PackedScene).instantiate()
	root.add_child(creature)
	var aabb := AABB()
	for m in creature.find_children("*", "MeshInstance3D", true, false):
		aabb = (m as MeshInstance3D).get_aabb()
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	# Distância fixa pelo tamanho do bicho no jogo (o AABB de malha com skin vem inflado).
	var distance: float = {"dolphin": 4.6, "gull": 4.2, "flyfish": 1.2, "tentacle": 2.6}.get(glb, 4.0)
	var look := Vector3(0, 0.5, 0) if glb == "tentacle" else Vector3.ZERO
	cam.fov = 45.0
	cam.look_at_from_position(look + Vector3(distance, 0.15 * distance, 0), look)
	var player := creature.find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	player.play(clip)
	for i in int(seconds * 30.0):
		await process_frame
	quit()
