shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled;

// Lado da noite do planeta, visto no mapa (globo): uma casca um pouco acima do mar que escurece o
// hemisfério oposto ao sol, com uma faixa quente no terminador (nascer/pôr do sol). Como o sol
// gira, dá para ver o planeta girando na frente dele.

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 night_color : source_color = vec3(0.02, 0.04, 0.12);
uniform vec3 dusk_color : source_color = vec3(1.0, 0.55, 0.3);
uniform float strength = 1.0;

varying vec3 v_normal;

void vertex() {
	v_normal = normalize((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz);
}

void fragment() {
	float d = dot(normalize(v_normal), normalize(sun_direction));
	float night = 1.0 - smoothstep(-0.18, 0.08, d);
	float dusk = exp(-d * d / 0.006) * 0.6;
	ALBEDO = mix(dusk_color, night_color, night);
	ALPHA = clamp(night * 0.62 + dusk * 0.35, 0.0, 0.8) * strength;
}
