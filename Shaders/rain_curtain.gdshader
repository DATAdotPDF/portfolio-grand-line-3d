shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled, skip_vertex_transform;

// Cortina de chuva da tempestade vista de longe (StormCell.gd): alguns lençóis verticais que
// giram em volta do próprio eixo para encarar a câmera (sem borda dura de cilindro). Alfa
// some nas laterais (gaussiana), no topo (base da nuvem) e no mar; estrias descendo.
// UV.x = largura (0..1), UV.y = 0 topo .. 1 mar. INSTANCE_CUSTOM não é usado (Compatibility).

uniform vec3 shaft_color : source_color = vec3(0.32, 0.36, 0.4);
uniform float density = 0.8;
uniform float lean = 0.0;           // desloca a base a favor do vento (m)
uniform vec3 lean_dir = vec3(1.0, 0.0, 0.0);
uniform float near_fade = 80.0;
uniform float night = 0.0;
uniform float flash = 0.0;

varying float seed;
varying float cam_dist;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	seed = float(INSTANCE_ID) * 3.17;
	// Eixo vertical = Y da instância; largura = X; o lençol vira para a câmera em volta do eixo.
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 up_axis = MODEL_MATRIX[1].xyz;
	float height = length(up_axis);
	vec3 up = up_axis / height;
	float width = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - center;
	vec3 side = normalize(cross(up, to_cam));
	float down = UV.y;                       // 0 topo, 1 mar
	vec3 world = center + side * (UV.x - 0.5) * width * mix(0.85, 1.15, down) + up * (1.0 - down) * height;
	world += lean_dir * lean * down * down;
	cam_dist = distance(world, CAMERA_POSITION_WORLD);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	float x = UV.x - 0.5;
	float sides = exp(-x * x / 0.045);
	vec2 q = vec2(UV.x * 26.0 + seed, UV.y * 2.5 - TIME * 0.9);
	float streak = noise(q) * 0.6 + noise(q * vec2(2.2, 1.5) + 7.0) * 0.4;
	float clumps = noise(vec2(UV.x * 4.0 + seed, UV.y * 0.8 + TIME * 0.05));
	float alpha = density * 0.55 * sides * (0.55 + 0.45 * streak) * (0.5 + 0.6 * clumps);
	// Só some no topo (base da nuvem); embaixo vai até o fundo e o mar cobre (antes sumia antes
	// de tocar a água e a cortina parecia flutuar).
	alpha *= smoothstep(0.0, 0.18, UV.y);
	alpha *= smoothstep(near_fade * 0.6, near_fade * 1.5, cam_dist);
	vec3 col = shaft_color * mix(1.0, 0.4, night) + vec3(0.35, 0.63, 0.96) * flash * 0.25;
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.8);
}
