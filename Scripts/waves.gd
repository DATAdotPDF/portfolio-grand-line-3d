@tool
extends Node

const Scale = preload("res://Scripts/WorldScale.gd")
const RADIUS := Scale.OCEAN_RADIUS
const AMPLITUDES := Vector3(0.48, 0.22, 0.09)
const FREQUENCIES := Vector3(TAU / 22.0, TAU / 11.0, TAU / 5.5)
const RATES := Vector3(0.92, 1.25, 1.7)
var directions := PackedVector3Array([Vector3(1,0.24,0.6).normalized(), Vector3(-0.35,0.55,1).normalized(), Vector3(0.6,1,-0.45).normalized()])
const PATCH_COUNT := 12
var centers := PackedVector3Array()
var patch_dirs := PackedVector3Array()
var patch_data := PackedVector4Array()
var patch_phase := PackedFloat32Array()
var phase := Vector3.ZERO

func _init() -> void:
	for i in range(PATCH_COUNT):
		var y := 1.0-2.0*(i+0.5)/PATCH_COUNT
		var a := i*2.39996323
		var n := Vector3(cos(a)*sqrt(1.0-y*y),y,sin(a)*sqrt(1.0-y*y))
		centers.append(n)
		patch_dirs.append(Vector3(sin(a+0.7),0.35,cos(a+0.7)).slide(n).normalized())
		var wave_number := TAU/(18.0+float(i%4)*3.0)
		# Deep-water dispersion: phase rate in radians per second.
		patch_data.append(Vector4(0.46,wave_number,sqrt(9.8*wave_number),0.55/(wave_number*0.46)))
		patch_phase.append(fposmod(i*1.73,TAU))
var materials: Array[ShaderMaterial] = []
var wake: Array[Vector4] = []
var ripples: Array[Vector4] = []

func _ready() -> void:
	process_physics_priority = -20

func register_material(material: ShaderMaterial) -> void:
	materials.append(material)
	material.set_shader_parameter("ocean_radius", RADIUS)
	material.set_shader_parameter("wave_dirs", directions)
	material.set_shader_parameter("patch_centers", centers)
	material.set_shader_parameter("patch_dirs", patch_dirs)
	material.set_shader_parameter("patch_data", patch_data)
	material.set_shader_parameter("patch_phase", patch_phase)
	material.set_shader_parameter("amplitudes", AMPLITUDES)
	material.set_shader_parameter("frequencies", FREQUENCIES)
	material.set_shader_parameter("phase", phase)

func _physics_process(delta: float) -> void:
	for i in range(PATCH_COUNT):
		patch_phase[i] = fposmod(patch_phase[i]+patch_data[i].z*delta,TAU)
	for i in range(3):
		phase[i] = fposmod(phase[i] + RATES[i] * delta, TAU)
	for i in range(wake.size() - 1, -1, -1):
		wake[i].w -= delta / 7.0
		if wake[i].w <= 0.0:
			wake.remove_at(i)
	for i in range(ripples.size() - 1, -1, -1):
		ripples[i].w += delta
		if ripples[i].w > 4.0:
			ripples.remove_at(i)

func _process(_delta: float) -> void:
	var render_phase := phase - RATES * ((1.0-Engine.get_physics_interpolation_fraction())/Engine.physics_ticks_per_second)
	var render_patches := patch_phase.duplicate()
	for i in range(PATCH_COUNT):
		render_patches[i] -= patch_data[i].z*((1.0-Engine.get_physics_interpolation_fraction())/Engine.physics_ticks_per_second)
	var packed_wake := PackedVector4Array(wake)
	packed_wake.resize(24)
	var packed_ripples := PackedVector4Array(ripples)
	packed_ripples.resize(20)
	for material in materials:
		material.set_shader_parameter("phase", render_phase)
		material.set_shader_parameter("patch_phase", render_patches)
		material.set_shader_parameter("wake_points", packed_wake)
		material.set_shader_parameter("ripple_points", packed_ripples)

		material.set_shader_parameter("ripple_count", ripples.size())
		material.set_shader_parameter("wake_count", wake.size())

func field_at(source: Vector3) -> Vector4:
	var q := source.normalized()*RADIUS
	var n := q/RADIUS
	var horizontal := Vector3.ZERO
	var height := 0.0
	var weights := 0.0
	for i in range(PATCH_COUNT):
		var weight := smoothstep(0.22,0.82,n.dot(centers[i]))
		if weight<=0.0: continue
		var data := patch_data[i]
		# Use the fixed patch direction for phase, not dot(q, its local tangent).
		var theta := q.dot(patch_dirs[i])*data.y-patch_phase[i]+phase_warp(q)
		var tangent := patch_dirs[i].slide(n).normalized()
		horizontal += tangent*(weight*data.w*data.x*cos(theta))
		height += weight*data.x*sin(theta)
		weights += weight
	var divisor := maxf(weights,0.001)
	horizontal /= divisor
	return Vector4(horizontal.x,horizontal.y,horizontal.z,height/divisor)

func ripple_height_at(point: Vector3) -> float:
	var result := 0.0
	for ripple in ripples:
		var d := point.distance_to(Vector3(ripple.x,ripple.y,ripple.z))
		var x := d-ripple.w*2.4
		result += 0.12*cos(x*4.0)*exp(-x*x/1.44)*(1.0-ripple.w/4.0)*smoothstep(0.0,0.15,ripple.w)
	return result

func displaced_at(source: Vector3) -> Vector3:
	var q := source.normalized()*RADIUS
	var field := field_at(q)
	var direction := (q+Vector3(field.x,field.y,field.z)).normalized()
	return direction*(RADIUS+field.w+ripple_height_at(direction*RADIUS))

func height_at(position: Vector3) -> float:
	var target := position.normalized()*RADIUS
	var source := target
	# Invert horizontal motion so buoyancy samples the rendered surface at world position.
	for iteration in range(3):
		var field := field_at(source)
		source = (target-Vector3(field.x,field.y,field.z)).normalized()*RADIUS
	return field_at(source).w+ripple_height_at(target)

func surface_at(position: Vector3) -> Vector3:
	return position.normalized() * (RADIUS + height_at(position))

func add_wake(position: Vector3) -> void:
	var point := position.normalized() * RADIUS
	wake.append(Vector4(point.x, point.y, point.z, 1.0))
	if wake.size() > 24:
		wake.pop_front()

func touch(position: Vector3) -> void:
	var point := position.normalized() * RADIUS
	ripples.append(Vector4(point.x, point.y, point.z, 0.01))
	if ripples.size() > 20:
		ripples.pop_front()

func phase_warp(q: Vector3) -> float:
	return 0.28*sin(q.dot(Vector3(0.047,0.061,-0.033))+sin(q.dot(Vector3(-0.019,0.038,0.057))))
