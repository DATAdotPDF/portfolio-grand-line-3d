shader_type spatial;
render_mode cull_back, depth_draw_always, diffuse_toon, specular_schlick_ggx;

// Esfera do oceano vista de longe. A geometria NUNCA é deformada (sem "bola de
// gelatina"): as ondas entram só como normal e cor no fragment. Perto do barco
// o OceanPatch assume com deslocamento real e esta esfera é descartada ali.

#include "res://Shaders/ocean_waves.gdshaderinc"

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = normalize(world_position) * planet_radius;
	if (patch_radius > 0.0 && distance(p, patch_center) < patch_radius * 0.95) {
		discard;
	}
	if (hull_cutout(p) > 0.5) {
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
	vec3 albedo = ocean_albedo(p, h, crest, ripple_glow, shore, foam);
	vec3 emission;
	ocean_finish(p, NORMAL, VIEW, foam, albedo, emission);
	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = mix(0.22, 0.85, foam);
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
