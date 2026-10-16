extends Node

## Sons do kraken (antes ele usava a chuva e os trovões da tempestade). Só observa o
## KrakenEvent (fase, tentáculos, barra de ação), sem mexer nele:
## - presságio: buzina grave sinistra em loop + uma pancada quando o aviso aparece;
## - subida: rugido da criatura e cada tentáculo rompendo a água (3D, no tentáculo);
## - redemoinho: vórtice de água + borbulhas graves, crescendo com a força do funil;
## - barra de ação: um toque a cada aperto (mais agudo conforme enche) e o arranque;
## - fim: naufrágio (madeira quebrando e afundando) ou o rugido dele indo embora.
## Gravações do Freesound (CC0/CC-BY), recortes de Tools/cut_game_sfx.sh.

const OMEN := preload("res://Assets/Sound/SFX/Cuts/kraken_omen_loop.ogg")
const BOOM := preload("res://Assets/Sound/SFX/Cuts/kraken_boom.ogg")
const ROAR := preload("res://Assets/Sound/SFX/Cuts/kraken_roar.ogg")
const ROAR_RETREAT := preload("res://Assets/Sound/SFX/Cuts/kraken_roar_retreat.ogg")
const TENTACLES: Array[AudioStream] = [preload("res://Assets/Sound/SFX/Cuts/kraken_tentacle_a.ogg"), preload("res://Assets/Sound/SFX/Cuts/kraken_tentacle_b.ogg")]
const WHIRLPOOL := preload("res://Assets/Sound/SFX/Cuts/kraken_whirlpool_loop.ogg")
const BUBBLES := preload("res://Assets/Sound/SFX/Cuts/kraken_bubbles_loop.ogg")
const TAP := preload("res://Assets/Sound/SFX/Cuts/kraken_action_tap.ogg")
const BREAKOUT := preload("res://Assets/Sound/SFX/Cuts/kraken_breakout.ogg")
const SHIPWRECK := preload("res://Assets/Sound/SFX/Cuts/kraken_shipwreck.ogg")
## Fases do KrakenEvent (Phase { IDLE, OMEN, RISE, PULL, LEAVE }).
const IDLE := 0
const OMEN_PHASE := 1
const RISE := 2
const PULL := 3
const LEAVE := 4

var kraken: Node
var omen: AudioStreamPlayer
var whirl: AudioStreamPlayer
var bubbles: AudioStreamPlayer
var last_phase := IDLE
var last_action := 0.0
var last_breakout := 0.0
var tentacles_heard: Dictionary = {}
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	omen = _loop_player("Omen", OMEN)
	whirl = _loop_player("Whirlpool", WHIRLPOOL)
	bubbles = _loop_player("Bubbles", BUBBLES)

func _loop_player(node_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = -80.0
	add_child(player)
	return player

func _process(delta: float) -> void:
	if not is_instance_valid(kraken):
		return
	var phase := int(kraken.phase)
	if phase != last_phase:
		_enter(phase)
		last_phase = phase
	var strength := float(kraken.strength)
	var omen_db := -80.0
	var whirl_db := -80.0
	var bubbles_db := -80.0
	match phase:
		OMEN_PHASE:
			omen_db = -9.0
		RISE:
			omen_db = -7.0
			whirl_db = -24.0
		PULL:
			omen_db = -16.0
			whirl_db = lerpf(-24.0, -8.0, strength)
			bubbles_db = lerpf(-30.0, -12.0, strength)
		LEAVE:
			whirl_db = -80.0 if strength < 0.05 else lerpf(-30.0, -8.0, strength)
			bubbles_db = -80.0 if strength < 0.05 else lerpf(-34.0, -12.0, strength)
	_fade(omen, omen_db, delta, 0.6)
	_fade(whirl, whirl_db, delta, 0.8)
	_fade(bubbles, bubbles_db, delta, 0.8)
	if phase == RISE or phase == PULL:
		_tentacles()
	# Barra de ação: cada aperto sobe a barra (action cresce de uma vez).
	var action := float(kraken.action)
	if action > last_action + 0.04:
		_one_shot(TAP, -8.0, 0.8 + action * 0.6)
	last_action = action
	var breakout := float(kraken.breakout)
	if breakout > 0.0 and last_breakout <= 0.0:
		_one_shot(BREAKOUT, -3.0, 1.0)
	last_breakout = breakout

func _enter(phase: int) -> void:
	match phase:
		OMEN_PHASE:
			_one_shot(BOOM, -6.0, 1.0)
		RISE:
			_one_shot(ROAR, -7.0, rng.randf_range(0.95, 1.05))
		LEAVE:
			if bool(kraken.lost):
				_one_shot(SHIPWRECK, -3.0, 1.0)
			elif not bool(kraken.aborted):
				_one_shot(ROAR_RETREAT, -5.0, 0.9)
		IDLE:
			tentacles_heard.clear()
	print("KRAKEN_AUDIO phase %d" % phase)

## Cada tentáculo, ao romper a água, solta um impacto molhado no lugar dele.
func _tentacles() -> void:
	var list: Array = kraken.tentacles
	for i in list.size():
		var t: Dictionary = list[i]
		if tentacles_heard.has(i) or float(t.rise) < 0.03:
			continue
		tentacles_heard[i] = true
		var node: Node3D = t.node
		if not is_instance_valid(node):
			continue
		var sound := AudioStreamPlayer3D.new()
		sound.stream = TENTACLES[rng.randi() % TENTACLES.size()]
		sound.volume_db = -5.0
		sound.unit_size = 40.0
		sound.max_distance = 400.0
		sound.pitch_scale = rng.randf_range(0.85, 1.1)
		add_child(sound)
		sound.global_position = node.global_position
		sound.play()
		sound.finished.connect(sound.queue_free)

func _one_shot(stream: AudioStream, volume: float, pitch: float) -> void:
	var sound := AudioStreamPlayer.new()
	sound.stream = stream
	sound.volume_db = volume
	sound.pitch_scale = pitch
	add_child(sound)
	sound.play()
	sound.finished.connect(sound.queue_free)

## Volume deslizando em amplitude linear; o loop liga quando fica audível e para quando some.
func _fade(player: AudioStreamPlayer, target_db: float, delta: float, rate: float) -> void:
	var amp := move_toward(db_to_linear(player.volume_db), db_to_linear(target_db), rate * delta)
	player.volume_db = linear_to_db(maxf(amp, 0.0001))
	if player.volume_db > -50.0:
		if not player.playing:
			player.play(rng.randf_range(0.0, 3.0))
	elif player.playing:
		player.stop()
