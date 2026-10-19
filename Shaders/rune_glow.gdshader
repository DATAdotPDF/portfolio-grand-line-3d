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

// Máscara de brilho de uma cor da textura (claro e saturado, ou na faixa de matiz das runas).
float glow_mask(vec3 c) {
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
	return mask;
}

// Bicúbica (B-spline, 4 leituras bilineares): ampliada de perto, a textura bilinear dá à máscara
// um contorno em degraus (losangos dos texels); a bicúbica deixa o traço da runa liso.
vec3 sample_bicubic(vec2 uv) {
	vec2 size = vec2(textureSize(albedo_map, 0));
	vec2 p = uv * size - 0.5;
	vec2 f = fract(p);
	p -= f;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;
	vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 s0 = w0 + w1;
	vec2 s1 = w2 + w3;
	vec2 t0 = (p - 0.5 + w1 / s0) / size;
	vec2 t1 = (p + 1.5 + w3 / s1) / size;
	t0 += 0.5 / size;
	t1 += 0.5 / size;
	return (texture(albedo_map, vec2(t0.x, t0.y)).rgb * s0.x + texture(albedo_map, vec2(t1.x, t0.y)).rgb * s1.x) * s0.y
		+ (texture(albedo_map, vec2(t0.x, t1.y)).rgb * s0.x + texture(albedo_map, vec2(t1.x, t1.y)).rgb * s1.x) * s1.y;
}

void fragment() {
	if (model_y < y_band.x || model_y > y_band.y) {
		discard;
	}
	vec2 texels = UV * vec2(textureSize(albedo_map, 0));
	float lod = 0.5 * log2(max(dot(dFdx(texels), dFdx(texels)), dot(dFdy(texels), dFdy(texels))));
	// Perto (textura ampliada): bicúbica; longe, a leitura normal com mipmaps.
	vec3 c = lod < 0.5 ? sample_bicubic(UV) : texture(albedo_map, UV).rgb;
	float mask = glow_mask(c);
	// Halo fraco: a máscara num mip 2 níveis acima, uma luz em volta do traço (sem apagar o desenho).
	// Conta simples (só claridade e saturação, sem a faixa de matiz): menos código para o navegador
	// compilar (no Windows cada programa deste shader custava ~1 s).
	vec3 soft = textureLod(albedo_map, UV, max(lod, 0.0) + 2.0).rgb;
	float soft_hi = max(soft.r, max(soft.g, soft.b));
	float soft_sat = soft_hi > 0.001 ? (soft_hi - min(soft.r, min(soft.g, soft.b))) / soft_hi : 0.0;
	float halo = smoothstep(0.3, 0.6, soft_hi) * smoothstep(0.25, 0.5, soft_sat);
	float hi = max(c.r, max(c.g, c.b));
	float pulse = 0.82 + 0.18 * sin(TIME * pulse_speed + phase + UV.y * 9.0);
	vec3 glow = mix(c, tint.rgb * max(hi, 0.6), tint.a);
	vec3 halo_color = mix(soft, tint.rgb * 0.8, tint.a);
	ALBEDO = (glow * mask + halo_color * halo * 0.18) * mix(day_strength, night_strength, night) * pulse;
}
