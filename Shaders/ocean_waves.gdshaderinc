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

// Tempestades locais (Weather): ondas maiores e água mais escura dentro do raio de cada uma.
#define MAX_STORMS 6
uniform vec4 storm_data[MAX_STORMS];      // xyz = centro na superfície, w = raio
uniform float storm_strengths[MAX_STORMS]; // "badness" 0..4 de cada tempestade (Weather.gd)
uniform int storm_count = 0;
uniform vec3 storm_water_tint : source_color = vec3(0.4, 0.56, 0.5);  // verde-acinzentado (Wind Waker)

uniform vec3 island_centers[5];
uniform float island_radii[5];
// Mar calmo também em volta das ilhas/rochas do mapa (WorldDecor, só as fixas): as MAX_CALM mais
// perto do barco, atualizadas pelo main_world. xyz = direção (unitária), w = raio em metros.
#define MAX_CALM 16
uniform vec4 calm_spots[MAX_CALM];
uniform int calm_count = 0;
// Redemoinho do kraken (KrakenEvent): o próprio mar afunda num funil. xyz = centro, w = raio.
uniform vec4 whirl_data = vec4(0.0);
uniform float whirl_depth = 0.0;

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
// Ondinhas de contato: anéis animados que saem de tudo o que encosta na água (ilhas, rochas, barco,
// tartaruga), lidos da mesma distância até a cena que faz a espuma da borda. Ideia do tutorial
// "Adding Ripples to 3D Water in Godot 4" (bramreth, MIT); conta nossa, no estilo toon do mar.
uniform float contact_ring_reach = 4.0;   // até onde os anéis vão (m de profundidade vista)
uniform float contact_ring_count = 3.0;   // anéis dentro desse alcance
uniform float contact_ring_speed = 0.35;  // anéis por segundo saindo da borda
uniform float contact_ring_strength = 0.8;
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
	for (int i = 0; i < MAX_CALM; i++) {
		if (i >= calm_count) {
			break;
		}
		float chord = distance(p, calm_spots[i].xyz * planet_radius);
		factor = min(factor, smoothstep(calm_spots[i].w * 0.7, calm_spots[i].w + 25.0 * wave_scale, chord));
	}
	// Dentro do redemoinho do kraken as ondas baixam (senão quebram a imagem do funil).
	if (whirl_depth > 0.0) {
		factor = min(factor, mix(0.2, 1.0, smoothstep(whirl_data.w * 0.7, whirl_data.w * 1.15, distance(p, whirl_data.xyz))));
	}
	return mix(0.08, 1.0, factor);
}

