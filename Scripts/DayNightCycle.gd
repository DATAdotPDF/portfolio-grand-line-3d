extends Node
signal time_changed(time: float)
@export var day_duration_seconds := 1800.0
@export_range(0.0,1.0) var time_of_day := 0.5
var night_factor := 0.0
var paused := false
var sun_direction := Vector3.UP

func _process(delta: float) -> void:
	if not paused:
		time_of_day = fposmod(time_of_day+delta/maxf(day_duration_seconds,1.0),1.0)
	_refresh()

func set_time(value: float, freeze := false) -> void:
	time_of_day = fposmod(value,1.0)
	paused = freeze
	_refresh()

func _refresh() -> void:
	# Noon at the reference northern hemisphere. Dawn at .25, sunset at .75.
	var angle := (time_of_day-0.5)*TAU
	sun_direction = Vector3(0.35*sin(angle),cos(angle),sin(angle)).normalized()
	night_factor = night_at(Vector3.UP)
	time_changed.emit(time_of_day)

func night_at(position: Vector3) -> float:
	return 1.0-smoothstep(-0.14,0.22,position.normalized().dot(sun_direction))
