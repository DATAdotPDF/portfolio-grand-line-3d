shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Água em volta de um colosso que anda (Scripts/SeaBeasts.gd): disco elíptico colado nas ondas
// (a elipse vem da escala do nó: largura x comprimento do bicho). UV.x = ângulo (0..1; a frente do
// bicho, -Z, fica em 0,75), UV.y = raio relativo (0 centro .. 1 borda).
// - Toque na água (como a espuma das ilhas): faixa de espuma onde o corpo corta a água (contact) e
//   anéis saindo dela para fora, mais fortes na frente (a água sendo empurrada).
// - Espectral (colosso de ossos): o mar em volta muda de cor como em volta do vulcão, mas em verde
//   espectral (o do navio fantasma), com fiapos girando devagar.

uniform float ring_radius = 50.0;     // raio médio em metros (escala dos fiapos/anéis)
uniform float contact = 0.6;          // raio relativo da linha onde o corpo corta a água
uniform float foam_strength = 1.0;
uniform float push = 0.6;             // quanto a frente é mais forte (velocidade)
uniform float ring_speed = 0.25;      // anéis por segundo
uniform float spectral = 0.0;         // 0 = só espuma, 1 = mar espectral
uniform float night = 0.0;
uniform vec3 foam_tint : source_color = vec3(0.92, 0.98, 1.0);
uniform vec3 spectral_deep : source_color = vec3(0.04, 0.32, 0.26);
uniform vec3 spectral_glow : source_color = vec3(0.35, 1.0, 0.68);

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
	wp = normalize(p) * (planet_radius + h + 0.15) + disp * fade;
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
	float a = UV.x * 6.2831853;
	// Frente do bicho (-Z) em UV.x = 0,75 → sin(a) = -1.
	float front = clamp(-sin(a), 0.0, 1.0);
	float r = v_r;
	float outside = smoothstep(contact - 0.04, contact, r);
	// Espuma na linha de contato (borda quebrada por ruído) e anéis saindo para fora.
	vec2 q = vec2(cos(a), sin(a)) * r * ring_radius * 0.18;
	float n = noise(q + TIME * 0.4) * 0.6 + noise(q * 2.3 - TIME * 0.7) * 0.4;
	float band = 1.0 - smoothstep(0.0, 0.05 + 0.04 * n, abs(r - contact - 0.02));
	float travel = (r - contact) / max(1.0 - contact, 0.01);
	float rings = 0.0;
	for (int k = 0; k < 3; k++) {
		float life = fract(TIME * ring_speed + float(k) / 3.0);
		float d = abs(travel - life);
		rings += (1.0 - smoothstep(0.0, 0.035 + 0.03 * n, d)) * (1.0 - life);
	}
	float foam = (band * (0.75 + 0.25 * n) + rings * (0.35 + push * front) * step(0.0, travel)) * foam_strength;
	foam *= outside * (1.0 - smoothstep(0.85, 1.0, r));
	// Mar espectral: cor do bioma fantasma forte junto do corpo, sumindo até a borda, com fiapos girando.
	float swirl = noise(vec2(a * 3.0 + TIME * 0.12, r * ring_radius * 0.05 - TIME * 0.25)) * 0.6 + noise(q * 0.6 + TIME * 0.2) * 0.4;
	float tint = spectral * (1.0 - smoothstep(contact, 1.0, r)) * (0.55 + 0.45 * swirl) * outside;
	float glow = spectral * smoothstep(0.62, 0.9, swirl) * (1.0 - smoothstep(contact, 0.95, r)) * outside;
	vec3 sea = mix(spectral_deep, spectral_glow, clamp(glow * (0.6 + 0.8 * night) + tint * 0.3, 0.0, 1.0));
	vec3 col = mix(sea, foam_tint, clamp(foam, 0.0, 1.0));
	float alpha = clamp(max(foam * 0.9, tint * (0.55 + 0.25 * night) + glow * 0.5), 0.0, 0.92);
	ALBEDO = col;
	ALPHA = alpha;
}
