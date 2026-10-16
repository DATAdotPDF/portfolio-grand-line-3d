shader_type sky;

// Céu do globo: gradiente dia/noite, sol pequeno, estrelas e as nuvens volumétricas
// estilizadas do pacote godot-4-stylized-sky (ray-march sobre ruído + curva de
// altura), adaptadas para um "céu local" cujo zênite é a normal radial da câmera.
// Amostras reduzidas (8 + 2 de sombra) para caber no WebGL 2 / mobile.

uniform vec3 local_up = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
// 0 = no mar, 1 = vendo o globo do espaço (mapa): nuvens e névoa somem.
uniform float space_view : hint_range(0.0, 1.0) = 0.0;
// Panorama de espaço profundo (equiretangular) usado na visão do mapa.
uniform sampler2D space_panorama : source_color, filter_linear, repeat_disable;
// Proporção da tela (largura/altura) e da imagem: o fundo preenche a tela sem esticar ('cover').
uniform float screen_aspect = 1.7778;
uniform float image_aspect = 1.7917;

group_uniforms SkyGradients;
uniform vec3 day_zenith_color : source_color = vec3(0.34, 0.6, 0.95);
uniform vec3 day_horizon_color : source_color = vec3(0.74, 0.88, 0.98);
uniform vec3 sunset_horizon_color : source_color = vec3(0.98, 0.55, 0.32);
uniform vec3 night_zenith_color : source_color = vec3(0.01, 0.02, 0.07);
uniform vec3 night_horizon_color : source_color = vec3(0.05, 0.08, 0.18);

group_uniforms Sun;
uniform float sun_disk_size : hint_range(0.00005, 0.02) = 0.00018;
uniform float sun_bloom : hint_range(0.0, 0.5) = 0.08;
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.86);

group_uniforms Clouds;
uniform sampler2D cloud_shape_sampler : filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_noise_sampler : filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_curves : repeat_disable;
uniform int clouds_samples : hint_range(4, 16) = 8;
uniform int shadow_samples : hint_range(1, 4) = 2;
uniform float clouds_density : hint_range(0.0, 1.0) = 0.46;
uniform float clouds_scale : hint_range(0.3, 2.0) = 1.1;
uniform float clouds_smoothness : hint_range(0.01, 0.1) = 0.035;
uniform float clouds_shadow_intensity : hint_range(0.1, 10.0) = 2.5;
uniform vec3 cloud_day_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_day_shade : source_color = vec3(0.55, 0.64, 0.95);
uniform vec3 cloud_night_light : source_color = vec3(0.28, 0.33, 0.5);
uniform vec3 cloud_night_shade : source_color = vec3(0.08, 0.1, 0.2);