// x = máscara (0..1) da tempestade mais forte no ponto, y = badness dela (0..4).
vec2 storm_eval(vec3 p) {
	vec2 best = vec2(0.0);
	for (int i = 0; i < MAX_STORMS; i++) {
		if (i >= storm_count) {
			break;
		}
		// Cheio debaixo da nuvem inteira (que vai até ~1,15 raio) e some logo depois.
		float m = 1.0 - smoothstep(storm_data[i].w * 0.95, storm_data[i].w * 1.45, distance(p, storm_data[i].xyz));
		if (m * storm_strengths[i] > best.x * best.y) {
			best = vec2(m, storm_strengths[i]);
		}
	}
	return best;
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
// Redemoinho: as ondas são torcidas em espiral em volta do centro (mais perto, mais torção), como
// num vórtice de verdade. Rotação rígida no tempo fica por conta do disco de espuma; aqui a
// torção é estática (não "enrola" com o tempo).
vec3 whirl_twist(vec3 p) {
	if (whirl_depth <= 0.0) {
		return p;
	}
	float d = distance(p, whirl_data.xyz);
	float R = whirl_data.w;
	if (d >= R) {
		return p;
	}
	float k = clamp(1.0 - d / R, 0.0, 1.0);
	float angle = whirl_depth * 0.22 * pow(k, 1.6) * (1.0 - smoothstep(0.55, 1.0, d / R) * 0.0);
	vec3 c = normalize(whirl_data.xyz);
	return p * cos(angle) + cross(c, p) * sin(angle) + c * dot(c, p) * (1.0 - cos(angle));
}

// Perfil de vórtice de Rankine (normalizado): fundo e íngreme no miolo, plano para fora.
float whirl_profile(float d, float R, out float slope) {
	float rc = R * 0.2;
	float rc2 = rc * rc;
	float fr = rc2 / (R * R + rc2);
	float f = (rc2 / (d * d + rc2) - fr) / (1.0 - fr);
	slope = 2.0 * d * rc2 / ((d * d + rc2) * (d * d + rc2) * (1.0 - fr));
	return max(f, 0.0);
}

void ocean_eval(vec3 p, float view_distance, out float h, out vec3 disp, out vec3 grad, out float crest, out float ripple_glow) {
	p = whirl_twist(p);
	vec3 n = normalize(p);
	float t = ocean_clock();
	vec2 storm = storm_eval(p);
	// Badness: ondas mais altas e, proporcionalmente, só um pouco mais íngremes. O Q é dividido
	// pelo ganho de altura para a compressão (crest) não passar muito de 1 e virar laço.
	float storm_amp = 1.0 + 0.35 * storm.y * storm.x;
	float storm_q = (1.0 + 0.08 * storm.y * storm.x) / storm_amp;
	float coast = coast_factor(p) * storm_amp;
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
		disp += g * (wp.w * storm_q * a * c);
		grad += g * (a * wp.x * c);
		crest += wp.w * storm_q * a * wp.x * s;
	}
	// Mar picado da tempestade: uma segunda oitava curta (2,6× mais curta, cruzada com a
	// direção de outra onda), só onde há badness. Deixa as cristas em bico e cheias de espuma.
	// Sempre um pouco de mar picado (textura, como no Sea of Thieves); cresce com o badness.
	float chop = clamp(0.2 + storm.x * storm.y / 4.0, 0.0, 1.0);
	if (chop > 0.01) {
		float calm_coast = coast / storm_amp;
		for (int i = 0; i < MAX_WAVES; i++) {
			if (i >= wave_count) {
				break;
			}
			vec4 wp = wave_params[i];
			vec3 d = normalize(wave_dirs[i].xyz + wave_dirs[(i + 1) % max(wave_count, 1)].xyz * 0.6);
			vec3 g = d - n * dot(n, d);
			float k = wp.x * 2.6;
			float w = smoothstep(CALM_INNER, CALM_OUTER, length(g)) * calm_coast * chop;
			if (view_distance >= 0.0) {
				float wavelength = 6.2831853 / k;
				w *= 1.0 - smoothstep(wavelength * far_detail_distance * 0.4, wavelength * far_detail_distance, view_distance);
			}
			float phi = k * dot(p, d) - wp.y * 1.6125 * t + wave_dirs[i].w * 3.1;
			float s = sin(phi);
			float c = cos(phi);
			float a = wp.z * 0.3 * w;
			h += a * s;
			disp += g * (wp.w * 0.8 * a * c);
			grad += g * (a * k * c);
			crest += wp.w * 0.8 * a * k * s;
		}
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
	if (whirl_depth > 0.0) {
		vec3 tp = p - whirl_data.xyz;
		float d = length(tp);
		if (d < whirl_data.w) {
			float slope;
			float f = whirl_profile(d, whirl_data.w, slope);
			h -= whirl_depth * f;
			vec3 rd = d > 0.001 ? tp / d : vec3(0.0);
			grad += (rd - n * dot(n, rd)) * (whirl_depth * slope);
		}
	}
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
	// Começa na largura das madeiras laterais do casco (~0,95 m do centro).
	float spread = 0.95 + (1.0 - life) * 2.2;
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
	float rim = 1.0 - smoothstep(0.05, shoreline_width, gap);
	// Anéis: fase pela distância à borda, correndo para fora com o tempo; finos e sumindo com a distância.
	float x = gap / contact_ring_reach;
	float phase = fract(x * contact_ring_count - ocean_clock() * contact_ring_speed);
	float ring = smoothstep(0.0, 0.1, phase) * (1.0 - smoothstep(0.2, 0.38, phase));
	ring *= (1.0 - smoothstep(0.35, 1.0, x)) * smoothstep(shoreline_width * 0.6, shoreline_width * 1.4, gap);
	return max(rim, ring * contact_ring_strength) * has_geometry;
}

// Bandas toon suaves (sem step binário, para não voltar o "polka dot").
float toon_band(float value) {
	float scaled = clamp(value, 0.0, 1.0) * toon_bands;
	float base = floor(scaled);
	return (base + smoothstep(0.42, 0.58, fract(scaled))) / toon_bands;
}

// Quatro mares (WorldDecor.gd, biomas): Norte lat ≥ 30, Sul lat ≤ -30, Leste/Oeste na faixa do
// equador (lon 0–180 / 180–360). Cada um puxa a cor do mar para o seu tom (a = quanto), com
// transição suave de biome_blend graus nas bordas. Desligado até o WorldDecor ligar.
uniform bool biome_tint_enabled = false;
uniform vec4 biome_tints[4];   // N, L, S, O
uniform float biome_blend = 7.0;

vec3 biome_tint(vec3 p, vec3 color) {
	if (!biome_tint_enabled) {
		return color;
	}
	vec3 n = normalize(p);
	float lat = degrees(asin(clamp(n.y, -1.0, 1.0)));
	float north = smoothstep(30.0 - biome_blend, 30.0 + biome_blend, lat);
	float south = smoothstep(-30.0 + biome_blend, -30.0 - biome_blend, lat);
	float band = max(1.0 - north - south, 0.0);
	// Leste = z > 0 (lon 0–180); a borda vale nos dois meridianos (0° e 180°).
	float side = n.z / max(length(n.xz), 0.0001);
	float east = smoothstep(-sin(radians(biome_blend)), sin(radians(biome_blend)), side);
	vec4 t = biome_tints[0] * north + biome_tints[2] * south + (biome_tints[1] * east + biome_tints[3] * (1.0 - east)) * band;
	return mix(color, t.rgb, clamp(t.a, 0.0, 1.0));
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
	// Dentro da tempestade o mar fica cinza-esverdeado e escuro (as cristas continuam claras).
	vec2 storm = storm_eval(p);
	float badness = storm.x * storm.y;
	color = mix(color, color * storm_water_tint * 1.3, storm.x * clamp(storm.y / 2.5, 0.0, 1.0));
	color = biome_tint(p, color);
	// Espuma onde a onda dobra sobre si mesma: crest é a compressão horizontal do Gerstner
	// (1 - Jacobiano), então crest alto = crista se fechando. Só aparece com badness.
	// Rasgos orgânicos: a textura de ruído das sombras de nuvem em escala de metros, em duas
	// escalas que andam em sentidos diferentes (espuma de tempestade é rasgada, não um tapete).
	vec2 foam_uv = vec2(dot(p, cloud_axis_u), dot(p, cloud_axis_v));
	float n1 = texture(cloud_shadow_tex, foam_uv * 0.045 + vec2(ocean_clock() * 0.012, 0.0)).x;
	float n2 = texture(cloud_shadow_tex, foam_uv * 0.11 - vec2(0.0, ocean_clock() * 0.02)).x;
	float breakup = (n1 * 0.6 + n2 * 0.4) * 2.0 - 1.0;
	// Calmo: só o topo das cristas mais altas (~5%) quebra; tempestade: muito mais.
	float cap_threshold = mix(0.38, 0.5, clamp(badness / 4.0, 0.0, 1.0));
	float breakup_weight = mix(0.22, 0.45, smoothstep(0.3, 1.2, badness));
	// Recortada em tiras pelo breakup (espuma de tempestade é rasgada, não um tapete).
	float whitecap = smoothstep(cap_threshold, cap_threshold + 0.08, crest + breakup * breakup_weight) * mix(0.55, 0.9, smoothstep(0.3, 1.2, badness));
	// Rendado de espuma nas faces que sobem para a crista (textura do mar quebrando, como no
	// Sea of Thieves): veios finos do ruído só onde a onda está se fechando um pouco.
	float lace_noise = texture(cloud_shadow_tex, foam_uv * 0.32 + vec2(ocean_clock() * 0.03, -ocean_clock() * 0.02)).x;
	float lace = (1.0 - smoothstep(0.03, 0.07, abs(lace_noise - 0.55))) * smoothstep(0.12, 0.32, crest) * 0.35;
	whitecap = max(whitecap, lace * (1.0 - smoothstep(60.0, 160.0, distance(p, boat_position))));
	vec2 cloud_uv = vec2(dot(p, cloud_axis_u), dot(p, cloud_axis_v)) / cloud_shadow_scale + TIME * 0.0006;
	float shadow = smoothstep(0.52, 0.62, texture(cloud_shadow_tex, cloud_uv).x);
	color *= 1.0 - shadow * cloud_shadow_strength;
	float wake = wake_foam(wake_point);
	float foam = max(max(shore, wake * 0.75), whitecap);
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
