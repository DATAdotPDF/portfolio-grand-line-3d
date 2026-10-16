shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

// Navio fantasma (GhostShip.gd) como LUZ: em vez de casco semitransparente (as faces internas se
// misturavam fora de ordem e viravam borrão), o navio soma brilho na tela — a ordem não importa,
// sobreposições viram mais brilho. Técnica do "ghost shader" da Miskatonic Studio (MIT,
// github.com/miskatonicstudio/godot-experiments): borda fresnel acesa, miolo quase invisível e malha
// ondulando com ruído. Nossa versão mantém a textura legível (tábuas, frisos, velas rasgadas), as
// velas/bandeira balançando e a névoa de aparecer/sumir.
// part: 0 casco/mastros, 1 velas, 2 bandeira.

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 body_color : source_color = vec3(0.1, 0.55, 0.42);
uniform vec3 rim_color : source_color = vec3(0.45, 1.0, 0.78);
uniform float fresnel_power : hint_range(0.5, 6.0) = 2.6;
uniform float body_glow = 0.35;     // brilho do miolo (detalhes da textura)
uniform float rim_glow = 1.6;       // brilho da borda
uniform float wobble = 0.06;        // ondulação da malha (m)
uniform float presence = 1.0;       // 0 = sumiu na névoa, 1 = inteiro
uniform int part = 0;
uniform float sway_top = 8.3;
uniform float sway_bottom = 2.4;
uniform float flag_near = 0.3;
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
	// Ondulação espectral (como no ghost shader): a malha "respira" ao longo da normal.
	float n = noise3(VERTEX * 0.7 + vec3(0.0, TIME * 0.5, TIME * 0.3));
	VERTEX += NORMAL * (n - 0.5) * 2.0 * wobble;
	local_pos = VERTEX;
}

void fragment() {
	vec3 nrm = FRONT_FACING ? NORMAL : -NORMAL;
	float fresnel = pow(1.0 - clamp(abs(dot(nrm, VIEW)), 0.0, 1.0), fresnel_power);
	vec3 tex = texture(albedo_map, UV).rgb;
	float lum = dot(tex, vec3(0.3, 0.59, 0.11));
	// Detalhes: só os claros da textura acendem no miolo (frisos, ossos, lanternas, bordas das tábuas).
	float detail = smoothstep(0.25, 0.85, lum);
	// Alma subindo pelo casco.
	float soul = smoothstep(0.6, 0.95, noise3(local_pos * vec3(0.6, 0.35, 0.6) - vec3(0.0, TIME * 0.8, 0.0)));
	float flicker = 0.9 + 0.1 * sin(TIME * 3.0 + local_pos.y * 0.7);
	vec3 col = body_color * (body_glow * (0.25 + detail) + soul * 0.35) + rim_color * fresnel * rim_glow;
	// Velas mais fracas e rasgos escuros somem (só sobra a trama clara).
	if (part == 1) {
		col *= 0.45 + 0.55 * detail;
	}
	// Névoa: some/aparece em manchas, com a borda da mancha acesa.
	float mist = noise3(local_pos * 0.9 + vec3(0.0, TIME * 0.6, 0.0));
	float edge = presence * 1.25 - 0.12 - local_pos.y * 0.01;
	if (mist > edge) {
		discard;
	}
	float glow_edge = 1.0 - smoothstep(0.0, 0.12, edge - mist);
	col += rim_color * glow_edge * 0.8;
	ALBEDO = col * flicker * presence;
}