group_uniforms Stars;
// Tempestade local (StormCell): céu fechado e cinza para quem está dentro; clarão do relâmpago.
uniform float storm_gloom : hint_range(0.0, 1.0) = 0.0;
uniform float storm_flash : hint_range(0.0, 1.0) = 0.0;
uniform float star_density : hint_range(50.0, 600.0) = 280.0;
uniform float star_brightness : hint_range(0.0, 3.0) = 1.0;
uniform float milky_way_strength : hint_range(0.0, 1.0) = 0.6;
// Eixo da Via Láctea (normal do plano da faixa, fixo no mundo).
uniform vec3 milky_way_axis = vec3(0.36, 0.48, -0.8);

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Uma camada de estrelas: a esfera vira as 6 faces de um cubo, cada face uma grade 2D; cada
// célula tem no máximo uma estrela, deslocada dentro dela mas longe da borda (não precisa olhar
// vizinhas). Ponto redondo com borda suave (não o quadrado da célula); cor de branco-azulado a
// âmbar; poucas fortes e muitas fracas. size = raio do ponto em frações da célula.
vec3 star_layer(vec3 d, float density, float chance, float size, float t) {
	vec3 a = abs(d);
	vec2 uv;
	float face;
	if (a.x >= a.y && a.x >= a.z) {
		uv = d.yz / a.x; face = d.x > 0.0 ? 1.0 : 2.0;
	} else if (a.y >= a.z) {
		uv = d.xz / a.y; face = d.y > 0.0 ? 3.0 : 4.0;
	} else {
		uv = d.xy / a.z; face = d.z > 0.0 ? 5.0 : 6.0;
	}
	vec2 g = uv * density;
	vec3 cell = vec3(floor(g), face * 131.0);
	vec3 h = hash33(cell);
	if (h.x > chance) {
		return vec3(0.0);
	}
	vec2 center = cell.xy + 0.34 + 0.32 * hash33(cell + 17.0).xy;
	float dist = length(g - center);
	float mag = pow(h.y, 5.0);
	float rad = size * (0.6 + 0.6 * mag);
	float core = 1.0 - smoothstep(rad * 0.25, rad, dist);
	float glow = (1.0 - smoothstep(0.0, 0.34, dist)) * 0.18 * mag;
	// As mais fortes ganham um brilho em cruz bem curto (estilo desenho, não foto).
	vec2 q = abs(g - center);
	float spike = (1.0 - smoothstep(0.0, 0.045, min(q.x, q.y))) * (1.0 - smoothstep(0.0, 0.32, max(q.x, q.y)));
	glow += spike * smoothstep(0.55, 0.95, mag) * 0.9;
	// Cintilação leve e lenta (cada estrela no seu ritmo), mais forte perto do horizonte.
	float twinkle = 1.0 - t * (0.5 + 0.5 * sin(TIME * (1.3 + h.z * 2.4) + h.y * 40.0));
	vec3 tint = mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.84, 0.66), h.z);
	tint = mix(vec3(1.0), tint, 0.7);
	return tint * (core * (0.3 + 1.7 * mag) + glow) * twinkle;
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

mat3 local_frame(vec3 up) {
	vec3 ref = abs(up.y) > 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	vec3 x = normalize(cross(ref, up));
	vec3 z = cross(x, up);
	return mat3(x, up, z);
}

// Ruído de valor 2D + fbm (procedural: sem texturas/mipmaps, estável no WebGL 2).
float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) {
			break;
		}
		value += vnoise(p) * amplitude;
		p = p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value;
}

