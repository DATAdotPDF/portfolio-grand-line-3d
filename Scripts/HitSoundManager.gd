extends Node

const HIT_THUD = preload("res://Assets/Sound/SFX/WOOD IMPACT CANON BALL SFX.wav")
const HITMARKER = preload("res://Assets/Sound/SFX/hitmarker_bell.wav")
var bell: AudioStreamPlayer
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	bell = AudioStreamPlayer.new()
	bell.name = "Hitmarker2D"
	bell.stream = HITMARKER
	bell.volume_db = -8.0
	add_child(bell)

func play_hit(position: Vector3) -> void:
	bell.pitch_scale = rng.randf_range(0.95,1.05)
	bell.play()
	var impact := AudioStreamPlayer3D.new()
	impact.name = "WoodHit3D"
	impact.stream = HIT_THUD
	impact.volume_db = -3.0
	impact.unit_size = 14.0
	impact.max_distance = 100.0
	impact.pitch_scale = rng.randf_range(0.95,1.05)
	var scene := get_tree().current_scene
	(scene if scene else get_tree().root).add_child(impact)
	impact.global_position = position
	impact.finished.connect(impact.queue_free)
	impact.play()
