// ocean_waves.gdshaderinc
// Campo de ondas trocoidais (Gerstner) sobre a esfera, compartilhado pela esfera
// distante (somente fragment) e pelo patch local que acompanha o barco (vertex).
// Regras do histórico: tudo em espaço de mundo, direções = vetores contínuos do
// vento (dot product), sem UV polar, sem somas cartesianas, sem produto sin*cos.
// Os parâmetros vêm de WorldScale.push_wave_uniforms (mesma fonte da física).

#define MAX_WAVES 5
#define MAX_RIPPLES 32
#define MAX_WAKE 24

uniform float planet_radius = 800.0;
uniform float wave_scale = 1.0;
uniform vec4 wave_dirs[MAX_WAVES];   // xyz = direção 3D, w = fase
uniform vec4 wave_params[MAX_WAVES]; // x = k, y = omega, z = amplitude, w = Q
uniform int wave_count = 0;
uniform float ocean_time = 0.0;
uniform bool use_simulation_time = false;

uniform vec4 ripple_points[MAX_RIPPLES]; // xyz = centro, w = idade (s)
uniform vec4 ripple_info[MAX_RIPPLES];   // x = força, y = velocidade de frente
uniform int ripple_count = 0;
// Arrasto do mouse/dedo: polilinha (xyz, w = idade em s) que vira um sulco contínuo.
#define MAX_STROKE 24
uniform vec4 stroke_points[MAX_STROKE];
uniform int stroke_count = 0;
uniform vec4 wake_points[MAX_WAKE];
uniform int wake_count = 0;

uniform vec3 island_centers[5];
uniform float island_radii[5];

uniform vec3 boat_position;
uniform vec3 boat_forward;
uniform vec3 boat_right;
uniform bool boat_cutout_enabled = false;

// Sombras das nuvens: mesmo ruído das nuvens do céu, projetado no plano do vento.
uniform sampler2D cloud_shadow_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 cloud_axis_u = vec3(1.0, 0.0, 0.0);
uniform vec3 cloud_axis_v = vec3(0.0, 0.0, 1.0);
uniform float cloud_shadow_scale = 900.0;
uniform float cloud_shadow_strength = 0.0;

uniform vec3 patch_center;
uniform float patch_radius = 0.0;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
// Cores calibradas para o Compatibility (sem HDR): valores altos estouram em ciano.
// Paleta turquesa (referência Seagazer). Valores moderados porque o Compatibility não tem HDR.
uniform vec3 deep_ocean_color : source_color = vec3(0.0, 0.3, 0.44);
uniform vec3 shallow_ocean_color : source_color = vec3(0.03, 0.5, 0.55);
uniform vec3 crest_color : source_color = vec3(0.3, 0.7, 0.72);
uniform vec3 foam_color : source_color = vec3(0.9, 0.98, 0.98);
// Reflexo do céu por Fresnel: o brilho pálido e vítreo perto do horizonte.
uniform vec3 sky_reflection_color : source_color = vec3(0.78, 0.85, 0.96);
uniform float fresnel_power : hint_range(1.0, 8.0) = 4.0;
uniform float fresnel_amount : hint_range(0.0, 1.0) = 0.6;
// 0 = dia, 1 = noite (enviado pelo main_world). À noite a esteira brilha (bioluminescência).
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 night_glow_color : source_color = vec3(0.2, 0.95, 0.85);
uniform float toon_bands : hint_range(1.0, 8.0) = 3.0;
uniform float crest_line_amount : hint_range(0.0, 1.0) = 0.4;
uniform float shoreline_width = 0.45;
uniform float far_detail_distance = 10.0; // em comprimentos de onda

const float CALM_INNER = 0.12;
const float CALM_OUTER = 0.55;

float ocean_clock() {
	return use_simulation_time ? ocean_time : TIME;
}

float coast_factor(vec3 p) {
	float factor = 1.0;
	for (int i = 0; i < 5; i++) {
		if (island_radii[i] > 0.0) {
			float chord = distance(p, island_centers[i] * planet_radius);
			factor = min(factor, smoothstep(island_radii[i] * 0.7, island_radii[i] + 25.0 * wave_scale, chord));
		}
	}
	return mix(0.08, 1.0, factor);
}

