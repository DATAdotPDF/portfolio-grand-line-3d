extends SceneTree

## Carga headless do mundo: confere bestas (SeaBeasts), tartaruga com o rig do Meshy e os bichos.
## Uso: Godot.exe --headless --path . --script res://Tests/beasts_load_check.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	for i in 30:
		await process_frame
	var beasts: Node = world.get("sea_beasts")
	var report := []
	if beasts:
		for b in beasts.beasts:
			var player: AnimationPlayer = b.player
			report.append("%s pos=%s anim=%s len=%.0f" % [b.name, (b.root as Node3D).global_position.round(),
				player.current_animation if player else "-", b.length])
	var turtle: Dictionary = world.world_decor.turtle
	var skel := turtle.get("skeleton") as Skeleton3D
	var bones := 0
	if skel:
		for f in turtle.flippers:
			if skel.find_bone(f.tip) >= 0 and skel.find_bone(f.base) >= 0:
				bones += 1
	print("LOAD_OK beasts=%s turtle_flippers=%d turtle_sound=%s" % [report, bones, not beasts.turtle_sound.is_empty()])
	quit()
