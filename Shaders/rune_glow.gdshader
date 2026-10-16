shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

// Brilho noturno por cima dos modelos do mapa (WorldDecor.gd, material_overlay): runas, corais
// bioluminescentes, o vidro da lanterna. Os GLBs do Meshy não têm mapa de emissão: o brilho sai da
// própria textura de cor, só onde ela é clara e saturada (runas, corais, vidro); a pedra (cinza,
// escura) fica de fora. Soma por cima do material original, que continua o mesmo.
// y_band (espaço do modelo): só acende nessa faixa de altura (ex.: só o vidro da lanterna).

uniform sampler2D albedo_map : source_color, filter_linear_mipmap;
uniform float night = 0.0;          // 0 dia .. 1 noite
uniform float day_strength = 0.12;  // um fio de brilho de dia (0 = só à noite)
uniform float night_strength = 1.6;
uniform float phase = 0.0;
uniform vec2 value_range = vec2(0.5, 0.78);      // claridade da textura que acende
uniform vec2 saturation_range = vec2(0.3, 0.55); // saturação que acende
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0); // a = quanto puxa para essa cor
uniform vec2 y_band = vec2(-100000.0, 100000.0);
uniform float pulse_speed = 1.3;
// Faixa de cor das runas (graus de matiz, mín..máx; z = 0 desliga): acende também runas escuras
// (verde-água/ciano mais fechado) que a regra de "claro e saturado" deixava de fora.
uniform vec3 hue_band = vec3(150.0, 205.0, 0.0);
uniform float hue_min_value = 0.22;

varying float model_y;

void vertex() {
	model_y = VERTEX.y;
}

void fragment() {
	if (model_y < y_band.x || model_y > y_band.y) {
		discard;
	}
	vec3 c = texture(albedo_map, UV).rgb;
	float hi = max(c.r, max(c.g, c.b));
	float lo = min(c.r, min(c.g, c.b));
	float sat = hi > 0.001 ? (hi - lo) / hi : 0.0;
	float mask = smoothstep(value_range.x, value_range.y, hi) * smoothstep(saturation_range.x, saturation_range.y, sat);
	if (hue_band.z > 0.5 && hi > 0.001 && hi - lo > 0.001) {
		float d = hi - lo;
		float h;
		if (hi == c.r) {
			h = mod((c.g - c.b) / d, 6.0);
		} else if (hi == c.g) {
			h = (c.b - c.r) / d + 2.0;
		} else {
			h = (c.r - c.g) / d + 4.0;
		}
		h *= 60.0;
		float in_band = smoothstep(hue_band.x - 8.0, hue_band.x, h) * (1.0 - smoothstep(hue_band.y, hue_band.y + 8.0, h));
		mask = max(mask, in_band * smoothstep(0.3, 0.5, sat) * smoothstep(hue_min_value, hue_min_value + 0.15, hi));
	}
	float pulse = 0.82 + 0.18 * sin(TIME * pulse_speed + phase + UV.y * 9.0);
	vec3 glow = mix(c, tint.rgb * max(hi, 0.6), tint.a);
	ALBEDO = glow * mask * mix(day_strength, night_strength, night) * pulse;
}
