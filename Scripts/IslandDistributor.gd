@tool
extends Node3D

const Scale = preload("res://Scripts/WorldScale.gd")

@export var planet_center := Vector3.ZERO
@export var planet_radius := Scale.OCEAN_RADIUS
@export var execute_distribution := false:
	set(value):
		if value and is_inside_tree():
			distribute_islands()
		execute_distribution = false

func distribute_islands() -> void:
	if get_child_count() != 5:
		push_warning("IslandAnchors precisa ter exatamente cinco marcadores.")
		return
	var directions := [
		Vector3(0.0, 200.0, 0.0),
		Vector3(200.0, 0.0, 0.0),
		Vector3(-100.0, 0.0, 173.20508),
		Vector3(-100.0, 0.0, -173.20508),
		Vector3(0.0, -200.0, 0.0)
	]
	for i in range(5):
		var anchor := get_child(i) as Node3D
		var direction: Vector3 = directions[i]
		var normal := direction.normalized()
		var forward := Vector3.UP
		if normal.y > 0.9:
			forward = Vector3.FORWARD
		elif normal.y < -0.9:
			forward = Vector3.BACK
		anchor.global_position = planet_center + direction * (planet_radius / 200.0)
		anchor.global_basis = Basis(forward.cross(normal), normal, -forward).orthonormalized()
		anchor.set_meta("surface_normal", normal)
