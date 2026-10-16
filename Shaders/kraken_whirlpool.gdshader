shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Redemoinho do kraken (KrakenEvent.gd): disco em anel sobre o mar com um funil afundando no
// meio, braços de espuma em espiral girando para dentro e o centro escuro. A borda some no mar.
// UV.x = ângulo (0..1), UV.y = raio relativo (0 centro .. 1 borda).

uniform float strength = 0.0;      // 0..1 (abre e fecha o redemoinho)
uniform float funnel_depth = 7.0;
uniform float spin_speed = 1.6;
uniform vec3 deep_color : source_color = vec3(0.02, 0.05, 0.1);
uniform vec3 water_color : source_color = vec3(0.05, 0.3, 0.42);
uniform vec3 swirl_foam_color : source_color = vec3(0.88, 0.95, 0.96);
uniform float night = 0.0;

#include "res://Shaders/ocean_waves.gdshaderinc"

varying float v_r;

void vertex() {
	float r = UV.y;
	v_r = r;
	// Cola na superfície do mar (mesma conta das ondas, senão as vagas cobrem o disco) e
	// afunda o funil a partir dela, mais perto do centro (perfil quadrático).
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 p = normalize(wp) * planet_radius;
	float h;
	vec3 disp;
	vec3 grad;
	float crest;
	float glow_r;
	ocean_eval(p, -1.0, h, disp, grad, crest, glow_r);
	float fade = patch_radius > 0.0 ? 1.0 - smoothstep(patch_radius * 0.5, patch_radius * 0.88, distance(p, patch_center)) : 0.0;
	vec3 n = normalize(p);
	// O funil já vem do mar (whirl_depth no ocean_eval); o disco só fica por cima dele.
	wp = n * (planet_radius + h + 0.25) + disp * fade;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
}

float wh(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float wnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(wh(i), wh(i + vec2(1, 0)), f.x), mix(wh(i + vec2(0, 1)), wh(i + vec2(1, 1)), f.x), f.y);
}

// Referência: o vórtice do Black Hole Fishing (References/Whirlpool Ref.mp4). Em vez de faixas,
// MUITOS traços finos (pinceladas creme e azuladas) seguindo as linhas de fluxo da espiral,
// mais apertados e curtos perto do centro; a água escurece para o miolo (profundidade do funil)
// e no meio um buraco preto com um anel branco largo e suave.
// Em coordenadas log-polares (u = log r, v = ângulo) a espiral logarítmica vira reta: os traços
// são ruído esticado ao longo dela. Giro rígido (não enrola com o tempo).
float streaks(vec2 flow, float lanes, float seed) {
	// Pistas finas ao longo da espiral: cada pista (floor de flow.x) tem pinceladas curtas de
	// comprimento e posição sorteados; a espessura é uma fração pequena da pista.
	float lane = floor(flow.x * lanes);
	float across = fract(flow.x * lanes);
	float seg_len = 0.35 + wh(vec2(lane, seed)) * 0.9;
	float pos = flow.y / seg_len + wh(vec2(lane, seed + 1.0)) * 10.0;
	float seg = floor(pos);
	float inside = fract(pos);
	float on = step(0.55, wh(vec2(lane, seg + seed * 3.0)));
	float width = 0.12 + wh(vec2(seg, lane + seed)) * 0.18;
	float thin = 1.0 - smoothstep(width * 0.4, width, abs(across - 0.5) * 2.0);
	float taper = smoothstep(0.0, 0.25, inside) * (1.0 - smoothstep(0.6, 1.0, inside));
	return on * thin * taper;
}

void fragment() {
	float r = max(v_r, 0.001);
	float a = UV.x * 6.2831853;
	float t = TIME * spin_speed;
	float u = log(r);
	float k = 1.35;                       // abertura da espiral
	float v = a + t * 1.2;
	// Coordenadas da espiral: através (w) e ao longo (s) das linhas de fluxo.
	float w = v - k * u;
	float along = v + u / k;
	vec2 flow = vec2(w, along * 6.0);
	// Água: escurece para o miolo.
	vec3 col = mix(deep_color, water_color, smoothstep(0.05, 0.85, r));
	float s1 = streaks(flow, 70.0, 3.1);
	float s2 = streaks(flow * vec2(1.0, 1.3) + vec2(0.37, 0.0), 110.0, 8.7);
	// Mais traços perto do centro (e somem na beirada do redemoinho).
	float dens = smoothstep(0.95, 0.3, r) * smoothstep(0.06, 0.16, r);
	float cream = s1 * dens;
	float blue = s2 * dens * (1.0 - s1);
	col = mix(col, swirl_foam_color, cream * 0.85);
	col = mix(col, vec3(0.5, 0.72, 0.78), blue * 0.6);
	// Buraco preto com anel branco largo e suave.
	float hole = 1.0 - smoothstep(0.045, 0.06, r);
	float ring = exp(-pow((r - 0.075) / 0.022, 2.0));
	col = mix(col, vec3(0.97), ring * 0.9);
	col = mix(col, vec3(0.0), hole);
	col *= mix(1.0, 0.5, night);
	float edge = 1.0 - smoothstep(0.75, 1.0, r);
	float body = (1.0 - smoothstep(0.1, 0.7, r)) * 0.75 + 0.15;
	ALBEDO = col;
	ALPHA = clamp((body + cream * 0.7 + blue * 0.4) * edge * strength + (ring + hole) * strength, 0.0, 1.0);
}
