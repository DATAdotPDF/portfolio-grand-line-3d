@tool
class_name WorldLayout
extends Resource

## Fonte única de verdade do mundo: raio do planeta, vento global, ondas e
## ancoragem das ilhas. Tudo o mais é derivado destes valores em runtime e no editor.

@export_group("Planeta")
## Raio do oceano em metros. Parâmetro livre: ilhas, ondas, câmera e spawn acompanham.
@export_range(150.0, 3000.0, 10.0) var planet_radius := 800.0:
	set(value):
		planet_radius = value
		emit_changed()

@export_group("Vento global")
## Ponto do globo para onde o vento converge. Ele e seu antípoda formam o "Calm Belt".
@export_range(-90.0, 90.0, 0.5) var wind_lat_deg := 38.0:
	set(value):
		wind_lat_deg = value
		emit_changed()
@export_range(-180.0, 360.0, 0.5) var wind_lon_deg := 30.0:
	set(value):
		wind_lon_deg = value
		emit_changed()
@export_range(0.0, 1.0, 0.05) var wind_strength := 1.0:
	set(value):
		wind_strength = value
		emit_changed()

@export_group("Ondas")
## Comprimento da ondulação principal no raio de referência.
@export_range(20.0, 400.0, 1.0) var swell_wavelength := 120.0:
	set(value):
		swell_wavelength = value
		emit_changed()
## Amplitude da ondulação principal no raio de referência.
@export_range(0.0, 8.0, 0.05) var swell_amplitude := 1.8:
	set(value):
		swell_amplitude = value
		emit_changed()
## Multiplicador geral de altura das ondas.
@export_range(0.0, 3.0, 0.05) var wave_strength := 1.0:
	set(value):
		wave_strength = value
		emit_changed()
## Nitidez trocoidal (Q de Gerstner). Limitada automaticamente para não formar laços.
@export_range(0.0, 1.0, 0.01) var crest_sharpness := 0.65:
	set(value):
		crest_sharpness = value
		emit_changed()
@export_range(0.1, 3.0, 0.05) var wave_speed := 1.0:
	set(value):
		wave_speed = value
		emit_changed()
## Raio em que comprimento e amplitude valem exatamente os números acima.
@export var reference_radius := 800.0:
	set(value):
		reference_radius = value
		emit_changed()
## Se ligado, ondas crescem na mesma proporção do raio do planeta.
@export var scale_waves_with_radius := true:
	set(value):
		scale_waves_with_radius = value
		emit_changed()

@export_group("Spawn da chalupa")
@export var spawn_island := 0:
	set(value):
		spawn_island = value
		emit_changed()
## Distância (m) da ilha de spawn até o barco, ao longo da superfície.
@export_range(20.0, 400.0, 1.0) var spawn_distance := 70.0:
	set(value):
		spawn_distance = value
		emit_changed()
@export_range(-180.0, 180.0, 1.0) var spawn_bearing_deg := 0.0:
	set(value):
		spawn_bearing_deg = value
		emit_changed()

@export_group("Ilhas")
@export var islands: Array[IslandAnchor] = []:
	set(value):
		for anchor in islands:
			if anchor and anchor.changed.is_connected(emit_changed):
				anchor.changed.disconnect(emit_changed)
		islands = value
		for anchor in islands:
			if anchor and not anchor.changed.is_connected(emit_changed):
				anchor.changed.connect(emit_changed)
		emit_changed()

func wave_scale() -> float:
	return planet_radius / maxf(reference_radius, 1.0) if scale_waves_with_radius else 1.0
