shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;

// "Usonami" (onda de mentira), estudados no mar do Wind Waker: cartões em pé perto do horizonte
// com a silhueta de uma onda vista de lado. A forma é matemática (é como uma crista se desenha):
//   silhueta  y = (1 - |x|)^1.5      (laterais côncavas subindo até a ponta)
//   corpo     y = 0.61 * (1 - |x|)   (triângulo de lados retos, cor do mar)
//   ponta branca = entre a silhueta e o corpo.
// Os quadrados são montados na CPU (Usonami.gd) já de pé no "para cima" do planeta e virados
// para a câmera. COLOR.a = opacidade (fade de distância/tempestade).

uniform vec3 body_color : source_color = vec3(0.1, 0.45, 0.62);
uniform vec3 tip_color : source_color = vec3(0.93, 0.97, 1.0);
uniform float daylight = 1.0;

varying float fade;

void vertex() {
	fade = COLOR.a;
}

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float y = 1.0 - UV.y;
	float edge = fwidth(y) * 1.5;
	float silhouette = pow(1.0 - x, 1.5);
	float body = 0.61 * (1.0 - x);
	float inside = 1.0 - smoothstep(silhouette - edge, silhouette + edge, y);
	float tip = smoothstep(body - edge, body + edge, y);
	// Corpo semitransparente (pega a cor do mar onde está, seja qual for o tom); ponta branca cheia.
	vec3 col = mix(body_color, tip_color, tip) * mix(0.3, 1.0, daylight);
	ALBEDO = col;
	ALPHA = inside * fade * mix(0.5, 1.0, tip);
}
