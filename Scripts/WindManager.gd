extends Node

## Vento global (estilo Wind Waker). O eixo vem de Config/world_layout.tres e é o
## mesmo que orienta as ondas; aqui só se acrescentam as rajadas ao longo do tempo.
## Todos os consumidores (vela, física do barco, fitas, partículas) usam wind_at().

signal gust_changed(multiplier: float)

const Scale = preload("res://Scripts/WorldScale.gd")

@export var gust_amplitude := 0.22
@export var gust_period := 11.0

var gust := 1.0
var elapsed := 0.0
var noise := FastNoiseLite.new()

func _ready() -> void:
	noise.seed = 4101
	noise.frequency = 1.0

func _process(delta: float) -> void:
	elapsed += delta
	var previous := gust
	gust = 1.0 + gust_amplitude * noise.get_noise_1d(elapsed / gust_period)
	if absf(gust - previous) > 0.01:
		gust_changed.emit(gust)

## Vetor tangente do vento no ponto; o comprimento é a intensidade local (0..~1.2).
func wind_at(point: Vector3) -> Vector3:
	return Scale.wind_at(point) * gust

func axis() -> Vector3:
	return Scale.wind_axis()
