extends CanvasLayer

## Flare do sol na tela (Shaders/sun_flare.gdshader): brilho + fantasmas na linha sol → centro.
## Posiciona o efeito onde o sol aparece na câmera e apaga à noite, com o sol atrás da câmera ou
## fora da tela, na tempestade, no mapa e quando algo sólido (ilha, barco) fica entre a câmera e
## o sol. As nuvens em cartões (SkyClouds) são brancas como o sol, então são testadas aqui pelas
## posições dos tufos; as nuvens do céu e as velas, pelo shader, olhando os pixels do disco do sol.

const SHADER := preload("res://Shaders/sun_flare.gdshader")
## Ângulo (rad) do disco cheio do sol no céu: acos(1 - sun_disk_size * 0.5) do radial_sky.
const SUN_ANGLE := 0.0134

var world: Node3D
var rect: ColorRect
var material: ShaderMaterial
var blocked := 0.0  # oclusão física suavizada (0 livre, 1 coberto)
var cover := 0.0    # última leitura (ilha/casco ou nuvens em cartões)
var check_timer := 0.0

func _ready() -> void:
	layer = 4  # acima do 3D, abaixo do véu de chuva (5) e do HUD (10)
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	material.shader = SHADER
	rect.material = material
	add_child(rect)

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if world == null or camera == null or world.get("clock") == null:
		return
	var to_sun: Vector3 = world.clock.sun_direction
	var eye := camera.global_position
	var sun_point := eye + to_sun * 2000.0
	var up := eye.normalized()
	var strength := 1.0
	strength *= smoothstep(0.0, 0.15, to_sun.dot(up))            # sol acima do horizonte
	strength *= 1.0 - clampf(float(world.get("storm_gloom")), 0.0, 1.0)
	strength *= 1.0 - smoothstep(0.1, 0.4, float(world.get("space_view")))
	if camera.is_position_behind(sun_point):
		strength = 0.0
	if strength <= 0.001:
		rect.visible = false
		return
	var size := get_viewport().get_visible_rect().size
	var uv := camera.unproject_position(sun_point) / size
	# Sol saindo da tela: apaga suave em vez de cortar.
	var edge := minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y))
	strength *= smoothstep(-0.01, 0.05, edge)
	# Raio físico (casco, costa) e nuvens em cartões na frente do sol: suavizado, sem piscar.
	# ~12 vezes por segundo basta (as nuvens andam devagar) e poupa o celular/web.
	check_timer -= delta
	if check_timer <= 0.0:
		check_timer = 0.08
		cover = 1.0 if _ray_blocked(eye, to_sun) else _cloud_cover(eye, to_sun)
	blocked = move_toward(blocked, cover, delta * 4.0)
	strength *= 1.0 - blocked
	rect.visible = strength > 0.001
	if not rect.visible:
		return
	material.set_shader_parameter("sun_uv", uv)
	material.set_shader_parameter("aspect", size.x / size.y)
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("sun_radius", tan(SUN_ANGLE) / (2.0 * tan(deg_to_rad(camera.fov) * 0.5)))
	var sun_light := world.get("sun") as DirectionalLight3D
	if sun_light != null:
		material.set_shader_parameter("tint", sun_light.light_color)

func _ray_blocked(eye: Vector3, to_sun: Vector3) -> bool:
	var space := get_viewport().world_3d.direct_space_state if get_viewport().world_3d else null
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, eye + to_sun * 900.0)
	query.collide_with_areas = false
	query.hit_from_inside = false
	return not space.intersect_ray(query).is_empty()

## Quanto os tufos das nuvens em cartões cobrem o sol (0..1). Cada cartão é um quadrado de lado
## s virado para a câmera; o tufo cheio ocupa ~o miolo (raio ~0,25 s) e some até ~0,42 s.
func _cloud_cover(eye: Vector3, to_sun: Vector3) -> float:
	var clouds := world.get_node_or_null("SkyClouds") as MultiMeshInstance3D
	if clouds == null or not clouds.visible or clouds.multimesh == null:
		return 0.0
	var mm := clouds.multimesh
	var cover := 0.0
	for i in mm.visible_instance_count:
		var xf := mm.get_instance_transform(i)
		var rel := xf.origin - eye
		var t := rel.dot(to_sun)
		if t <= 0.0:
			continue
		var s := xf.basis.x.length()
		var d := (rel - to_sun * t).length() / s
		if d > 0.45:
			continue
		var alpha := mm.get_instance_color(i).a
		cover = maxf(cover, alpha * (1.0 - smoothstep(0.24, 0.42, d)))
		if cover >= 0.99:
			break
	return cover
