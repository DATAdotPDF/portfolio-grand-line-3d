shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;
void fragment() {
	float rim=pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),3.5);
	ALBEDO=mix(vec3(0.72,0.88,0.98),vec3(1.0,0.92,0.7),rim);
	ALPHA=0.008+0.11*rim;
}
