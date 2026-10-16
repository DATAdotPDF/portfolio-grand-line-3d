shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, fog_disabled;

// Funil do ciclone (Cyclone.gd) em partes, como o Pedro descreveu a partir do estudo do Thiago
// Muniz (References/Tornado Thiago). Todas as partes tocam a base do tornado:
// - layer 0 DENSA: casca de fora, malva escuro, lenta, com tracinhos e falhas (deixa ver a de baixo);
// - layer 1 MEIO: mais clara e rápida, um pouco mais alta que a densa, com labaredas brancas;
// - layer 2 INTERNA: tom médio, a mais de dentro;
// - layer 3 FITA: as duas fitas de vento que sobem em espiral por fora (malha própria).
// O eixo serpenteia em "S" + uma onda helicoidal (a mesma conta roda em Cyclone.axis_offset()).

uniform int layer = 0;
uniform float height = 95.0;
uniform float sway_amount = 3.2;
uniform float sway_time = 0.0;      // relógio do próprio ciclone (bate com a CPU)
uniform float s_curve = 9.0;        // curva em "S" do eixo (bate com Cyclone.axis_offset)
uniform float breath = 1.0;         // ciclo de ~30 s (a boca abre e fecha)
uniform float spin = 0.9;           // velocidade das faixas em volta do eixo
uniform float twist = 5.0;          // torção das labaredas da base ao topo
uniform float rise = 0.35;          // faixas subindo
uniform float opacity = 0.9;
uniform vec3 light_color : source_color = vec3(0.45, 0.38, 0.4);
uniform vec3 dark_color : source_color = vec3(0.25, 0.2, 0.22);
uniform vec3 streak_color : source_color = vec3(0.16, 0.13, 0.15);
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform float night = 0.0;
uniform float grow = 1.0;           // 0..1 aparece/some (chegada com mini ciclone)
uniform float flash = 0.0;          // raio dentro do funil
uniform vec3 flash_color : source_color = vec3(0.85, 0.95, 1.0);
// Técnica do estudo do Wind Waker (References/WW_Study/notes/tornado.md): cada casca rola a sua
// textura em velocidade/direção próprias; o desencontro entre as cascas é o que dá volume.
// Texturas nossas (grátis, tutorial "GODOT 3D VFX - Tornado Effect" de Le Lu).
uniform float cutout = 0.0;
uniform sampler2D pattern_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D distort_tex : repeat_enable, filter_linear_mipmap;
uniform float around = 3.0;         // repetições da textura em volta (inteiro = sem costura)
uniform float up_repeat = 1.5;      // repetições da base ao topo
uniform float tex_mix = 0.7;        // quanto a textura rolando entra no desenho

varying vec3 local_pos;

vec2 sway(float h) {
	float amp = sway_amount * pow(h, 1.3) * (sin(sway_time * 1.6 - h * 5.0) * 0.5 + 0.5);
	float dir = sway_time * 0.8 - h * 7.0;
	float s = s_curve * sin(h * 3.14159 * 1.25) * (1.0 - 0.35 * h);
	float s_dir = sway_time * 0.12;
	return vec2(cos(dir), sin(dir)) * amp + vec2(cos(s_dir), sin(s_dir)) * s;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Ruído que se repete em volta do cilindro (u em 0..1 sem costura).
float wrap_noise(float u, float v, float cells) {
	vec2 p = vec2(u * cells, v);
	return mix(vnoise(p), vnoise(p - vec2(cells, 0.0)), u);
}

void vertex() {
	// A altura de cada casca é normalizada pela altura do funil (a do meio passa um pouco de 1).
	float h = clamp(VERTEX.y / height, 0.0, 1.1);
	local_pos = VERTEX;
	VERTEX.xz *= mix(1.0, 0.85 + 0.15 * breath, smoothstep(0.4, 1.0, h));
	VERTEX.xz = VERTEX.xz * grow + sway(min(h, 1.0));
	VERTEX.y *= grow;
}

void fragment() {
	float h = clamp(local_pos.y / height, 0.0, 1.1);
	float u = fract(UV.x);
	float t = TIME;
	vec3 col;
	float alpha;
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	if (layer == 3) {
		// FITA de vento: branca, com tracejado correndo ao longo dela e bordas macias.
		float along = UV.x * 14.0 - t * spin * 3.0;
		float dash = step(0.35, fract(along + vnoise(vec2(UV.x * 30.0, 0.0)) * 0.4));
		float across = 1.0 - smoothstep(0.3, 0.5, abs(UV.y - 0.5));
		col = mix(vec3(0.86, 0.9, 0.95), vec3(1.0), across);
		alpha = dash * across * opacity * smoothstep(0.0, 0.05, UV.x) * (1.0 - smoothstep(0.9, 1.0, UV.x));
	} else {
		float uu = fract(u - t * spin * 0.08 + h * 0.15);
		float dash = wrap_noise(uu, h * 90.0 - t * rise * 9.0, 24.0);
		// Textura rolando em espiral (gira, torce com a altura e sobe), distorcida por ruído.
		float turns = around / 6.2831853;
		vec2 tuv = vec2(u * around - t * spin * turns + h * twist * turns, h * up_repeat - t * rise);
		vec2 dd = texture(distort_tex, tuv * 0.5 + vec2(t * 0.03, -t * 0.08)).rg - 0.5;
		float tex = texture(pattern_tex, tuv + dd * 0.12).r;
		dash = mix(dash, tex, tex_mix);
		col = mix(dark_color, light_color, smoothstep(0.1, 0.9, h));
		col = mix(col, light_color * 1.12, (1.0 - facing) * 0.3);
		alpha = opacity;
		if (layer == 0) {
			// DENSA: tracinhos escuros e falhas grandes (onde aparece a camada do meio).
			col = mix(col, streak_color, step(0.74, dash));
			float gaps = mix(wrap_noise(fract(u - t * spin * 0.05), h * 4.0 - t * 0.2, 5.0), tex, tex_mix * 0.6);
			alpha *= step(0.38, gaps);
		} else if (layer == 1) {
			// MEIO: claro e rápido, com labaredas brancas recortadas.
			float warp = wrap_noise(fract(u + h * twist * 0.08 - t * spin * 0.12), h * 3.0 - t * 0.5, 3.0);
			float n = mix(wrap_noise(fract(uu + warp * 0.18), h * 7.0 - t * rise * 2.0 + warp * 1.5, 5.0), tex, tex_mix);
			float flame = step(0.55, n);
			col = mix(col, vec3(0.97, 0.97, 1.0), flame);
			alpha *= mix(0.55, 1.0, flame);
		} else {
			// INTERNA: tom médio, quase cheia, tracinhos suaves.
			col = mix(col, streak_color, step(0.8, dash) * 0.6);
		}
		float crack = 1.0 - smoothstep(0.0, 0.03, abs(wrap_noise(uu, h * 9.0, 4.0) - 0.5));
		col = mix(col, flash_color, crack * flash);
		// Toca o chão (some só nos 2% de baixo) e some na boca, onde entram as nuvens.
		alpha *= smoothstep(0.0, 0.02, h) * (1.0 - smoothstep(0.9, 1.05, h));
	}
	col *= mix(1.0, 0.34, night);
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
