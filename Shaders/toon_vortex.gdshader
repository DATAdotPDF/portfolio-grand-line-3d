shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

// Vórtice de nuvens em toon (estudo do Thiago Muniz: anel de nuvem que se fecha em espiral, com
// bordas rasgadas e duas cores chapadas). Usado no céu do kraken e no topo do tornado.
// Malha em anel: UV.x = ângulo (0..1), UV.y = raio relativo (0 centro .. 1 borda).

uniform float eye = 0.3;           // raio do "olho" aberto no meio (0..1); diminui = fecha
uniform float strength = 1.0;      // aparece/some
uniform float spin = 0.25;         // giro (voltas por segundo × 2π)
uniform float twist = 5.0;         // quanto a espiral torce para dentro
uniform vec3 light_color : source_color = vec3(0.42, 0.48, 0.55);
uniform vec3 dark_color : source_color = vec3(0.14, 0.17, 0.22);
uniform vec3 rim_color : source_color = vec3(0.7, 0.25, 0.22);  // borda do olho (avermelhada no kraken)
uniform float rim_amount = 0.0;
uniform float night = 0.0;
uniform float rips = 1.0;          // 0 = disco cheio (nuvem do tornado), 1 = rasgos de céu
uniform float form = 1.0;          // 0..1: a nuvem se forma juntando pedaços (dissolve)
uniform float flash = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0, 0.3, 0.25);

// Curva o disco junto com o planeta (sem isso as bordas de um disco grande e chato ficavam
// cortadas/descoladas do céu). 0 = não curva (disco do tornado, pequeno).
uniform float sphere_radius = 0.0;

void vertex() {
	if (sphere_radius > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		wp = normalize(wp) * sphere_radius;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	}
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 3.7) * 0.3 + vnoise(p * 4.3 + 7.1) * 0.15;
}

// Ruído sem costura em volta do disco: o ângulo vai de 0 a 2π no UV.x e o fbm não se repete, então
// em 0°/360° o desenho pulava e aparecia uma linha. Mistura a leitura com a de uma volta antes.
float wrap_fbm(vec2 p, float turn, float u) {
	return mix(fbm(p), fbm(p - vec2(turn, 0.0)), u);
}

void fragment() {
	float r = max(UV.y, 0.001);
	float a = UV.x * 6.2831853;
	float t = TIME * spin;
	// Coordenadas em espiral (log-polar torcido): os rasgos convergem para o olho.
	// Giro rígido: girar mais rápido no centro "enrola" a espiral com o tempo em anéis.
	float arm = a + log(r) * twist - t;
	// Blocos grandes de nuvem (pouca frequência no raio): espiral solta, sem anéis concêntricos.
	vec2 sp = vec2(arm * 1.3, r * 1.4);
	float u = UV.x;
	float turn = 6.2831853 * 1.3;
	float cloud = wrap_fbm(sp + vec2(0.0, t * 0.2), turn, u);
	// Borda de fora rasgada e olho com contorno irregular.
	float outer = smoothstep(1.0, 0.7, r + (cloud - 0.5) * 0.3);
	float inner = smoothstep(eye, eye + 0.06, r + (cloud - 0.5) * 0.12);
	float mask = outer * inner;
	// Duas cores chapadas (limiar), com faixas claras rasgadas correndo em espiral.
	float band = step(0.5, wrap_fbm(sp * vec2(1.4, 1.0) + 11.0, turn * 1.4, u));
	vec3 col = mix(dark_color, light_color, band);
	// Contorno do olho (brilho avermelhado no kraken).
	float rim = (1.0 - smoothstep(0.0, 0.08, r - eye)) * inner * rim_amount;
	col = mix(col, rim_color, rim);
	col *= mix(1.0, 0.5, night);
	col += flash_color * flash * 0.6 * band;
	// Rasgos: o limiar abre buracos de céu dentro da nuvem.
	float holes = mix(1.0, step(0.3, cloud), rips);
	// Formação: pedaços soltos que se juntam até o anel ficar inteiro.
	float formed = step(1.0 - form, wrap_fbm(sp * 0.7 + 21.0, turn * 0.7, u) * 0.6 + 0.4 * (1.0 - abs(r - 0.6) * 2.0));
	ALBEDO = col;
	ALPHA = mask * holes * formed * strength * 0.95;
}
