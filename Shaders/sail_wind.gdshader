shader_type spatial;
render_mode cull_disabled;

// Material da chalupa (malha única do modelo). Só as regiões de pano se mexem:
// - velas brancas: "barriga" para a proa que cresce com a velocidade + rajadas;
// - bandeira preta no topo do mastro: tremula com o vento.
// A Jolly Roger é projetada aqui (Decal não existe no WebGL 2 Compatibility).

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform float bottom;
uniform float height;
uniform float wind_strength = 0.085;
uniform sampler2D jolly_roger : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.0);
// Proa em espaço local do modelo (enviado pelo main_world).
uniform vec3 forward_local = vec3(1.0, 0.0, 0.0);
uniform float boat_speed = 0.0;
uniform float max_speed = 12.5;
uniform float flag_amount : hint_range(0.0, 0.2) = 0.05;
varying vec3 sail_rest;

void vertex() {
	sail_rest = VERTEX;
	vec3 paint = textureLod(albedo_map, UV, 0.0).rgb;
	float h = (VERTEX.y - bottom) / height;
	float speed = clamp(boat_speed / max_speed, 0.0, 1.0);

	// Velas (pano claro, faixa média de altura).
	float white = smoothstep(0.38, 0.68, min(paint.r, min(paint.g, paint.b)));
	float cloth = white * smoothstep(0.35, 0.48, h) * (1.0 - smoothstep(0.78, 0.88, h));
	cloth *= 1.0 - smoothstep(0.05, 0.30, VERTEX.x);
	float vertical = sin(clamp((h - 0.4) / 0.45, 0.0, 1.0) * 3.14159);
	float across = cos(clamp(VERTEX.z / 0.36, -1.0, 1.0) * 1.5708);
	float belly = vertical * max(across, 0.0);
	float gust = 0.75 + 0.25 * sin(TIME * 1.15 + VERTEX.z * 3.0);
	float flutter = sin(TIME * (5.0 + boat_speed * 0.4) + VERTEX.z * 17.0 + VERTEX.y * 9.0) * 0.012;
	float fill = (0.025 + 0.11 * speed) * belly * gust;
	VERTEX += normalize(forward_local) * fill * cloth;
	VERTEX += normalize(wind_direction) * wind_strength * cloth * flutter * 4.0;

	// Bandeira preta no topo: tremula mais longe do mastro.
	float dark = 1.0 - smoothstep(0.12, 0.22, max(paint.r, max(paint.g, paint.b)));
	float flag = dark * smoothstep(0.86, 0.92, h);
	float from_pole = clamp(abs(VERTEX.z) / 0.25 + abs(VERTEX.x) / 0.25, 0.0, 1.0);
	float wave = sin(TIME * (7.0 + speed * 6.0) - from_pole * 9.0);
	VERTEX += cross(normalize(forward_local), vec3(0.0, 1.0, 0.0)) * wave * flag_amount * from_pole * flag;
	VERTEX.y += cos(TIME * 6.0 - from_pole * 7.0) * flag_amount * 0.35 * from_pole * flag;
}

void fragment() {
	vec3 base = texture(albedo_map, UV).rgb;
	vec2 emblem_uv = vec2((sail_rest.z + 0.32) / 0.64, 1.0 - (sail_rest.y + 0.13) / 0.52);
	vec2 q = (emblem_uv - vec2(0.5)) * 2.0;
	float ink_mask = smoothstep(1.0, 0.83, length(q));
	ink_mask *= 1.0 - smoothstep(-0.12, -0.005, sail_rest.x);
	ink_mask *= smoothstep(0.56, 0.79, min(base.r, min(base.g, base.b)));
	vec3 ink = texture(jolly_roger, clamp(emblem_uv, vec2(0.0), vec2(1.0))).rgb;
	ALBEDO = mix(base, ink, ink_mask * 0.9);
	ROUGHNESS = 0.82;
	SPECULAR = 0.16;
}
