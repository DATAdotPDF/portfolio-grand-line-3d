shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque, unshaded, fog_disabled;

// Casca do tornado (Cyclone.gd) no estilo estudado no vídeo do Wind Waker (noclip, só estudo):
// poucas faixas LARGAS em hélice, lisas, em dois tons; cascas concêntricas girando em ritmos e
// sentidos diferentes (o desencontro dá o volume); a boca abre em fitas rasgadas. Desenho todo
// procedural nosso; o ruído das bordas é a textura grátis do Le Lu.

uniform vec3 light_color : source_color = vec3(0.84, 0.86, 0.92);
uniform vec3 shade_color : source_color = vec3(0.6, 0.62, 0.72);
uniform sampler2D noise_texture : repeat_enable, filter_linear_mipmap;
uniform float bands = 3.0;          // faixas em volta (inteiro = sem costura)
uniform float twist = 2.2;          // voltas que a faixa dá da base ao topo
uniform float spin = 0.35;          // voltas por segundo (sinal = sentido)
uniform float band_width = 0.55;    // fração da faixa que é "cheia"
uniform float gaps = 0.0;           // 0 = casca fechada, 1 = só as faixas (vê a de dentro)
uniform float ragged = 0.35;        // quanto a borda da faixa é rasgada
uniform float mouth_tear = 1.0;     // fitas rasgadas na boca
uniform float opacity = 1.0;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
// Forma (iguais às do Cyclone.gd, para a física seguir o desenho).
uniform float height = 95.0;
uniform float sway_amount = 3.2;
uniform float sway_time = 0.0;
uniform float s_curve = 9.0;
uniform float grow = 1.0;
uniform float night = 0.0;
uniform float flash = 0.0;

varying float h;
varying vec3 world_normal;

vec2 sway(float k) {
	float amp = sway_amount * pow(k, 1.3) * (sin(sway_time * 1.6 - k * 5.0) * 0.5 + 0.5);
	float dir = sway_time * 0.8 - k * 7.0;
	float s = s_curve * sin(k * 3.14159 * 1.25) * (1.0 - 0.35 * k);
	float s_dir = sway_time * 0.12;
	return vec2(cos(dir), sin(dir)) * amp + vec2(cos(s_dir), sin(s_dir)) * s;
}

void vertex() {
	h = clamp(VERTEX.y / height, 0.0, 1.2);
	VERTEX.xz = VERTEX.xz * grow + sway(min(h, 1.0));
	VERTEX.y *= grow;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float u = UV.x;
	// Fase da faixa: volta em hélice (torce com a altura) e gira com o tempo.
	float phase = u * bands + h * twist * bands - TIME * spin * bands;
	// Borda ondulada/rasgada: ruído rolando junto com a faixa.
	float n = texture(noise_texture, vec2(phase / bands * 2.0, h * 3.0 - TIME * 0.12)).r;
	float stripe = fract(phase + (n - 0.5) * ragged);
	float band = smoothstep(0.0, 0.04, stripe) * (1.0 - smoothstep(band_width - 0.04, band_width, stripe));
	// Luz em dois degraus (toon) pelo sol + a faixa clareia, o vão escurece.
	float lit = step(0.0, dot(world_normal, normalize(sun_direction)) * (FRONT_FACING ? 1.0 : -1.0) + 0.15);
	vec3 col = mix(shade_color, light_color, max(band * 0.85, lit * 0.35 + band * lit * 0.65));
	// Miolo escuro visto por dentro da boca.
	col *= FRONT_FACING ? 1.0 : 0.72;
	col += vec3(0.85, 0.95, 1.0) * flash * band;
	ALBEDO = col * mix(1.0, 0.36, night);
	// Boca: as faixas viram fitas soltas e rasgadas acima de ~80% da altura.
	float tear = smoothstep(0.78, 0.98, h + (n - 0.5) * 0.25) * mouth_tear;
	float fill = mix(1.0, band, max(gaps, tear));
	// Toca o mar com um fade curtinho.
	fill *= smoothstep(0.0, 0.025, h) * (1.0 - smoothstep(1.02, 1.12, h));
	ALPHA = fill * opacity;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
