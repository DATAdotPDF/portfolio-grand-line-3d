extends Node3D

## Sons do barco (água no casco, vela, batidas, quedas, rangido) ficam de fora por enquanto:
## o Pedro vai providenciar os arquivos. Aqui: fundo de mar, gaivotas, a tempestade e o kraken
## (KrakenAudio). Tudo gravado (Freesound, recortes de Tools/cut_game_sfx.sh; créditos em
## Config/sfx_credits.json), nada sintetizado.

const KrakenAudioScript = preload("res://Scripts/KrakenAudio.gd")
const GULLS = preload("res://Assets/Sound/SFX/SEAGULLS OPEN SEA SFX 1.mp3")
const OCEAN_BED = preload("res://Assets/Sound/SFX/Cuts/ocean_bed_loop.ogg")
# Tempestade no litoral do Báltico (chuva + mar) e chuva forte de verão.
const RAIN_LIGHT = preload("res://Assets/Sound/SFX/Cuts/storm_rain_light_loop.ogg")
const RAIN_HEAVY = preload("res://Assets/Sound/SFX/Cuts/storm_rain_heavy_loop.ogg")
## Abaixo disto (dB) um loop para de tocar.
const SILENT_DB := -50.0

@export var min_silence_seconds := 18.0
@export var max_silence_seconds := 45.0
@export var orbit_radius := 35.0
@export var flight_height := 22.0
## Abaixo desta distância (m) da ilha mais próxima, intervalos curtos.
@export var near_island_distance := 120.0
## Acima desta distância, intervalos longos de mar aberto.
@export var open_sea_distance := 450.0

var ship: CharacterBody3D
var islands: Array[Node3D] = []
var ocean: Node
var ocean_bed: AudioStreamPlayer
var gull_call: AudioStreamPlayer3D
var gull_timer: Timer
var remaining_followups := 0
var in_burst := false
var rng := RandomNumberGenerator.new()
## Camadas da tempestade (chuva fraca e forte).
var storm_layers: Dictionary = {}
var kraken_audio: Node

func _ready() -> void:
	rng.randomize()

	ocean_bed = AudioStreamPlayer.new()
	ocean_bed.name = "OceanBed"
	ocean_bed.stream = OCEAN_BED
	ocean_bed.volume_db = -24.0
	add_child(ocean_bed)
	ocean_bed.play()

	var storm_streams := {"rain_light": RAIN_LIGHT, "rain_heavy": RAIN_HEAVY}
	for key in storm_streams:
		var layer := AudioStreamPlayer.new()
		layer.name = "Storm_" + key
		layer.stream = storm_streams[key]
		layer.volume_db = -80.0
		add_child(layer)
		storm_layers[key] = layer

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

func _process(delta: float) -> void:
	if not is_instance_valid(ship):
		return
	_update_storm(delta)
	# O kraken nasce depois do mundo: liga o som dele quando o evento existir.
	if kraken_audio == null and get_parent().get("kraken_event") != null:
		kraken_audio = KrakenAudioScript.new()
		kraken_audio.name = "KrakenAudio"
		kraken_audio.kraken = get_parent().kraken_event
		add_child(kraken_audio)

## Tempestade: chuva (com o mar do litoral) fraca e depois forte, pelo badness no barco (Weather).
## O kraken também sobe o badness (mar escuro), mas tem os próprios sons: sem chuva nele.
func _update_storm(delta: float) -> void:
	var weather: Node = get_parent().get("weather")
	if weather == null:
		return
	var b: float = weather.badness
	var kraken: Node = get_parent().get("kraken_event")
	if kraken != null and int(kraken.phase) != 0:
		b = 0.0
	var levels := {
		"rain_light": _ramp(b, 0.15, 1.4, -32.0, -15.0) if b < 2.6 else _ramp(b, 2.6, 3.6, -15.0, -23.0),
		"rain_heavy": _ramp(b, 1.6, 3.4, -32.0, -12.0),
	}
	for key in storm_layers:
		_fade(storm_layers[key], levels[key], delta, 1.5)

func _ramp(x: float, from: float, to: float, low_db: float, high_db: float) -> float:
	if x <= from:
		return -80.0
	return lerpf(low_db, high_db, clampf((x - from) / (to - from), 0.0, 1.0))

## Desliza o volume até o alvo em amplitude linear (sem estalo) e liga/desliga o loop quando
## fica audível/mudo (começa num ponto sorteado do loop para não repetir sempre igual).
func _fade(player: Node, target_db: float, delta: float, rate: float) -> void:
	var amp := move_toward(db_to_linear(player.volume_db), db_to_linear(target_db), rate * 0.25 * delta)
	player.volume_db = linear_to_db(maxf(amp, 0.0001))
	if player.volume_db > SILENT_DB:
		if not player.playing:
			player.play(rng.randf_range(0.0, 4.0))
	elif player.playing:
		player.stop()

## Perto de terra as gaivotas são frequentes; em mar aberto, raras.
func _silence_scale() -> float:
	if not is_instance_valid(ship) or islands.is_empty():
		return 1.0
	var up := ship.global_position.normalized()
	var nearest := INF
	for island in islands:
		nearest = minf(nearest, up.angle_to(island.global_position.normalized()) * ship.global_position.length())
	return lerpf(0.35, 1.7, smoothstep(near_island_distance, open_sea_distance, nearest))

func _schedule_silence() -> void:
	in_burst = false
	remaining_followups = 0
	var factor := _silence_scale()
	gull_timer.start(
		rng.randf_range(min_silence_seconds, max_silence_seconds) * factor
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
