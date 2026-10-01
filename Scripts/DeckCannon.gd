extends Node3D

const CARRIAGE = preload("res://Assets/Optimized/cannon_carriage.glb")
const BARREL = preload("res://Assets/Optimized/cannon_barrel.glb")

@export_group("Mira")
@export var min_pitch := -3.0
@export var max_pitch := 30.0
@export var aim_smoothness := 7.0
@export_group("Recuo")
@export var recoil_distance := 0.30
@export var recoil_recovery_speed := 5.0

var target_pitch := deg_to_rad(12.0)
var current_pitch := deg_to_rad(12.0)
var recoil_offset := 0.0
var pitch_kick := 0.0
var carriage: Node3D
var barrel: Node3D
var pitch_pivot: Node3D
var recoil_pivot: Node3D
var muzzle: Marker3D
var fuse_audio: AudioStreamPlayer3D
var shot_audio: AudioStreamPlayer3D
var fuse_light: OmniLight3D

func _bounds(model: Node3D) -> AABB:
	var total:=AABB()
	var first:=true
	for instance in model.find_children("*","MeshInstance3D",true,false):
		var relative:Transform3D=model.global_transform.affine_inverse()*instance.global_transform
		var bounds:AABB=relative*instance.get_aabb()
		total=bounds if first else total.merge(bounds)
		first=false
	return total

func _ready() -> void:
	name="DeckCannon"
	position=Vector3(-0.40,0.204,0.40)
	rotation.y=0.0
	carriage=CARRIAGE.instantiate() as Node3D
	carriage.name="CannonCarriage_Mesh"
	add_child(carriage)
	var a:=_bounds(carriage)
	var scale_factor:=0.95/a.size.x
	carriage.scale=Vector3.ONE*scale_factor
	carriage.rotation.y=0.0
	carriage.position=Vector3(-a.get_center().x,-a.position.y,-a.get_center().z)*scale_factor
	pitch_pivot=Node3D.new()
	pitch_pivot.name="PitchPivot"
	pitch_pivot.position.y=0.29
	# The fixed cradle faces port. Only the barrel's local X pitch changes.
	pitch_pivot.rotation.y=PI*0.5
	add_child(pitch_pivot)
	recoil_pivot=Node3D.new()
	recoil_pivot.name="RecoilPivot"
	pitch_pivot.add_child(recoil_pivot)
	barrel=BARREL.instantiate() as Node3D
	barrel.name="CannonBarrel_Mesh"
	recoil_pivot.add_child(barrel)
	var b:=_bounds(barrel)
	barrel.scale=Vector3.ONE*(0.95/b.size.x)
	barrel.rotation.y=-PI*0.5
	barrel.position=-b.get_center()*barrel.scale.x
	muzzle=Marker3D.new()
	muzzle.name="MuzzlePoint"
	muzzle.position=Vector3(0,0.07,-0.53)
	muzzle.rotation.x=deg_to_rad(12.0)
	recoil_pivot.add_child(muzzle)
	fuse_audio=_sound("FUSE SFX",-3.0)
	shot_audio=_sound("CANNON SHOT SFX",-8.0)
	fuse_light=OmniLight3D.new()
	fuse_light.name="FuseEmber"
	fuse_light.position=Vector3(0,0.26,0.24)
	fuse_light.light_color=Color("ff8c24")
	fuse_light.omni_range=0.8
	fuse_light.visible=false
	add_child(fuse_light)
	var ember:=MeshInstance3D.new()
	var ball:=SphereMesh.new()
	ball.radius=0.015
	ball.height=0.03
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("ff9e28")
	material.emission_enabled=true
	material.emission=Color("ff8e20")
	ball.material=material
	ember.mesh=ball
	fuse_light.add_child(ember)
	print("MODULAR_CANNON carriage=",a," barrel=",b)

func _sound(file:String, volume:float) -> AudioStreamPlayer3D:
	var player:=AudioStreamPlayer3D.new()
	player.stream=load("res://Assets/Sound/SFX/"+file+".wav")
	player.volume_db=volume
	player.unit_size=15.0
	add_child(player)
	return player

func set_target_pitch(pitch:float) -> void:
	target_pitch=clampf(pitch,deg_to_rad(min_pitch),deg_to_rad(max_pitch))

func recoil() -> void:
	recoil_offset=recoil_distance
	pitch_kick=deg_to_rad(2.5)

func _physics_process(delta:float) -> void:
	var smoothing:=1.0-exp(-aim_smoothness*delta)
	current_pitch=lerpf(current_pitch,target_pitch,smoothing)
	recoil_offset=move_toward(recoil_offset,0.0,recoil_recovery_speed*delta*recoil_distance)
	pitch_kick=move_toward(pitch_kick,0.0,delta*0.22)
	pitch_pivot.rotation.x=current_pitch-deg_to_rad(12.0)+pitch_kick
	recoil_pivot.position.z=recoil_offset