// Cobertura de nuvem no plano do céu (0..1), já com borda suave.
float cloud_cover(vec2 p, int octaves) {
	float base = fbm(p * clouds_scale, octaves);
	float threshold = 1.0 - clouds_density;
	return smoothstep(threshold - clouds_smoothness * 3.0, threshold + clouds_smoothness * 3.0, base);
}
void sky() {
	vec3 up = normalize(local_up);
	mat3 frame = local_frame(up);
	// Direções no "céu local" (Y = zênite do ponto do globo onde está a câmera).
	vec3 dir = transpose(frame) * EYEDIR;
	vec3 sun = transpose(frame) * normalize(sun_direction);

	float sun_height = sun.y;
	float day = smoothstep(-0.15, 0.25, sun_height);
	float sunset = clamp((1.0 - abs(sun_height * 4.0)) * (1.0 - day * 0.6), 0.0, 1.0);
	float zenith = clamp(dir.y, 0.0, 1.0);
	vec3 day_sky = mix(day_horizon_color, day_zenith_color, pow(zenith, 0.7));
	day_sky = mix(day_sky, sunset_horizon_color, sunset * (1.0 - zenith) * 0.8);
	vec3 night_sky = mix(night_horizon_color, night_zenith_color, pow(zenith, 0.7));
	vec3 color = mix(night_sky, day_sky, day);

	// Sol pequeno + brilho suave.
	float sun_dot = max(dot(dir, sun), 0.0);
	float disk = smoothstep(1.0 - sun_disk_size, 1.0 - sun_disk_size * 0.5, sun_dot);
	color += (disk * 3.0 + pow(sun_dot, 24.0) * sun_bloom) * sun_color * day;

	// Céu noturno: estrelas redondas em 2 camadas (muitas fracas + poucas fortes), cintilação
	// leve e uma Via Láctea sutil (faixa num grande círculo fixo, com nuvens claras e uma fenda
	// escura de poeira). Tudo some com o dia e perto do horizonte.
	float night_visibility = (1.0 - smoothstep(0.05, 0.55, day)) * smoothstep(0.02, 0.3, dir.y) * (1.0 - storm_gloom);
	if (night_visibility > 0.01) {
		vec3 wd = normalize(EYEDIR);
		vec3 axis = normalize(milky_way_axis);
		float band_y = dot(wd, axis);
		float band = exp(-band_y * band_y * 28.0);
		vec3 stars = vec3(0.0);
		float tw = mix(0.35, 0.12, smoothstep(0.1, 0.6, dir.y));
		stars += star_layer(wd, star_density, 0.06 + 0.3 * band, 0.3, tw) * 0.45;
		stars += star_layer(wd, star_density * 0.45, 0.2 + 0.15 * band, 0.2, tw) * 0.8;
		stars += star_layer(vec3(wd.z, wd.x, -wd.y), star_density * 0.16, 0.22, 0.12, tw * 0.6) * 1.6;
		vec3 milky = vec3(0.0);
		if (band > 0.02 && milky_way_strength > 0.0) {
			float clouds = vnoise3(wd * 6.0) * 0.6 + vnoise3(wd * 13.0 + 3.1) * 0.3 + vnoise3(wd * 29.0) * 0.1;
			float lane = smoothstep(0.035, 0.0, abs(band_y + 0.04 * (vnoise3(wd * 9.0) - 0.5) - 0.01));
			float glow = band * smoothstep(0.25, 0.85, clouds) * (1.0 - 0.75 * lane);
			milky = mix(vec3(0.38, 0.45, 0.75), vec3(0.8, 0.7, 0.62), clouds) * glow * 0.22 * milky_way_strength;
		}
		color += (stars * star_brightness + milky) * night_visibility;
	}

	// Nuvens fofas estilizadas: plano de nuvens projetado, luz falsa amostrando
	// a cobertura deslocada na direção do sol (topo claro, base lavanda).
	float cloud_fade = 1.0 - space_view;
	if (dir.y > 0.0 && cloud_fade > 0.01) {
		float elevation = max(dir.y, 0.04);
		vec2 plane = dir.xz / elevation * 0.9 + vec2(TIME * 0.004, TIME * 0.002);
		int octaves = elevation < 0.15 ? 3 : 5;
		float cover = cloud_cover(plane, octaves);
		if (cover > 0.001) {
			vec2 to_sun = normalize(sun.xz + vec2(0.0001)) * 0.35;
			float lit_cover = cloud_cover(plane + to_sun, octaves);
			float light = clamp(1.0 - (lit_cover - cover * 0.35) * clouds_shadow_intensity * 0.45, 0.0, 1.0);
			light = (floor(light * 3.0) + smoothstep(0.35, 0.65, fract(light * 3.0))) / 3.0;
			vec3 light_col = mix(cloud_night_light, cloud_day_light, day);
			vec3 shade_col = mix(cloud_night_shade, cloud_day_shade, day);
			light_col = mix(light_col, sunset_horizon_color, sunset * 0.35);
			vec3 cloud_col = mix(shade_col, light_col, light);
			// Contra o sol: miolo da nuvem fica na sombra e a borda brilha (silver lining).
			float backlit = pow(sun_dot, 90.0) * day;
			cloud_col = mix(cloud_col, shade_col * 1.15, backlit * smoothstep(0.35, 0.9, cover) * 0.55);
			cloud_col += sun_color * backlit * (1.0 - smoothstep(0.1, 0.6, cover)) * 0.35;
			float horizon = smoothstep(0.02, 0.2, dir.y);
			// À noite as nuvens ficam um pouco mais ralas: as estrelas aparecem nas bordas.
			color = mix(color, cloud_col, cover * horizon * cloud_fade * mix(0.82, 1.0, day));
		}
	}
	float grey = dot(color, vec3(0.3, 0.5, 0.2));
	// Tempestade (Wind Waker): céu verde-acinzentado; clarão azulado (90,160,245).
	color = mix(color, vec3(grey) * vec3(0.6, 0.72, 0.66), storm_gloom * 0.85);
	color += vec3(0.35, 0.63, 0.96) * storm_flash * 0.4;
	COLOR = color;
}
