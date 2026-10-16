shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

// Camada por cima das lanternas do bioma fantasma (WorldDecor.gd, material_overlay): o mesmo
// verde do navio fantasma nas bordas (fresnel), pulsando devagar. Soma à textura do modelo.

uniform vec3 glow_color : source_color = vec3(0.35, 1.0, 0.6);
uniform float strength = 1.0;
uniform float phase = 0.0;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float pulse = 0.8 + 0.2 * sin(TIME * 1.7 + phase);
	ALBEDO = glow_color * (0.1 + fresnel * 0.85) * pulse * strength;
}
