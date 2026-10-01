@tool
class_name IslandAnchor
extends Resource

## Ponto de ancoragem de uma ilha no globo. A posição final é calculada a partir
## do raio atual do planeta, então mudar o raio não exige reposicionar nada.

@export var section := "":
	set(value):
		section = value
		emit_changed()
@export_range(-90.0, 90.0, 0.1) var lat_deg := 0.0:
	set(value):
		lat_deg = value
		emit_changed()
@export_range(-180.0, 360.0, 0.1) var lon_deg := 0.0:
	set(value):
		lon_deg = value
		emit_changed()
## Giro da ilha em torno da sua normal radial.
@export_range(-180.0, 180.0, 0.5) var rotation_offset_deg := 0.0:
	set(value):
		rotation_offset_deg = value
		emit_changed()
## Quanto da base medida (floor_offset) fica abaixo do nível médio da água.
@export_range(0.0, 5.0, 0.05) var submersion := 0.5:
	set(value):
		submersion = value
		emit_changed()
## Espaço livre entre o topo medido da ilha e a base da placa de título.
@export_range(0.0, 20.0, 0.1) var plate_clearance := 3.5:
	set(value):
		plate_clearance = value
		emit_changed()
