shader_type spatial;
render_mode cull_back, depth_draw_always, diffuse_toon, specular_schlick_ggx, world_vertex_coords;

// Patch local de alta resolução que acompanha o barco (estilo mar plano do
// Seagazer, mas curvado sobre a esfera). Aqui as ondas Gerstner deslocam a
// geometria de verdade; o deslocamento vai a zero antes da borda, onde o patch
// encontra a esfera sem deformação.

#include "res://Shaders/ocean_waves.gdshaderinc"

varying vec3 rest_position;
varying vec3 surface_position;
varying float patch_distance;

void vertex() {
	vec3 p = normalize(VERTEX) * planet_radius;
	patch_distance = distance(p, patch_center);
	float fade = 1.0 - smoothstep(patch_radius * 0.5, patch_radius * 0.88, patch_distance);
	float h;
	vec3 disp;
	vec3 grad;
	float crest;
	float ripple_glow;
	ocean_eval(p, -1.0, h, disp, grad, crest, ripple_glow);
	rest_position = p;
	VERTEX = normalize(p) * (planet_radius + h * fade) + disp * fade;
	surface_position = normalize(VERTEX) * planet_radius;
}

void fragment() {
	if (patch_distance > patch_radius * 0.97) {
		discard;
	}
	vec3 p = rest_position;
	// O casco ocupa a posição deslocada da água, não a de repouso.
	if (hull_cutout(surface_position) > 0.5) {
		discard;
	}
	float h;
	vec3 disp;
	vec3 grad;
	float crest;
	float ripple_glow;
	ocean_eval(p, length(VERTEX), h, disp, grad, crest, ripple_glow);
	vec3 normal_world = ocean_normal(p, grad, crest);
	NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
	float shore = shore_foam_from_depth(texture(depth_texture, SCREEN_UV).r, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX);
	float foam;
	ALBEDO = ocean_albedo(p, h, crest, ripple_glow, shore, foam);
	ROUGHNESS = mix(0.22, 0.85, foam);
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
