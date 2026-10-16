shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// Linhas de vento do tornado com a MESMA mecânica do vento do jogo (WindRibbon.gdshader, estudo
// do Wind Waker): uma fita cuja cabeça corre por um caminho e a cauda vem atrás afinando, com
// nascimento e fim em fade. Aqui o caminho é uma espiral que sobe colada no funil (mesmo perfil e
// mesma curva em "S" do Cyclone.gd/cyclone_funnel), com uma volta solta no meio do caminho.
// Malha: PlaneMesh com UV.x ao longo (cauda 0 → cabeça 1) e UV.y na largura.

uniform float age = 0.0;            // 0..1 vida da rajada
uniform float phase = 0.0;          // ângulo de partida em volta do funil
uniform float turns = 1.6;          // voltas da base ao topo
uniform float start_h = 0.05;       // altura relativa onde nasce
uniform float end_h = 0.85;         // altura relativa onde some
uniform float loop_amount = 1.0;    // a volta solta (curl) no meio do caminho
uniform float width = 0.9;
uniform float out_scale = 1.3;      // quanto fica por fora do funil
// Perfil e balanço do funil (iguais aos do Cyclone.gd).
uniform float height = 95.0;
uniform float radius_scale = 0.55;
uniform float breath = 1.0;
uniform float sway_amount = 3.2;
uniform float sway_time = 0.0;
uniform float s_curve = 9.0;
uniform float grow = 1.0;
uniform vec4 ribbon_color : source_color = vec4(0.88, 0.92, 0.97, 0.8);
uniform float night = 0.0;

varying float ribbon_opacity;

// Mesmo perfil de taça do Cyclone.gd (Catmull-Rom sobre 11 raios).
float profile_value(int i) {
	float p[11] = float[](23.8, 15.4, 10.6, 9.9, 9.5, 9.1, 9.8, 12.1, 19.6, 28.0, 51.9);
	return p[clamp(i, 0, 10)];
}

float radius_at(float h) {
	float x = clamp(h, 0.0, 1.0) * 10.0;
	int i = min(int(x), 9);
	float t = x - float(i);
	float p0 = profile_value(i - 1);
	float p1 = profile_value(i);
	float p2 = profile_value(i + 1);
	float p3 = profile_value(i + 2);
	float r = 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t);
	return r * radius_scale * (1.0 + 0.12 * (breath - 0.5) * smoothstep(0.6, 1.0, h));
}

vec2 sway(float h) {
	float amp = sway_amount * pow(h, 1.3) * (sin(sway_time * 1.6 - h * 5.0) * 0.5 + 0.5);
	float dir = sway_time * 0.8 - h * 7.0;
	float s = s_curve * sin(h * 3.14159 * 1.25) * (1.0 - 0.35 * h);
	float s_dir = sway_time * 0.12;
	return vec2(cos(dir), sin(dir)) * amp + vec2(cos(s_dir), sin(s_dir)) * s;
}

// Ponto do caminho no tempo t (0..1): espiral subindo + uma volta solta (como o loop do vento).
vec3 wind_path(float t) {
	float h = mix(start_h, end_h, t);
	float loop_window = smoothstep(0.35, 0.42, t) * (1.0 - smoothstep(0.62, 0.69, t));
	float turn = 6.2831853 * (t - 0.4) / 0.25;
	float a = phase + t * turns * 6.2831853;
	float r = radius_at(h) * out_scale + 1.2 * (1.0 - cos(turn)) * loop_window * loop_amount;
	float y = h * height + 2.0 * sin(turn) * loop_window * loop_amount;
	vec2 s = sway(h);
	return vec3(cos(a) * r + s.x, y, sin(a) * r + s.y) * vec3(grow, grow, grow);
}

void vertex() {
	// A cauda vem atrás da cabeça (mesma conta do WindRibbon: atraso de 0,23 da vida).
	float tail_age = age - (1.0 - UV.x) * 0.23;
	float t = clamp(tail_age, 0.0, 1.0);
	vec3 p = wind_path(t);
	vec3 ahead = wind_path(min(t + 0.004, 1.0)) - wind_path(max(t - 0.004, 0.0));
	vec3 tangent = normalize(ahead + vec3(0.0001));
	// Largura na direção vertical-ao-caminho (fica de lado para a câmera que olha o funil).
	vec3 outward = normalize(vec3(p.x, 0.0, p.z) + vec3(0.0001));
	vec3 side = normalize(cross(tangent, outward));
	float taper = pow(max(sin(UV.x * 3.14159265), 0.0), 0.72);
	VERTEX = p + side * (UV.y - 0.5) * width * taper;
	ribbon_opacity = step(0.0, tail_age) * taper * smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.72, 1.0, age));
}

void fragment() {
	ALBEDO = ribbon_color.rgb * mix(1.0, 0.45, night);
	ALPHA = ribbon_color.a * ribbon_opacity;
}
