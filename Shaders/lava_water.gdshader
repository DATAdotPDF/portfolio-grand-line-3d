shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Água fervendo em volta do vulcão (WorldDecor.gd): disco colado nas ondas, avermelhado perto
// da costa e muito mais forte onde a lava entra no mar (hot_spots), com bolhas que crescem,
// estouram e somem. UV.x = ângulo (0..1), UV.y = raio relativo (0 centro .. 1 borda).

uniform float ring_radius = 50.0;
uniform vec4 hot_spots[4];   // xyz = ponto no mundo onde a lava encontra o mar, w = raio
uniform int hot_count = 0;
uniform float shore_heat = 0.45;
uniform vec3 boil_color : source_color = vec3(0.6, 0.07, 0.03);
uniform vec3 glow_color : source_color = vec3(1.0, 0.42, 0.08);

#include "res://Shaders/ocean_waves.gdshaderinc"

varying vec3 world_pos;
varying float v_r;

void vertex() {
	v_r = UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 p = normalize(wp) * planet_radius;
	float h;
	vec3 disp;
	vec3 grad;
	float crest;
	float glow_r;
	ocean_eval(p, -1.0, h, disp, grad, crest, glow_r);
	float fade = patch_radius > 0.0 ? 1.0 - smoothstep(patch_radius * 0.5, patch_radius * 0.88, distance(p, patch_center)) : 0.0;
	wp = normalize(p) * (planet_radius + h + 0.12) + disp * fade;
	world_pos = wp;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
}

float bh(vec2 p) {
	return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453);
}

// Bolhas: uma por célula, nascendo em hora sorteada; o anel cresce e estoura.
float bubbles(vec2 p, float rate) {
	vec2 id = floor(p);
	vec2 f = fract(p);
	float seed = bh(id);
	float life = fract(TIME * rate + seed * 7.0);
	vec2 c = vec2(0.25 + 0.5 * bh(id + 3.1), 0.25 + 0.5 * bh(id + 8.7));
	float r = mix(0.05, 0.32, life) * (0.6 + 0.4 * seed);
	float d = distance(f, c);
	float rim = 1.0 - smoothstep(0.0, 0.06, abs(d - r));
	float fill = (1.0 - smoothstep(r - 0.04, r, d)) * 0.35;
	return (rim + fill) * (1.0 - smoothstep(0.75, 1.0, life)) * step(0.35, seed);
}

void fragment() {
	float heat = shore_heat * (1.0 - smoothstep(0.45, 0.95, v_r));
	for (int i = 0; i < hot_count; i++) {
		heat += 1.0 - smoothstep(0.0, hot_spots[i].w, distance(world_pos, hot_spots[i].xyz));
	}
	heat = clamp(heat, 0.0, 1.0);
	vec2 q = vec2(UV.x * 6.2831853 * ring_radius, v_r * ring_radius) * 0.45;
	float b = bubbles(q, 0.55) + bubbles(q * 1.7 + 4.3, 0.8) * 0.7;
	b *= smoothstep(0.08, 0.5, heat);
	vec3 col = mix(boil_color, glow_color, clamp(heat * 0.55 + b * 0.8, 0.0, 1.0));
	float edge = 1.0 - smoothstep(0.82, 1.0, v_r);
	ALBEDO = col;
	ALPHA = clamp(heat * 0.8 + b * 0.4, 0.0, 0.9) * edge;
}
