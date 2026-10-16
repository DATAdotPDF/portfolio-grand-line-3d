shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

// Redemoinho do ciclone no mar (Cyclone.gd): um disco largo de espuma em espiral, que sobe
// como uma parede de spray abraçando a base do funil. Prende o ciclone ao oceano: cada vértice
// sobe e desce com as mesmas ondas do patch do mar (mesma conta, mesmo enfraquecimento na borda).

#include "res://Shaders/ocean_waves.gdshaderinc"

uniform float swirl_outer_radius = 20.0;
uniform float wall_height = 7.5;
uniform float spin = 1.4;
uniform float arms = 4.0;
uniform float tightness = 3.2;
uniform vec3 water_color : source_color = vec3(0.24, 0.42, 0.46);
uniform vec3 swirl_foam_color : source_color = vec3(0.88, 0.94, 0.95);
uniform float night = 0.0;
uniform float grow = 1.0;
// Células de espuma (textura grátis do tutorial de tornado do Le Lu). Sem mipmap: o atan tem
// um salto na costura e o mipmap marcaria uma linha ali.
uniform sampler2D cells_tex : repeat_enable, filter_linear;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	VERTEX *= grow;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 p = normalize(wp) * planet_radius;
	float lift = length(wp) - planet_radius;
	float h;
	vec3 disp;
	vec3 grad;
	float crest;
	float ripple_glow;
	ocean_eval(p, -1.0, h, disp, grad, crest, ripple_glow);
	// Fora do patch o mar é a esfera lisa, então as ondas somem do mesmo jeito.
	float fade = patch_radius > 0.0 ? 1.0 - smoothstep(patch_radius * 0.5, patch_radius * 0.88, distance(p, patch_center)) : 0.0;
	wp = normalize(p) * (planet_radius + h * fade + lift) + disp * fade;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
}

void fragment() {
	float r = length(local_pos.xz);
	float wall = clamp(local_pos.y / wall_height, 0.0, 1.0);
	// Espiral logarítmica: braços que se enrolam para dentro e giram.
	float a = atan(local_pos.z, local_pos.x) + TIME * spin + log(max(r, 0.5)) * tightness;
	float arm = sin(a * arms) * 0.5 + 0.5;
	vec2 cell_uv = vec2(a / 6.2831853 * 4.0, r * 0.06 + local_pos.y * 0.12 - TIME * 0.15);
	float n = texture(cells_tex, cell_uv).r * 0.7 + arm * 0.45;
	float foam = smoothstep(0.62, 0.7, n + wall * 0.4);
	vec3 col = mix(water_color, swirl_foam_color, foam);
	col *= mix(1.0, 0.35, night);
	float edge = 1.0 - smoothstep(swirl_outer_radius * 0.6, swirl_outer_radius, r);
	float alpha = mix(0.45, 0.95, foam) * edge;
	// Parede de spray: some para cima.
	alpha *= 1.0 - smoothstep(0.55, 1.0, wall);
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
