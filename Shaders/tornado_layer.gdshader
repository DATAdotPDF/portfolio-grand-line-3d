shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque, unshaded, fog_disabled;

// Camada do tornado (Cyclone.gd): cone oco invertido, várias cascas concêntricas girando em
// velocidades/sentidos diferentes, cada uma com ruído rolando em espiral (UV panning + twist),
// corte em limiar (recorte "de papel", toon) e fresnel nas bordas. Guia do Pedro: técnica de
// cascas do Wind Waker/Genshin. O eixo balança com a mesma conta de Cyclone.axis_offset().

uniform vec4 wind_color : source_color = vec4(0.85, 0.9, 0.95, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.35, 0.4, 0.45, 1.0);
uniform sampler2D noise_texture : repeat_enable, filter_linear_mipmap;
uniform vec2 tiling = vec2(3.0, 2.0);          // x inteiro = sem costura em volta
uniform vec2 scroll_speed = vec2(0.8, -0.4);   // giro em volta + subida
uniform float twist_strength : hint_range(0.0, 5.0) = 1.8;
uniform float cutoff_threshold : hint_range(0.0, 1.0) = 0.42;
uniform float edge_softness : hint_range(0.0, 0.5) = 0.08;
uniform float scissor = 1.0;                   // 1 = recorte duro (opaco), 0 = translúcido
uniform float opacity = 1.0;
uniform float contrast = 2.4;
// Forma (iguais às do Cyclone.gd, para a física seguir o desenho).
uniform float height = 95.0;
uniform float sway_amount = 3.2;
uniform float sway_time = 0.0;
uniform float s_curve = 9.0;
uniform float grow = 1.0;
uniform float night = 0.0;
uniform float flash = 0.0;

varying float h;

vec2 sway(float k) {
	float amp = sway_amount * pow(k, 1.3) * (sin(sway_time * 1.6 - k * 5.0) * 0.5 + 0.5);
	float dir = sway_time * 0.8 - k * 7.0;
	float s = s_curve * sin(k * 3.14159 * 1.25) * (1.0 - 0.35 * k);
	float s_dir = sway_time * 0.12;
	return vec2(cos(dir), sin(dir)) * amp + vec2(cos(s_dir), sin(s_dir)) * s;
}

void vertex() {
	// A malha já vem com a base em y = 0 (Cyclone._cone_mesh).
	h = clamp(VERTEX.y / height, 0.0, 1.0);
	VERTEX.xz = VERTEX.xz * grow + sway(h);
	VERTEX.y *= grow;
}

void fragment() {
	// Espiral: torce com a altura e rola com o tempo.
	vec2 uv = vec2(UV.x, h) * tiling;
	uv.x += h * twist_strength;
	uv += scroll_speed * TIME;
	// Ondulação lenta das faixas (warp com o próprio ruído, bem esticado).
	uv.x += (texture(noise_texture, uv * vec2(0.25, 0.08) + vec2(0.0, TIME * 0.05)).r - 0.5) * 0.6;
	float n = texture(noise_texture, uv).r;
	// Segunda leitura mais fina e mais rápida quebra a repetição.
	n = mix(n, texture(noise_texture, uv * vec2(1.7, 2.3) + vec2(TIME * scroll_speed.x * 0.5, 0.0)).r, 0.3);
	// Contraste: o ruído é suave demais para dar faixas recortadas.
	n = clamp((n - 0.5) * contrast + 0.5, 0.0, 1.0);
	// Toca o mar (fade curtinho embaixo) e some na boca, onde entram as nuvens.
	float vertical_fade = smoothstep(0.0, 0.03, h) * (1.0 - smoothstep(0.85, 1.0, h));
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.5);
	float mask = smoothstep(cutoff_threshold - edge_softness, cutoff_threshold + edge_softness, n) * vertical_fade;
	// Toon: duas cores em degrau suave + borda clara.
	float tone = smoothstep(cutoff_threshold + 0.12, cutoff_threshold + 0.2, n + fresnel * 0.25);
	vec3 col = mix(shadow_color.rgb, wind_color.rgb, tone);
	col += vec3(0.85, 0.95, 1.0) * flash * (1.0 - smoothstep(0.0, 0.04, abs(n - 0.5)));
	ALBEDO = col * mix(1.0, 0.36, night);
	float a = mask * clamp(wind_color.a + fresnel * 0.3, 0.0, 1.0) * opacity;
	ALPHA = mix(a, step(0.5, mask) * opacity, scissor);
	ALPHA_SCISSOR_THRESHOLD = scissor > 0.5 ? 0.5 : 0.01;
}