// Sulco do arrasto: cavado no centro e cristas laterais que se afastam com a idade.
void stroke_eval(vec3 p, vec3 n, inout float h, inout vec3 grad, inout float glow) {
	// Distância à polilinha inteira (segmento mais próximo), como na esteira.
	float d = 1e6;
	float age = 0.0;
	vec3 to_p = vec3(0.0);
	for (int i = 0; i < MAX_STROKE - 1; i++) {
		if (i >= stroke_count - 1) {
			break;
		}
		vec3 a = stroke_points[i].xyz;
		vec3 seg = stroke_points[i + 1].xyz - a;
		float t = clamp(dot(p - a, seg) / max(dot(seg, seg), 0.0001), 0.0, 1.0);
		vec3 off = p - (a + seg * t);
		float dist = length(off);
		if (dist < d) {
			d = dist;
			to_p = off;
			age = mix(stroke_points[i].w, stroke_points[i + 1].w, t);
		}
	}
	if (d > 30.0) {
		return;
	}
	float life = exp(-age * 1.1) * smoothstep(0.0, 0.1, age);
	float width = 0.6 + age * 1.6;
	float k = 1.0 / (width * width * 0.35);
	float trough = -0.35 * exp(-d * d * k);
	float ring = d - width * 1.5;
	float s = 0.5 + age * 0.6;
	float ridge = 0.22 * exp(-ring * ring / s);
	h += (trough + ridge) * life;
	float dv = (-2.0 * d * k * trough - 2.0 * ring / s * ridge) * life;
	vec3 dir = d > 0.001 ? to_p / d : vec3(0.0);
	grad += (dir - n * dot(n, dir)) * dv;
	glow += ridge / 0.22 * life * 0.8;
}
// p: ponto na esfera (|p| = planet_radius). view_distance < 0 desliga o fade de LOD.
// h: altura radial; disp: deslocamento tangente; grad: gradiente tangente da altura;
// crest: compressão horizontal (> 0 nas cristas), usada para as bandas toon.
void ocean_eval(vec3 p, float view_distance, out float h, out vec3 disp, out vec3 grad, out float crest, out float ripple_glow) {
	vec3 n = normalize(p);
	float t = ocean_clock();
	float coast = coast_factor(p);
	h = 0.0;
	disp = vec3(0.0);
	grad = vec3(0.0);
	crest = 0.0;
	ripple_glow = 0.0;
	for (int i = 0; i < MAX_WAVES; i++) {
		if (i >= wave_count) {
			break;
		}
		vec3 d = wave_dirs[i].xyz;
		vec4 wp = wave_params[i];
		vec3 g = d - n * dot(n, d); // gradiente tangente de dot(p, d)
		float w = smoothstep(CALM_INNER, CALM_OUTER, length(g)) * coast;
		if (view_distance >= 0.0) {
			float wavelength = 6.2831853 / wp.x;
			w *= 1.0 - smoothstep(wavelength * far_detail_distance * 0.4, wavelength * far_detail_distance, view_distance);
		}
		// Grupos de ondas: a amplitude varia devagar pelo mar (umas mais altas e íngremes, outras mais 'gordinhas').
		vec3 d2 = wave_dirs[(i + 2) % max(wave_count, 1)].xyz;
		float group = 0.55 + 0.75 * (0.5 + 0.5 * sin(wp.x * 0.19 * dot(p, d2) + wp.x * 0.07 * dot(p, d) - wp.y * 0.05 * t + wave_dirs[i].w * 2.7));
		w *= group;
		float phi = wp.x * dot(p, d) - wp.y * t + wave_dirs[i].w;
		float s = sin(phi);
		float c = cos(phi);
		float a = wp.z * w;
		h += a * s;
		disp += g * (wp.w * a * c);
		grad += g * (a * wp.x * c);
		crest += wp.w * a * wp.x * s;
	}
	// Perturbações do mouse/impactos: pacotes de onda circulares amortecidos.
	for (int r = 0; r < MAX_RIPPLES; r++) {
		if (r >= ripple_count) {
			break;
		}
		vec3 center = ripple_points[r].xyz;
		float age = ripple_points[r].w;
		vec3 to_point = p - center;
		float dist = length(to_point);
		float front = ripple_info[r].y * age;
		float sigma = 0.9 + 0.55 * age;
		float x = dist - front;
		float k = 6.2831853 / (2.2 + 0.35 * age);
		float envelope = exp(-x * x / (2.0 * sigma * sigma));
		float amp = ripple_info[r].x * exp(-age * 0.9) / (1.0 + 0.12 * dist) * smoothstep(0.0, 0.08, age);
		float wave = -cos(k * x);
		h += amp * envelope * wave;
		// Realce de crista do anel: o toon achata a normal, então a cor carrega o gesto.
		ripple_glow += max(wave, 0.0) * envelope * smoothstep(0.0, 0.25, amp) * exp(-age * 0.6);
		float dh = amp * envelope * (k * sin(k * x) - wave * x / (sigma * sigma));
		vec3 radial_dir = dist > 0.001 ? to_point / dist : vec3(0.0);
		grad += (radial_dir - n * dot(n, radial_dir)) * dh;
	}
	stroke_eval(p, n, h, grad, ripple_glow);
}

// Sulco do arrasto: cavado no centro e cristas laterais que se afastam com a idade.
vec3 ocean_normal(vec3 p, vec3 grad, float crest) {
	vec3 n = normalize(p);
	return normalize(n * max(1.0 - crest, 0.2) - grad);
}

float hull_cutout(vec3 p) {
	if (!boat_cutout_enabled) {
		return 0.0;
	}
	vec3 from_boat = p - boat_position;
	vec2 hull = vec2(dot(from_boat, boat_forward) / 1.72, dot(from_boat, boat_right) / 0.62);
	return dot(hull, hull) < 1.0 ? 1.0 : 0.0;
}

