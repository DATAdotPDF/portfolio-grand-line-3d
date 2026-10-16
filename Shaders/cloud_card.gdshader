shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

// Nuvem de tempestade em cartões (técnica do Sea of Thieves; textura nossa, gerada no
// Blender por Tools/bake_cloud_atlas.py). Cada cartão mostra um tufo volumétrico "assado" com
// três luzes: R = sol da direita, G = de cima, B = da esquerda; A = densidade.
// Aqui misturamos as três conforme o sol visto da câmera, então o tufo parece iluminado de
// verdade de qualquer ângulo. Cor da instância (StormCell.gd):
//   r = variante (0..15)/16, g = altura relativa (0 base .. 1 topo), b = espelha (0/1), a = opacidade.

uniform sampler2D atlas : repeat_disable, filter_linear_mipmap;
uniform float grid = 4.0;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);   // para onde a luz VAI (como DirectionalLight)
uniform vec3 sun_color : source_color = vec3(1.0);
uniform vec3 lit_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 shade_color : source_color = vec3(0.42, 0.47, 0.55);
uniform vec3 base_color : source_color = vec3(0.16, 0.18, 0.22);
uniform float badness = 2.0;
uniform float night = 0.0;
uniform float flash = 0.0;
uniform float near_fade = 40.0;

varying vec4 card;
varying float view_dist;

void vertex() {
	card = COLOR;
	// Billboard: o cartão encara a câmera mantendo a escala da instância.
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y, INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float index = floor(card.r * 16.0 + 0.5);
	vec2 cell = vec2(mod(index, grid), floor(index / grid));
	vec2 uv = UV;
	if (card.b > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	vec4 tex = texture(atlas, (cell + uv) / grid);
	// Sol na tela: de onde a luz VEM, em espaço de câmera.
	vec3 from_sun = normalize((VIEW_MATRIX * vec4(-sun_direction, 0.0)).xyz);
	float sx = card.b > 0.5 ? -from_sun.x : from_sun.x;
	float right = max(sx, 0.0);
	float left = max(-sx, 0.0);
	float top = max(from_sun.y, 0.0) + 0.35;  // sempre um pouco de luz de cima
	float lit = (tex.r * right + tex.g * top + tex.b * left) / (right + left + top);
	lit = clamp(lit * 1.35, 0.0, 1.0);
	// Contraluz (sol atrás da nuvem): bordas finas brilham.
	float back = max(-from_sun.z, 0.0);
	float rim = (1.0 - smoothstep(0.15, 0.6, tex.a)) * back;
	// Base escura e reta, topo branco; quanto pior a tempestade, mais escura a base.
	float height = card.g;
	vec3 shadow = mix(base_color * mix(1.2, 0.75, clamp(badness / 4.0, 0.0, 1.0)), shade_color, smoothstep(0.0, 0.55, height));
	vec3 col = mix(shadow, lit_color * sun_color, lit * mix(0.55, 1.0, height));
	col += sun_color * rim * 0.5;
	col *= mix(1.0, 0.35, night);
	col += vec3(0.16, 0.2, 0.3) * night * lit * height;
	col += vec3(0.35, 0.63, 0.96) * flash * (0.3 + 0.7 * lit);
	ALBEDO = col;
	float alpha = tex.a * card.a;
	// Tufos das camadas de cima: a base reta deles some aos poucos (fundem nos de baixo, sem corte).
	float upper = smoothstep(0.3, 0.45, card.g);
	alpha *= mix(1.0, 1.0 - smoothstep(0.5, 0.67, UV.y), upper);
	alpha *= smoothstep(near_fade * 0.5, near_fade * 1.5, view_dist);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
