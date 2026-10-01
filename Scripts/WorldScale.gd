@tool
extends RefCounted

## Acesso estático à configuração do mundo (Config/world_layout.tres) e à
## matemática compartilhada por shader, física, vento e ancoragem.

const LAYOUT_PATH := "res://Config/world_layout.tres"
const GRAVITY := 9.8
const PLATE_HALF_HEIGHT := 2.0
## Componentes da ondulação, relativas à principal:
## [razão de comprimento, razão de amplitude, eixo de giro (0=u, 1=v), giro em graus, fase]
const WAVE_COMPONENTS := [
	[1.00, 1.00, 0, 0.0, 0.0],
	[0.61, 0.50, 0, 21.0, 1.7],
	[0.37, 0.26, 1, -27.0, 3.8],
	[0.21, 0.12, 0, -46.0, 5.1],
	[0.11, 0.05, 1, 58.0, 2.3],
]
const MAX_WAVES := 5
## Abaixo deste |tangente| a componente some (zonas calmas perto do eixo do vento).
const CALM_INNER := 0.12
const CALM_OUTER := 0.55

static var _layout: WorldLayout

static func layout() -> WorldLayout:
	if _layout == null:
		_layout = load(LAYOUT_PATH) as WorldLayout
		if _layout == null:
			push_error("WorldScale: não foi possível carregar " + LAYOUT_PATH)
			_layout = WorldLayout.new()
	return _layout

static func radius() -> float:
	return layout().planet_radius

static func lat_lon_normal(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()

## Basis ortonormal com Y = normal radial. Nos polos usa uma referência própria
## (sem degenerar) e mantém a orientação histórica das âncoras.
static func surface_basis(normal: Vector3, rotation_deg := 0.0) -> Basis:
	var n := normal.normalized()
	var reference := Vector3.UP
	if n.y > 0.99:
		reference = Vector3.FORWARD
	elif n.y < -0.99:
		reference = Vector3.BACK
	var x := reference.cross(n).normalized()
	var basis := Basis(x, n, x.cross(n)).orthonormalized()
	if not is_zero_approx(rotation_deg):
		basis = basis.rotated(n, deg_to_rad(rotation_deg))
	return basis

## Posição/rotação da âncora: origem no nível médio do mar, Y radial.
## A altura do modelo (floor_offset) é aplicada pelo próprio modelo, dentro da âncora.
static func anchor_transform(anchor: IslandAnchor, planet_radius: float) -> Transform3D:
	var n := lat_lon_normal(anchor.lat_deg, anchor.lon_deg)
	return Transform3D(surface_basis(n, anchor.rotation_offset_deg), n * planet_radius)

# --- Vento ---------------------------------------------------------------------

static func wind_axis() -> Vector3:
	var l := layout()
	return lat_lon_normal(l.wind_lat_deg, l.wind_lon_deg)

## Fator 0..1 que zera o vento/ondas perto do eixo (Calm Belt).
static func calm_factor(tangent_length: float) -> float:
	return smoothstep(CALM_INNER, CALM_OUTER, tangent_length)

## Vetor de vento tangente à esfera no ponto. Comprimento = intensidade local (0..1).
static func wind_at(point: Vector3) -> Vector3:
	var n := point.normalized()
	var tangent := wind_axis().slide(n)
	var length := tangent.length()
	if length < 0.0001:
		return Vector3.ZERO
	return tangent / length * layout().wind_strength * calm_factor(length)

# --- Ondas ---------------------------------------------------------------------

## Lista de componentes já em unidades do mundo. Cada item:
## {dir: Vector3, phase, k, omega, amplitude, steepness}
static func wave_components() -> Array[Dictionary]:
	var l := layout()
	var s := l.wave_scale()
	var axis := wind_axis()
	var u := axis.cross(Vector3.UP)
	if u.length_squared() < 0.01:
		u = axis.cross(Vector3.FORWARD)
	u = u.normalized()
	var v := axis.cross(u).normalized()
	var result: Array[Dictionary] = []
	var slope_sum := 0.0
	for c in WAVE_COMPONENTS:
		var wavelength: float = maxf(l.swell_wavelength * float(c[0]) * s, 0.5)
		var k := TAU / wavelength
		var amplitude: float = l.swell_amplitude * float(c[1]) * s * l.wave_strength
		var rotation_axis: Vector3 = u if int(c[2]) == 0 else v
		var direction := axis.rotated(rotation_axis, deg_to_rad(float(c[3]))).normalized()
		result.append({
			"dir": direction,
			"phase": float(c[4]),
			"k": k,
			"omega": sqrt(GRAVITY * k) * l.wave_speed,
			"amplitude": amplitude,
			"steepness": 0.0,
		})
		slope_sum += k * amplitude
	# Q uniforme com soma(Q k A) = crest_sharpness, para nunca formar laços.
	var q := minf(1.5, l.crest_sharpness / maxf(slope_sum, 0.0001))
	for item in result:
		item.steepness = q
	return result

static func max_wave_height() -> float:
	var total := 0.0
	for item in wave_components():
		total += float(item.amplitude)
	return total

## Envia os parâmetros das ondas para um ShaderMaterial do oceano.
static func push_wave_uniforms(material: ShaderMaterial) -> void:
	if material == null:
		return
	var dirs := PackedVector4Array()
	var params := PackedVector4Array()
	for item in wave_components():
		var d: Vector3 = item.dir
		dirs.append(Vector4(d.x, d.y, d.z, float(item.phase)))
		params.append(Vector4(float(item.k), float(item.omega), float(item.amplitude), float(item.steepness)))
	material.set_shader_parameter("wave_dirs", dirs)
	material.set_shader_parameter("wave_params", params)
	material.set_shader_parameter("wave_count", dirs.size())
	material.set_shader_parameter("planet_radius", radius())
	material.set_shader_parameter("wave_scale", layout().wave_scale())
