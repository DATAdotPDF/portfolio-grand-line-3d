shader_type canvas_item;
render_mode blend_add;

// Flare do sol, tudo procedural (só a IDEIA estudada do Wind Waker: brilho em volta do sol e
// "fantasmas" — hexágonos e círculos — enfileirados na linha do sol que passa pelo centro da tela
// e segue para o lado oposto; nada de textura ou valor copiado).
// Visibilidade: 13 pontos dentro do disco do sol na imagem já renderizada. Se ilha, vela ou
// nuvem cobrir o sol, os pontos deixam de ser quase brancos e o flare apaga aos poucos (um
// pedaço do sol coberto = flare mais fraco). O script soma oclusão por raio físico e a borda da tela.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 sun_uv = vec2(0.5);      // posição do sol na tela (0..1)
uniform float aspect = 1.7778;
uniform float strength = 0.0;         // 0 = sem sol (noite, atrás da câmera, tempestade, oclusão física)
uniform float sun_radius = 0.016;     // raio do disco do sol na tela (fração da altura)
uniform vec3 tint : source_color = vec3(1.0, 0.96, 0.87); // cor da luz do sol (quente no poente)

const int GHOSTS = 9;
// Posição na linha (0 = sol, 1 = centro da tela, 2 = espelho do sol), raio (altura da tela),
// forma (0 disco, 1 hexágono, 2 anel), intensidade.
const float G_POS[9] = float[9](0.22, 0.42, 0.6, 0.78, 1.08, 1.3, 1.55, 1.85, 2.15);
const float G_RAD[9] = float[9](0.018, 0.046, 0.013, 0.032, 0.06, 0.022, 0.095, 0.04, 0.15);
const int G_SHAPE[9] = int[9](1, 0, 1, 1, 1, 0, 1, 0, 2);
const float G_INT[9] = float[9](0.42, 0.16, 0.45, 0.32, 0.2, 0.34, 0.12, 0.24, 0.16);
const vec3 G_COL[9] = vec3[9](
	vec3(1.0, 0.72, 0.3), vec3(0.35, 0.75, 1.0), vec3(0.55, 1.0, 0.4),
	vec3(1.0, 0.45, 0.75), vec3(0.45, 0.7, 1.0), vec3(1.0, 0.9, 0.45),
	vec3(0.7, 0.5, 1.0), vec3(0.4, 1.0, 0.75), vec3(1.0, 0.65, 0.4));

float sun_visible() {
	// Centro + 2 anéis de 6 pontos dentro do disco (30% e 65% do raio).
	float v = 0.0;
	float n = 0.0;
	for (int i = 0; i < 13; i++) {
		vec2 o = vec2(0.0);
		if (i > 0) {
			float a = float(i) * 1.0472 + (i > 6 ? 0.5236 : 0.0);
			o = vec2(cos(a), sin(a)) * sun_radius * (i > 6 ? 0.65 : 0.3);
		}
		vec2 p = sun_uv + o * vec2(1.0 / aspect, 1.0);
		n += 1.0;
		if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) {
			continue;
		}
		vec3 c = textureLod(screen_tex, p, 0.0).rgb;
		// Sol = quase branco; céu, nuvem contra a luz, ilha e vela ficam bem abaixo.
		// O canal mais fraco decide: nuvem iluminada é creme (azul < 0,9), o sol é branco puro.
		v += smoothstep(0.92, 0.98, min(c.r, min(c.g, c.b)));
	}
	return v / n;
}

// Distância com sinal até um hexágono regular (apótema r).
float sd_hex(vec2 p, float r) {
	const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

void fragment() {
	if (strength <= 0.001) {
		discard;
	}
	float vis = sun_visible();
	if (vis <= 0.001) {
		discard;
	}
	vec2 asp = vec2(aspect, 1.0);
	vec2 axis = vec2(0.5) - sun_uv;
	// 1 olhando direto para o sol, 0 com o sol no canto.
	float staring = 1.0 - clamp(length(axis * asp) / 0.85, 0.0, 1.0);
	float aa = 1.5 * SCREEN_PIXEL_SIZE.y;  // ~1,5 px de borda suave
	vec3 col = vec3(0.0);

	// Brilho do sol: núcleo pequeno + halo largo e fraco + anel de halo bem leve.
	vec2 ds = (UV - sun_uv) * asp;
	float r = length(ds);
	float core = exp(-r * r / (0.00045 + 0.00035 * staring));
	float halo = exp(-r / (0.05 + 0.03 * staring)) * (0.16 + 0.08 * staring);
	float ring = smoothstep(0.012, 0.0, abs(r - 0.21)) * 0.035;
	// Raios curtos (8) girando devagar conforme o sol anda na tela.
	float ang = atan(ds.y, ds.x) + sun_uv.x * 1.3;
	float rays = pow(abs(cos(ang * 4.0)), 60.0) * exp(-r * 14.0) * 0.18;
	col += tint * (core * 0.8 + halo + rays) + vec3(0.75, 0.85, 1.0) * ring;

	// Fantasmas na linha sol → centro → espelho.
	for (int i = 0; i < GHOSTS; i++) {
		vec2 c = sun_uv + axis * G_POS[i];
		vec2 d = (UV - c) * asp;
		float rad = G_RAD[i];
		if (abs(d.x) > rad * 1.3 || abs(d.y) > rad * 1.3) {
			continue;
		}
		float shape;
		if (G_SHAPE[i] == 1) {
			// Hexágono (íris de 6 lâminas), um pouco girado; borda nítida e mais clara (toon).
			vec2 q = mat2(vec2(0.966, 0.259), vec2(-0.259, 0.966)) * d;
			float sd = sd_hex(q, rad);
			shape = smoothstep(aa, -aa, sd) * (0.55 + 0.45 * smoothstep(-rad * 0.3, 0.0, sd));
		} else if (G_SHAPE[i] == 0) {
			float sd = length(d) - rad;
			shape = smoothstep(aa, -aa, sd) * (0.6 + 0.4 * smoothstep(-rad * 0.4, 0.0, sd));
		} else {
			// Anel fino com franja de cor (como aberração cromática).
			float dr = length(d) - rad;
			vec3 fringe = vec3(smoothstep(0.006, 0.0, abs(dr - 0.004)), smoothstep(0.006, 0.0, abs(dr)), smoothstep(0.006, 0.0, abs(dr + 0.004)));
			col += fringe * G_INT[i] * tint;
			continue;
		}
		col += G_COL[i] * tint * shape * G_INT[i];
	}
	// Olhando bem para o sol: véu claro na tela toda (ofusca de leve).
	col += tint * 0.035 * staring * staring * staring;
	COLOR = vec4(col * vis * strength, 1.0);
}
