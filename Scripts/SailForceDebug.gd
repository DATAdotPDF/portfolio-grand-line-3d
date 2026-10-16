extends MeshInstance3D

## Setas de força na vela, só para debug no editor (F3 liga/desliga; nunca entra no export).
## Mostra a conta do sloop.gd decomposta como num barco a vela de verdade:
## - azul: vento real no ponto (WindManager, já com rajada e badness);
## - branco: vento aparente (vento real − velocidade do barco);
## - rosa: lift, a parte da força da vela perpendicular ao vento aparente;
## - verde: drag, a parte ao longo do vento aparente;
## - amarelo: força resultante que o sloop usa (proa × fator da vela).

const WIND_SCALE := 6.0     # m de seta por unidade de vento
const FORCE_SCALE := 0.8    # m de seta por m/s de alvo

var ship: Node3D
var lines := ImmediateMesh.new()

func _ready() -> void:
	top_level = true
	mesh = lines
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.render_priority = 10
	material_override = material
	visible = false

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		visible = not visible

func _process(_delta: float) -> void:
	if not visible or not is_instance_valid(ship):
		return
	global_transform = Transform3D.IDENTITY
	var up: Vector3 = ship.global_position.normalized()
	var origin: Vector3 = ship.global_position + up * 5.0
	var heading: Vector3 = ship.heading
	var wind: Vector3 = ship._wind_at(ship.global_position)
	var velocity: Vector3 = heading * ship.drive_speed
	var apparent := wind * WIND_SCALE - velocity
	# Mesma conta do sloop.gd: o vento muda a velocidade alvo entre 72% e 100%.
	var alignment := heading.dot(wind.normalized()) if wind.length_squared() > 0.0001 else 0.0
	var sail_factor := lerpf(1.0, 0.72 + 0.28 * alignment, ship.wind_strength * clampf(wind.length(), 0.0, 1.0))
	var force: Vector3 = heading * ship.cruise_speed * sail_factor * FORCE_SCALE
	var along := apparent.normalized() if apparent.length_squared() > 0.0001 else heading
	var drag := along * force.dot(along)
	var lift := force - drag
	lines.clear_surfaces()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	_arrow(origin, wind * WIND_SCALE, up, Color(0.3, 0.6, 1.0))
	_arrow(origin + up * 0.3, apparent, up, Color(1, 1, 1))
	_arrow(origin, lift, up, Color(1.0, 0.35, 0.75))
	_arrow(origin, drag, up, Color(0.3, 1.0, 0.4))
	_arrow(origin - up * 0.3, force, up, Color(1.0, 0.85, 0.2))
	lines.surface_end()

func _arrow(from: Vector3, vector: Vector3, up: Vector3, color: Color) -> void:
	if vector.length() < 0.05:
		return
	var to := from + vector
	var side := vector.cross(up).normalized() * minf(0.4, vector.length() * 0.2)
	var back := -vector.normalized() * minf(0.8, vector.length() * 0.3)
	for segment in [[from, to], [to, to + back + side], [to, to + back - side]]:
		lines.surface_set_color(color)
		lines.surface_add_vertex(segment[0])
		lines.surface_set_color(color)
		lines.surface_add_vertex(segment[1])