float wake_foam(vec3 p) {
	// Distância à polilinha inteira (não por segmento), para não formar anéis nas juntas.
	float distance_to_wake = 1e6;
	float life = 0.0;
	for (int i = 0; i < MAX_WAKE - 1; i++) {
		if (i >= wake_count - 1) {
			break;
		}
		vec3 start = wake_points[i].xyz;
		vec3 segment = wake_points[i + 1].xyz - start;
		float along = clamp(dot(p - start, segment) / max(dot(segment, segment), 0.001), 0.0, 1.0);
		float d = length(p - start - segment * along);
		if (d < distance_to_wake) {
			distance_to_wake = d;
			life = mix(wake_points[i].w, wake_points[i + 1].w, along);
		}
	}
	if (life <= 0.0) {
		return 0.0;
	}
	// Esteira discreta (Seagazer): duas linhas finas de espuma que se abrem e se
	// quebram com a idade, e um rastro suave de água revolta no centro.
	float spread = 0.55 + (1.0 - life) * 2.2;
	float line_width = 0.07 + (1.0 - life) * 0.16;
	float edge = 1.0 - smoothstep(line_width * 0.3, line_width, abs(distance_to_wake - spread));
	// Quebra a linha em pedaços (ruído ao longo do mundo) conforme envelhece.
	float breakup = sin(dot(p, vec3(1.7, 2.3, 1.1)) * 1.3 + life * 9.0) * 0.5 + 0.5;
	breakup *= sin(dot(p, vec3(-2.9, 0.7, 2.1)) * 0.9) * 0.5 + 0.5;
	edge *= mix(1.0, smoothstep(0.15, 0.45, breakup), 1.0 - life);
	float core = (1.0 - smoothstep(0.0, spread * 0.8, distance_to_wake)) * 0.18;
	return max(edge * 0.7, core) * life * life;}

// Espuma de costa pela profundidade da cena (funciona no Compatibility e no Forward+).
float shore_foam_from_depth(float raw_depth, vec2 screen_uv, mat4 inv_projection, vec3 vertex_view) {
	float clip_depth;
	float has_geometry;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	clip_depth = raw_depth * 2.0 - 1.0;
	has_geometry = 1.0 - step(0.9999, raw_depth);
#else
	clip_depth = raw_depth;
	has_geometry = step(0.0001, raw_depth);
#endif
	vec4 scene_view = inv_projection * vec4(screen_uv * 2.0 - 1.0, clip_depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float gap = max(0.0, -scene_view.z + vertex_view.z);
	return (1.0 - smoothstep(0.05, shoreline_width, gap)) * has_geometry;
}

// Bandas toon suaves (sem step binário, para não voltar o "polka dot").
float toon_band(float value) {
	float scaled = clamp(value, 0.0, 1.0) * toon_bands;
	float base = floor(scaled);
	return (base + smoothstep(0.42, 0.58, fract(scaled))) / toon_bands;
}

// Cor final. h e crest normalizados pela escala de amplitude do mar atual.
// wake_point: onde a esteira é medida (no patch, a posição deslocada da água).
vec3 ocean_albedo(vec3 p, vec3 wake_point, float h, float crest, float ripple_glow, float shore, out float foam_out) {
	float amplitude_ref = max(wave_params[0].z * 1.6, 0.05);
	float height_tint = toon_band(smoothstep(-amplitude_ref, amplitude_ref, h));
	vec3 color = mix(deep_ocean_color, shallow_ocean_color, height_tint);
	float crest_line = smoothstep(0.32, 0.62, crest) * crest_line_amount;
	color = mix(color, crest_color, crest_line);
	color = mix(color, foam_color, clamp(ripple_glow, 0.0, 1.0) * 0.55);
	vec2 cloud_uv = vec2(dot(p, cloud_axis_u), dot(p, cloud_axis_v)) / cloud_shadow_scale + TIME * 0.0006;
	float shadow = smoothstep(0.52, 0.62, texture(cloud_shadow_tex, cloud_uv).x);
	color *= 1.0 - shadow * cloud_shadow_strength;
	float wake = wake_foam(wake_point);
	float foam = max(shore, wake * 0.75);
	foam_out = foam;
	return mix(color, foam_color, clamp(foam, 0.0, 0.96));
}

// Acabamento comum: reflexo do céu (Fresnel) e brilho noturno da esteira.
// normal_view/view em espaço de câmera. Escreve parte da cor como emissão.
void ocean_finish(vec3 p, vec3 normal_view, vec3 view, float foam, inout vec3 albedo, out vec3 emission) {
	// p aqui também é o ponto da esteira.
	float facing = clamp(dot(normalize(normal_view), normalize(view)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power) * fresnel_amount * (1.0 - foam);
	float day = 1.0 - night_amount;
	emission = sky_reflection_color * fresnel * mix(0.1, 0.4, day);
	albedo = mix(albedo, albedo * 0.6, fresnel);
	// Só as linhas da esteira brilham à noite (o miolo junto ao casco fica discreto).
	emission += night_glow_color * smoothstep(0.3, 0.7, wake_foam(p)) * night_amount * 0.3;
}
