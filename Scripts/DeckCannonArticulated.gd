@tool
extends Node3D

@export_group("Deck Mount")
@export var mount_yaw_degrees := 90.0:
	set(value):
		mount_yaw_degrees = value
		_update_preview()
@export var cradle_height := 0.45:
	set(value):
		cradle_height = value
		_update_preview()
@export var carriage_width := 0.95:
	set(value):
		carriage_width = maxf(value, 0.1)
		_update_preview()
@export var barrel_width := 0.95:
	set(value):
		barrel_width = maxf(value, 0.1)
		_update_preview()
@export var barrel_offset := Vector3.ZERO:
	set(value):
		barrel_offset = value
		_update_preview()

@export_group("Aim")
@export_range(-45.0, 45.0, 0.5) var preview_yaw_degrees := 0.0:
	set(value):
		preview_yaw_degrees = value
		_update_preview()
@export_range(-3.0, 30.0, 0.5) var preview_pitch_degrees := 12.0:
	set(value):
		preview_pitch_degrees = value
		_update_preview()
@export_range(0.0, 0.4, 0.01) var preview_recoil_distance := 0.0:
	set(value):
		preview_recoil_distance = value
		_update_preview()
@export var max_yaw := 45.0
@export var min_pitch := -3.0
@export var max_pitch := 30.0
@export var aim_smoothness := 7.0

@export_group("Recoil Spring")
@export var recoil_distance := 0.30
@export var carriage_recoil_distance := 0.12
@export var recoil_spring := 48.0
@export var recoil_damping := 11.0

@onready var carriage: Node3D = $CannonCarriage_Mesh
@onready var pitch_pivot: Node3D = $PitchPivot
@onready var recoil_pivot: Node3D = $PitchPivot/RecoilPivot
@onready var barrel: Node3D = $PitchPivot/RecoilPivot/CannonBarrel_Mesh
@onready var muzzle: Marker3D = $PitchPivot/RecoilPivot/MuzzlePoint
@onready var fuse_audio: AudioStreamPlayer3D = $FuseAudio
@onready var shot_audio: AudioStreamPlayer3D = $ShotAudio
@onready var fuse_light: OmniLight3D = $FuseEmber

var target_yaw := 0.0
var target_pitch := deg_to_rad(12.0)
var current_pitch := deg_to_rad(12.0)
var recoil_offset := 0.0
var recoil_velocity := 0.0
var carriage_offset := 0.0
var carriage_velocity := 0.0
var kick_angle := 0.0
var kick_velocity := 0.0
var carriage_base := Vector3.ZERO

func _ready() -> void:
	_fit_models()
	carriage_base = carriage.position
	target_yaw = deg_to_rad(preview_yaw_degrees)
	target_pitch = deg_to_rad(preview_pitch_degrees)
	current_pitch = target_pitch
	_update_preview()
	if Engine.is_editor_hint():
		set_physics_process(false)

func _bounds(model: Node3D) -> AABB:
	var total := AABB()
	var first := true
	for part in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := part as MeshInstance3D
		if mesh.mesh == null:
			continue
		var relative := model.global_transform.affine_inverse() * mesh.global_transform
		var bounds: AABB = relative * mesh.get_aabb()
		total = bounds if first else total.merge(bounds)
		first = false
	return total

func _fit_models() -> void:
	var carriage_bounds := _bounds(carriage)
	if carriage_bounds.size.x > 0.001:
		var factor := carriage_width / carriage_bounds.size.x
		carriage.scale = Vector3.ONE * factor
		carriage.rotation.y = -PI * 0.5
		var offset := Vector3(-carriage_bounds.get_center().x, -carriage_bounds.position.y, -carriage_bounds.get_center().z) * factor
		carriage.position = Basis(Vector3.UP, -PI * 0.5) * offset
		carriage_base = carriage.position
	var barrel_bounds := _bounds(barrel)
	if barrel_bounds.size.x > 0.001:
		var factor := barrel_width / barrel_bounds.size.x
		barrel.scale = Vector3.ONE * factor
		barrel.rotation.y = -PI * 0.5
		barrel.position = -barrel_bounds.get_center() * factor + barrel_offset

func _update_preview() -> void:
	if not is_inside_tree() or not is_node_ready():
		return
	_fit_models()
	rotation.y = deg_to_rad(mount_yaw_degrees + preview_yaw_degrees)
	pitch_pivot.position.y = cradle_height
	if Engine.is_editor_hint():
		pitch_pivot.rotation.x = deg_to_rad(preview_pitch_degrees)
		recoil_pivot.position.z = preview_recoil_distance
		carriage.position = carriage_base + Vector3(0.0, 0.0, preview_recoil_distance * 0.4)

func set_target_yaw(yaw: float) -> void:
	target_yaw = clampf(yaw, deg_to_rad(-max_yaw), deg_to_rad(max_yaw))

func set_target_pitch(pitch: float) -> void:
	target_pitch = clampf(pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))

func recoil() -> void:
	recoil_offset += recoil_distance
	carriage_offset += carriage_recoil_distance
	kick_angle += deg_to_rad(2.5)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var weight := 1.0 - exp(-aim_smoothness * delta)
	var desired_yaw := Quaternion(Vector3.UP, deg_to_rad(mount_yaw_degrees) + target_yaw)
	quaternion = quaternion.slerp(desired_yaw, weight).normalized()
	current_pitch = lerp_angle(current_pitch, target_pitch, weight)
	var remaining := minf(delta, 0.25)
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 120.0)
		recoil_velocity += (-recoil_offset * recoil_spring - recoil_velocity * recoil_damping) * step
		recoil_offset += recoil_velocity * step
		carriage_velocity += (-carriage_offset * recoil_spring - carriage_velocity * recoil_damping) * step
		carriage_offset += carriage_velocity * step
		kick_velocity += (-kick_angle * recoil_spring - kick_velocity * recoil_damping) * step
		kick_angle += kick_velocity * step
		remaining -= step
	pitch_pivot.rotation.x = current_pitch + kick_angle
	recoil_pivot.position.z = recoil_offset
	carriage.position = carriage_base + Vector3(0.0, 0.0, carriage_offset)
