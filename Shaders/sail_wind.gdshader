shader_type spatial;
render_mode cull_disabled;

// Material das peças de pano da chalupa, cada uma com o seu (main_world.gd):
// - part 0 = vela principal (Sail_Main) e part 1 = vela de popa (Sail_Stern): "barriga" para a proa,
//   presa nas bordas (vergas e mastro) e cheia no meio; enche com a velocidade + rajadas de vento;
// - part 2 = bandeira preta (Flag): tremula mais longe do mastro.
// A Jolly Roger é projetada aqui só na vela principal (Decal não existe no WebGL 2 Compatibility).

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform int part = 0;
// Caixa da peça no espaço local do modelo (mesh.get_aabb()): dá a posição relativa de cada vértice no pano.
uniform vec3 sail_min = vec3(-0.5);
uniform vec3 sail_max = vec3(0.5);
uniform float wind_strength = 0.085;
uniform sampler2D jolly_roger : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.0);
// Proa em espaço local do modelo (enviado pelo main_world).
uniform vec3 forward_local = vec3(1.0, 0.0, 0.0);
uniform float boat_speed = 0.0;
uniform float max_speed = 12.5;
uniform float flag_amount : hint_range(0.0, 0.3) = 0.11;
// 1 só na vela principal; nas outras peças de pano a Jolly Roger não aparece.
uniform float emblem : hint_range(0.0, 1.0) = 1.0;
// Fases acumuladas no main_world (sem pulo quando a velocidade muda) e velocidade suavizada.
uniform float flag_phase = 0.0;
uniform float sail_phase = 0.0;
uniform float cloth_speed = 0.0;
varying vec3 sail_rest;
// Normal de repouso no espaço do modelo: o emblema só vale onde o pano encara a projeção.
varying vec3 rest_normal;

void vertex() {
	sail_rest = VERTEX;
	rest_normal = NORMAL;
	float speed = clamp(boat_speed / max_speed, 0.0, 1.0);
	vec3 size = max(sail_max - sail_min, vec3(0.001));
	vec3 n = clamp((VERTEX - sail_min) / size, vec3(0.0), vec3(1.0));

	if (part < 2) {
		// Barriga: zero nas bordas (presas), máxima no meio do pano; velas menores enchem proporcionalmente.
		// Topo bem preso à verga (n.y alto) e lados presos ao mastro/vergas: a curva começa na
		// madeira, sem o pano atravessar a verga quando enche.
		float belly = sin(n.y * PI) * pow(sin(n.z * PI), 1.4) * smoothstep(1.0, 0.78, n.y) * smoothstep(0.0, 0.12, n.y);
		float scale = size.y / 0.56;
		float gust = 0.75 + 0.25 * sin(TIME * 1.15 + VERTEX.z * 3.0 + float(part) * 1.7);
		float flutter = sin(sail_phase + VERTEX.z * 17.0 + VERTEX.y * 9.0) * 0.012;
		float fill = (0.02 + 0.11 * speed + 0.03 * wind_strength / 0.085) * scale * belly * gust;
		VERTEX += normalize(forward_local) * fill;
		VERTEX += normalize(wind_direction) * wind_strength * flutter * 4.0 * belly;
	} else {
		// Bandeira: duas ondas viajando do mastro para a ponta + caimento leve quando o barco está parado.
		float from_pole = clamp(abs(VERTEX.z) / 0.25 + abs(VERTEX.x) / 0.25, 0.0, 1.0);
		// Fase acumulada (flag_phase) e amplitude pela velocidade suavizada: parado, a bandeira
		// cai e ondula devagar; andando, tremula mais.
		float t_flag = flag_phase;
		float wave = sin(t_flag - from_pole * 8.0) * 0.7 + sin(t_flag * 1.73 - from_pole * 13.0 + 1.3) * 0.3;
		float reach = from_pole * from_pole;
		float amp = flag_amount * mix(0.45, 1.0, cloth_speed);
		VERTEX += cross(normalize(forward_local), vec3(0.0, 1.0, 0.0)) * wave * amp * reach;
		VERTEX.y += (cos(t_flag * 0.9 - from_pole * 6.0) * 0.35 - (1.0 - cloth_speed) * 0.5) * amp * reach;
	}
}

void fragment() {
	// Faces de trás (pano, bandeira): normal invertida, senão ficam pretas.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 base = texture(albedo_map, UV).rgb;
	vec2 emblem_uv = vec2((sail_rest.z + 0.32) / 0.64, 1.0 - (sail_rest.y + 0.13) / 0.52);
	vec2 q = (emblem_uv - vec2(0.5)) * 2.0;
	// Borda do círculo nítida (antes um degradê cinza largo em volta).
	float ink_mask = smoothstep(1.0, 0.96, length(q));
	// Projeção é de lado (eixo X do modelo): onde o pano curva, o desenho escorria em mancha preta.
	ink_mask *= smoothstep(0.2, 0.45, abs(normalize(rest_normal).x));
	ink_mask *= smoothstep(0.56, 0.79, min(base.r, min(base.g, base.b)));
	vec3 ink = texture(jolly_roger, clamp(emblem_uv, vec2(0.0), vec2(1.0))).rgb;
	ALBEDO = mix(base, ink, ink_mask * 0.9 * emblem);
	ROUGHNESS = 0.82;
	SPECULAR = 0.16;
}
