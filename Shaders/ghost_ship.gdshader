shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled;

// Navio fantasma (GhostShip.gd), modelo original do Meshy com textura (Tools/ghost_ship_from_original.py).
// A textura vira um "negativo espectral": tábuas, velas e detalhes continuam legíveis, pintados em
// verde-água; casco mais sólido, velas mais translúcidas (as partes escuras/rasgadas quase somem),
// brilho fresnel nas bordas, luz interna correndo para cima e dissolução em névoa ao aparecer/sumir.
// part: 0 casco/mastros, 1 velas (balançam abaixo da verga), 2 bandeira (ondula longe do mastro).

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.0, 0.05, 0.06);
uniform vec3 pale_color : source_color = vec3(0.22, 0.95, 0.62);
uniform vec3 rim_color : source_color = vec3(0.45, 1.0, 0.75);
uniform float fresnel_power : hint_range(0.5, 6.0) = 2.2;
uniform float flicker_speed = 3.0;
uniform float presence = 1.0;      // 0 = sumiu na névoa, 1 = inteiro
uniform int part = 0;
uniform float sway_top = 8.3;      // velas: altura (local) da verga; a vela balança abaixo dela
uniform float sway_bottom = 2.4;
uniform float flag_near = 0.3;     // bandeira: distância do mastro onde fica presa
uniform float flag_far = 2.5;

varying vec3 local_pos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	if (part == 1) {
		float w = clamp((sway_top - VERTEX.y) / max(sway_top - sway_bottom, 0.01), 0.0, 1.0);
		VERTEX.x += sin(TIME * 2.2 + VERTEX.y * 0.6 + VERTEX.z * 0.4) * 0.35 * w;
		VERTEX.z += sin(TIME * 1.7 + VERTEX.y * 0.8) * 0.15 * w;
	} else if (part == 2) {
		float d = abs(VERTEX.z);
		float w = clamp((d - flag_near) / max(flag_far - flag_near, 0.01), 0.0, 1.0);
		VERTEX.x += sin(TIME * 6.0 - d * 3.0) * 0.3 * w;
		VERTEX.y += sin(TIME * 5.0 - d * 2.5) * 0.1 * w;
	}
	local_pos = VERTEX;
}

void fragment() {
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	vec3 tex = texture(albedo_map, UV).rgb;
	float lum = dot(tex, vec3(0.3, 0.59, 0.11));
	// Volume: luz falsa vinda de cima (espaço da câmera) — o navio não some num chapado.
	float shade = 0.55 + 0.45 * clamp(dot(n, normalize(vec3(0.25, 0.9, 0.35))), 0.0, 1.0);
	float fresnel = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), fresnel_power);
	float flicker = 0.92 + 0.08 * sin(TIME * flicker_speed + local_pos.y * 0.7);
	// Luz interna espectral subindo pelo casco.
	float soul = noise3(local_pos * vec3(0.6, 0.35, 0.6) - vec3(0.0, TIME * 0.8, 0.0));
	soul = smoothstep(0.55, 0.95, soul);
	// Corpo escuro esverdeado com a textura em relevo; só os claros (frisos, lanternas, ossos) acendem.
	vec3 col = mix(deep_color, pale_color * 0.55, smoothstep(0.05, 0.85, lum)) * shade;
	col += pale_color * smoothstep(0.5, 0.9, lum) * 0.6;
	col += pale_color * soul * 0.45;
	col = mix(col, rim_color, fresnel * 0.85);
	// Névoa: ao aparecer/sumir o navio se desfaz em manchas, de cima para baixo.
	float mist = noise3(local_pos * 0.9 + vec3(0.0, TIME * 0.6, 0.0));
	float edge = presence * 1.25 - 0.12 - local_pos.y * 0.01;
	if (mist > edge) {
		discard;
	}
	float glow_edge = 1.0 - smoothstep(0.0, 0.12, edge - mist);
	col = mix(col, rim_color * 1.4, glow_edge);
	float body = part == 0 ? 0.5 : (part == 1 ? 0.18 + 0.35 * smoothstep(0.08, 0.5, lum) : 0.45);
	ALBEDO = col * flicker;
	ALPHA = clamp(body + fresnel * 0.5 + soul * 0.15 + glow_edge * 0.3, 0.0, 0.95);
}
