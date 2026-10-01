extends Node3D

const GULLS = preload("res://Assets/Sound/SFX/SEAGULLS OPEN SEA SFX 1.mp3")
const WOOD = preload("res://Assets/Sound/SFX/WOODEN BOAT OPEN SEA SFX.mp3")
const BREAKER = preload("res://Assets/Sound/SFX/OCEAN WAVE CRASH SFX.mp3")

@export var min_silence_seconds := 18.0
@export var max_silence_seconds := 45.0
@export var orbit_radius := 35.0
@export var flight_height := 22.0

var ship: CharacterBody3D
var ocean: Node
var ocean_bed: AudioStreamPlayer
var gull_call: AudioStreamPlayer3D
var gull_timer: Timer
var boat_creak: AudioStreamPlayer3D
var bow_crash: AudioStreamPlayer3D
var crash_timer := 3.0
var remaining_followups := 0
var in_burst := false
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

	ocean_bed = AudioStreamPlayer.new()
	ocean_bed.name = "OceanBed"
	ocean_bed.stream = _make_ocean_bed()
	ocean_bed.volume_db = -31.0
	add_child(ocean_bed)
	ocean_bed.play()

	var wood_loop := WOOD.duplicate() as AudioStreamMP3
	wood_loop.loop = true
	boat_creak = _ship_sound("WoodenBoat", wood_loop, -22.0, 25.0)
	bow_crash = _ship_sound("BowWaveCrash", BREAKER, -18.0, 45.0)
	bow_crash.position = Vector3(0.0, 0.15, -1.55)

	gull_call = AudioStreamPlayer3D.new()
	gull_call.name = "SeagullAmbience"
	gull_call.stream = GULLS.duplicate()
	if gull_call.stream is AudioStreamMP3:
		(gull_call.stream as AudioStreamMP3).loop = false
	gull_call.top_level = true
	gull_call.autoplay = false
	gull_call.volume_db = -18.0
	gull_call.unit_size = 22.0
	gull_call.max_distance = 120.0
	add_child(gull_call)
	gull_call.finished.connect(_on_gull_finished)

	gull_timer = Timer.new()
	gull_timer.name = "SeagullTimer"
	gull_timer.one_shot = true
	add_child(gull_timer)
	gull_timer.timeout.connect(_on_gull_timeout)
	_schedule_silence()

func _ship_sound(
	node_name: String,
	audio: AudioStream,
	volume: float,
	reach: float
) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.stream = audio
	player.volume_db = volume
	player.unit_size = 12.0
	player.max_distance = reach
	ship.float_visual.add_child(player)
	return player

func _process(delta: float) -> void:
	if not is_instance_valid(ship):
		return

	var speed: float = ship.measured_speed
	if speed > 0.65:
		boat_creak.volume_db = -25.0 + minf(speed / 12.0, 1.0) * 7.0
		if not boat_creak.playing:
			boat_creak.play()
	elif speed < 0.3 and boat_creak.playing:
		boat_creak.stop()

	crash_timer -= delta
	if speed > 2.8 and crash_timer <= 0.0 and not bow_crash.playing:
		var crest: float = ocean.height_at(
			ship.global_position + ship.heading * 1.5
		)
		if crest > 0.08:
			bow_crash.volume_db = -20.0 + minf(speed / 12.0, 1.0) * 6.0
			bow_crash.play()
			crash_timer = rng.randf_range(4.5, 8.0)
		else:
			crash_timer = 0.4

func _schedule_silence() -> void:
	in_burst = false
	remaining_followups = 0
	gull_timer.start(
		rng.randf_range(min_silence_seconds, max_silence_seconds)
	)

func _on_gull_timeout() -> void:
	if not is_instance_valid(ship):
		_schedule_silence()
		return

	if not in_burst:
		in_burst = true
		var chance := rng.randf()
		if chance < 0.10:
			remaining_followups = 2
		elif chance < 0.40:
			remaining_followups = 1
		else:
			remaining_followups = 0

	var up := ship.global_position.normalized()
	var forward := (-ship.global_transform.basis.z).slide(up).normalized()
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD.slide(up).normalized()
	var right := forward.cross(up).normalized()
	var angle := rng.randf_range(0.0, TAU)
	var radius := rng.randf_range(orbit_radius * 0.8, orbit_radius * 1.2)

	gull_call.global_position = (
		ship.global_position
		+ up * (flight_height + rng.randf_range(-4.0, 6.0))
		+ right * cos(angle) * radius
		+ forward * sin(angle) * radius
	)
	gull_call.pitch_scale = rng.randf_range(0.92, 1.08)
	gull_call.volume_db = -18.0 + rng.randf_range(-3.0, 3.0)
	gull_call.play()

func _on_gull_finished() -> void:
	if remaining_followups > 0:
		remaining_followups -= 1
		gull_timer.start(rng.randf_range(1.5, 3.5))
	else:
		_schedule_silence()

func _make_ocean_bed() -> AudioStreamWAV:
	# Água sem gaivotas gravadas no fundo.
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 88200

	var data := PackedByteArray()
	data.resize(176400)
	var slow := 0.0
	for i in range(88200):
		slow = lerpf(slow, rng.randf_range(-1.0, 1.0), 0.012)
		var time := float(i) / 22050.0
		var swell := 0.55 + 0.30 * sin(TAU * time / 4.0)
		data.encode_s16(
			i * 2,
			int(clampf(slow * swell * 3.0, -1.0, 1.0) * 14000.0)
		)
	wav.data = data
	return wav
