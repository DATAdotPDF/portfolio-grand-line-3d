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
uniform float star_density : hint_range(50.0, 600.0) = 280.0;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
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

	// Estrelas (só à noite e longe do horizonte).
	float night_visibility = (1.0 - day) * smoothstep(0.05, 0.35, dir.y);
	if (night_visibility > 0.01) {
		float star = hash3(floor(EYEDIR * star_density));
		if (star > 0.985) {
			float twinkle = sin(TIME * 3.2 + star * 45.0) * 0.5 + 0.5;
			color += vec3(pow((star - 0.985) / 0.015, 2.0) * twinkle * night_visibility * 1.8);
		}
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
			float horizon = smoothstep(0.02, 0.2, dir.y);
			color = mix(color, cloud_col, cover * horizon * cloud_fade);
		}
	}	COLOR = color;
}
