shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

// Silhuetas de animais sob a água (SeaShadows.gd / SeaLife.gd): uma placa grudada na superfície
// (segue as ondas pela mesma conta do mar) com a silhueta do atlas
// (Assets/SeaLife/sea_shadows_atlas.png, feito por Tools/bake_sea_shadow_atlas.py a partir das
// texturas do Meshy). Para parecer EMBAIXO d'água e não pintada em cima:
// - as cristas e a espuma das ondas cobrem a silhueta (passam por cima dela);
// - some de lado (fresnel: de longe e rasante a água reflete o céu e esconde o fundo);
// - borda borrada e um tremor de refração; reflexos de luz (cáusticas) correndo por cima;
// - a cor é a do mar escurecido, não preto.
// UV.x = largura (0..1), UV.y = comprimento (0 cabeça .. 1 cauda).
// kind = célula do atlas (4 × 2): 0 tubarão, 1 arraia, 2 baleia, 3 tubarão-baleia, 4 kraken,
// 5 foca, 6 golfinho.

#include "res://Shaders/ocean_waves.gdshaderinc"

uniform int kind = 0;
uniform sampler2D shadow_atlas : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform float swim = 0.0;        // fase do nado (acumulada na CPU)
uniform float opacity = 0.0;     // aparece/some (sobe do fundo / mergulha)
uniform float wiggle = 1.0;      // força do serpentear (golfinho e foca mais)
uniform float flap = 0.0;        // arraia: batida de asa (0..1), "voo" debaixo d'água
uniform float glow = 0.0;        // bioluminescência (arraias à noite)
uniform float curve = 0.0;       // curvatura do corpo na curva (−1..1): o corpo vira um "C"
uniform float roll = 0.0;        // giro em volta do próprio eixo (0..1): de cima, o corpo afina
uniform vec3 shadow_color : source_color = vec3(0.02, 0.2, 0.28);
uniform vec3 glow_color : source_color = vec3(0.25, 0.95, 0.9);

varying float v_crest;
varying vec3 v_world;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 p = normalize(wp) * planet_radius;
	float h;
	vec3 disp;
	vec3 grad;
	float crest;
	float glow_r;
	ocean_eval(p, -1.0, h, disp, grad, crest, glow_r);
	float fade = patch_radius > 0.0 ? 1.0 - smoothstep(patch_radius * 0.5, patch_radius * 0.88, distance(p, patch_center)) : 0.0;
	wp = normalize(p) * (planet_radius + h * fade + 0.06) + disp * fade;
	v_crest = crest * fade;
	v_world = wp;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
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

void fragment() {
	vec2 q = vec2(UV.x - 0.5, UV.y);       // x lateral (−0,5..0,5), y 0 cabeça .. 1 cauda
	// Serpentear do nado: mais para a cauda.
	float bend = sin(swim - q.y * 5.0) * 0.06 * q.y * q.y * wiggle;
	if (kind == 1) {
		// Arraia "voando": as asas sobem e descem (de cima, a envergadura encolhe e abre) e a
		// onda corre da frente para trás das pontas.
		float beat = sin(swim * 0.7 - abs(q.x) * 3.0 - q.y * 1.5);
		q.x /= 1.0 + beat * 0.22 * flap * smoothstep(0.05, 0.45, abs(q.x) * 2.0);
		bend *= 0.2;
	}
	q.x -= bend;
	// Na curva o corpo inteiro arqueia (cabeça e cauda para o lado de fora), como um bicho mole.
	q.x -= curve * (q.y - 0.42) * (q.y - 0.42) * 0.9;
	// Rolando de lado: visto de cima a silhueta afina (nadadeiras de perfil).
	q.x /= mix(1.0, 0.5, roll);
	// Refração: a água entre o bicho e o olho entorta um pouco a silhueta.
	vec2 wob = vec2(vnoise(v_world.xz * 0.35 + TIME * 0.6), vnoise(v_world.zx * 0.35 - TIME * 0.5)) - 0.5;
	q += wob * 0.018;
	vec2 uv = clamp(vec2(q.x + 0.5, q.y), vec2(0.004), vec2(0.996));
	vec2 cell = vec2(float(kind % 4), float(kind / 4));
	vec2 atlas_uv = (cell + uv) * vec2(0.25, 0.5);
	// Borda borrada: mipmap mais alto (como visto através de meio metro de água).
	float m = texture(shadow_atlas, atlas_uv, 1.0).r;
	float core = texture(shadow_atlas, atlas_uv, 2.5).r;
	float a = smoothstep(0.08, 0.55, m) * mix(0.5, 0.72, core) * opacity;
	// Cristas e espuma passam por cima da silhueta.
	a *= 1.0 - smoothstep(0.2, 0.9, v_crest) * 0.5;
	// Rasante: a superfície reflete o céu e esconde um pouco o fundo (a câmera do jogo é baixa:
	// não pode apagar demais).
	float facing = abs(dot(normalize(NORMAL), VIEW));
	a *= mix(0.72, 1.0, smoothstep(0.05, 0.5, facing));
	// Cáusticas: veios claros de luz correndo por cima do corpo.
	vec2 cp = v_world.xz * 0.9 + vec2(TIME * 0.35, -TIME * 0.27);
	float caustic = smoothstep(0.62, 0.9, vnoise(cp) * 0.6 + vnoise(cp * 2.1 + 3.0) * 0.4);
	a *= 1.0 - caustic * 0.22;
	vec3 col = shadow_color;
	// Bioluminescência: contorno e pintas que acendem em ondas.
	float rim = clamp(m - core * 1.1, 0.0, 1.0) * 2.5;
	float spots = smoothstep(0.7, 0.95, vnoise(uv * vec2(18.0, 28.0) + swim * 0.1)) * core;
	float pulse = 0.65 + 0.35 * sin(TIME * 1.7 - q.y * 6.0);
	float lum = (rim + spots + core * 0.25) * glow * pulse;
	col = mix(col, glow_color * 1.8, clamp(lum, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(a + lum * opacity * 0.9, 0.0, 0.95);
}
