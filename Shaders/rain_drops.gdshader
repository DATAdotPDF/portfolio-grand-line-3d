shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, skip_vertex_transform, fog_disabled;

// Gotas de chuva das partículas (Weather/StormCell), no espírito do "Easy Particle Rain in Godot 4"
// (Watt Interactive, CC0): cada partícula é um quadro com VÁRIOS riscos finos dentro (menos
// partículas para a mesma densidade). O quadro gira só em volta do eixo "para cima" da partícula
// (= vertical do planeta naquele ponto) para ficar de frente para a câmera sem deitar.
// Cor dessaturada e esverdeada, bem transparente.

uniform vec3 rain_color : source_color = vec3(0.6, 0.66, 0.62);
uniform float opacity = 0.22;
uniform int streaks = 6;
uniform float streak_width = 0.03;
uniform float streak_length = 0.32;
uniform float night = 0.0;
// Longe da câmera os riscos viram uma cortina suave (sem "código de barras" de quadros).
uniform float soft_start = 60.0;
uniform float soft_end = 180.0;
uniform float soft_density = 0.32;
varying flat float seed;
varying float cam_distance;

float hash(float n) {
	return fract(sin(n * 78.233) * 43758.5453);
}

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 up_axis = MODEL_MATRIX[1].xyz;
	float sy = length(up_axis);
	float sx = length(MODEL_MATRIX[0].xyz);
	vec3 up = up_axis / max(sy, 0.0001);
	vec3 to_cam = CAMERA_POSITION_WORLD - center;
	vec3 right = cross(up, to_cam);
	right = length(right) > 0.0001 ? normalize(right) : normalize(MODEL_MATRIX[0].xyz);
	vec3 world = center + right * VERTEX.x * sx + up * VERTEX.y * sy;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(-normalize(to_cam), 0.0)).xyz;
	seed = float(INSTANCE_ID) * 1.618;
	cam_distance = length(to_cam);
}

void fragment() {
	float a = 0.0;
	for (int k = 0; k < 8; k++) {
		if (k >= streaks) {
			break;
		}
		float fk = float(k);
		float x = 0.08 + 0.84 * hash(seed * 3.1 + fk * 1.7);
		float len = streak_length * (0.6 + 0.8 * hash(seed + fk * 5.3));
		float y0 = hash(seed * 1.3 + fk * 9.1) * (1.0 - len);
		float t = (UV.y - y0) / len;
		if (t > 0.0 && t < 1.0) {
			// Afina nas pontas (gota esticada) e é mais forte embaixo.
			float w = streak_width * (0.5 + 0.5 * sin(t * PI));
			float core = 1.0 - smoothstep(w * 0.3, w, abs(UV.x - x));
			a = max(a, core * sin(t * PI) * (0.55 + 0.45 * t));
		}
	}
	float soft = smoothstep(soft_start, soft_end, cam_distance);
	float edges = smoothstep(0.0, 0.35, UV.x) * smoothstep(1.0, 0.65, UV.x) * smoothstep(0.0, 0.2, UV.y) * smoothstep(1.0, 0.8, UV.y);
	a = mix(a, soft_density * edges, soft);
	ALBEDO = rain_color * mix(1.0, 0.45, night);
	ALPHA = a * opacity * COLOR.a;
}
