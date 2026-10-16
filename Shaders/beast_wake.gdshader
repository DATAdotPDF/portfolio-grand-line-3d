shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Rastro de um colosso (Scripts/SeaBeasts.gd): fita colada nas ondas atrás do bicho. A fita é
// refeita pelo script com os pontos por onde ele passou; UV.x = idade (0 = junto do corpo .. 1 = fim),
// UV.y = lado (-1 .. 1). Abre com a idade (como o V do rastro de um barco): duas linhas de espuma nas
// bordas e água revolta no meio, sumindo com a idade. strength = velocidade relativa (mais rápido,
// mais espuma).

uniform float strength = 1.0;
uniform float scale_m = 40.0;         // largura do bicho (m): tamanho dos fiapos
uniform vec3 foam_tint : source_color = vec3(0.92, 0.98, 1.0);

#include "res://Shaders/ocean_waves.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 p = normalize(wp) * planet_radius;
	float h;
	vec3 disp;
	vec3 grad;
	float crest;
	float glow_r;
	ocean_eval(p, -1.0, h, disp, grad, crest, glow_r);
	float fade = patch_radius > 0.0 ? 1.0 - smoothstep(patch_radius * 0.5, patch_radius * 0.88, distance(p, patch_center)) : 0.0;
	wp = normalize(p) * (planet_radius + h + 0.14) + disp * fade;
	world_pos = wp;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float age = UV.x;
	float side = abs(UV.y);
	vec2 q = world_pos.xz / max(scale_m * 0.12, 1.0);
	float n = noise(q + TIME * 0.3) * 0.6 + noise(q * 2.7 - TIME * 0.5) * 0.4;
	float edge = 1.0 - smoothstep(0.0, 0.2 + 0.12 * n, abs(side - 0.8));
	// Água revolta no meio: forte logo atrás do corpo, abrindo em fiapos com a idade.
	float near_body = 1.0 - smoothstep(0.0, 0.3, age);
	float churn = (1.0 - smoothstep(0.35, 0.8, side)) * mix(smoothstep(0.35, 0.7, n), 1.0, near_body * 0.7);
	float life = (1.0 - smoothstep(0.2, 1.0, age)) * smoothstep(0.0, 0.02, age);
	float foam = (edge * (0.8 + 0.3 * n) + churn) * life * clamp(strength, 0.0, 1.5);
	ALBEDO = foam_tint;
	ALPHA = clamp(foam, 0.0, 0.92) * (1.0 - smoothstep(0.95, 1.0, side));
}
