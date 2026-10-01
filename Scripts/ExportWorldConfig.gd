extends SceneTree

const CameraSettings = preload("res://Scripts/PortfolioCameraController.gd")
const Scale = preload("res://Scripts/WorldScale.gd")
const TitleSettings = preload("res://Scripts/IslandTitleSign.gd")

const OUTPUT := "res://Export/world_config.json"
const SECTIONS := ["sobre", "experiencia", "formacao", "projetos", "contato"]

func _initialize() -> void:
	call_deferred("export_world")

func vec3(value: Vector3) -> Array[float]:
	return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001), snappedf(value.z, 0.0001)]

func transform_data(value: Transform3D) -> Dictionary:
	var rotation := value.basis.get_rotation_quaternion()
	return {
		"position": vec3(value.origin),
		"quaternion_xyzw": [snappedf(rotation.x, 0.000001), snappedf(rotation.y, 0.000001), snappedf(rotation.z, 0.000001), snappedf(rotation.w, 0.000001)],
		"scale": vec3(value.basis.get_scale())
	}

func export_world() -> void:
	var world: Variant = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	root.add_child(world)
	var ocean: Variant = world.ocean
	var data := {
		"schema_version": 2,
		"snapshot_status": "current",
		"units": "meters",
		"coordinate_system": "right-handed, Y up, -Z forward",
		"planet": {"center": [0.0, 0.0, 0.0], "water_radius": world.planet_radius, "bed_radius": world.planet_radius - world.SEABED_DEPTH},
		"boat": {"model": world.SHIP_PATH.trim_prefix("res://"), "length": world.SHIP_LENGTH, "spawn": transform_data(world.ship.global_transform), "model_local": transform_data(world.sail_model.transform), "cruise_speed": 4.2, "shift_speed": 12.5},
		"waves": {"strength": Scale.layout().wave_strength, "swell_wavelength": Scale.layout().swell_wavelength, "speed": Scale.layout().wave_speed, "wind_axis": vec3(Scale.wind_axis()), "components": []},
		"islands": [],
		"naval_targets": [],
		"gameplay": {"target_respawn_seconds": world.naval.target_respawn_seconds, "cannon_fuse_seconds": world.naval.fuse_duration, "time_attack_duration_seconds": world.naval.time_attack_duration, "time_attack_target_count": world.naval.targets.size()},
		"day_night": {"cycle_seconds": world.day_duration, "manual_options": ["auto", "day", "night"]},
		"camera": {"follow_distance": world.camera.follow_distance, "follow_height": world.camera.follow_height, "fov_deg": world.camera.fov, "overview_radius": world.planet_radius * 2.6, "island_profiles": []}
	}
	for item in Scale.wave_components():
		data.waves.components.append({"direction": vec3(item.dir), "amplitude": item.amplitude, "wavelength": TAU / float(item.k), "phase_offset": item.phase, "steepness": item.steepness})
	for i in range(world.islands.size()):
		var island: Node3D = world.islands[i]
		var model: Node3D = island.get_node("IslandModel")
		var sign: Node3D = island.get_node("IslandTitleSign")
		world.camera._frame_island_geometry(island, i)
		data.camera.island_profiles.append({"id": SECTIONS[i], "focus_height": world.camera.framed_focus_height, "orbit_distance": world.camera.framed_orbit_distance, "pitch_deg": CameraSettings.ORBIT_PITCHES[i]})
		data.islands.append({
			"id": SECTIONS[i],
			"title": island.get_meta("section"),
			"model": "Assets/" + world.ISLANDS[i].file,
			"model_local": transform_data(model.transform),
			"mount": transform_data(island.global_transform),
			"title_local": transform_data(sign.transform),
			"coast_width": world.ISLANDS[i].width,
			"waterline_fraction": island.get_meta("waterline_fraction"),
			"title_model": TitleSettings.PLATES[i].trim_prefix("res://")
		})
	for target in world.naval.targets:
		data.naval_targets.append({"id": target.id, "normal": vec3(target.normal), "position": vec3(target.normal * world.planet_radius), "island_index": target.island})
	var absolute := ProjectSettings.globalize_path(OUTPUT)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		push_error("Não foi possível criar Export: %d" % error)
		quit(1)
		return
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível abrir %s" % OUTPUT)
		quit(1)
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	print("WORLD_CONFIG_EXPORTED islands=", data.islands.size(), " targets=", data.naval_targets.size(), " path=", absolute)
	quit()
