shader_type spatial;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform float glow=0.5;
void fragment() {
	vec3 paint=texture(albedo_map,UV).rgb;
	float rune=smoothstep(0.28,0.7,paint.g)*smoothstep(0.04,0.22,paint.g-paint.r);
	ALBEDO=mix(vec3(0.035,0.06,0.08),paint,0.65);
	EMISSION=vec3(0.0,0.72,0.9)*rune*glow;
	ROUGHNESS=0.35;
}
