shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_disabled;

// Gotícula estilo toon (adaptada de water-wakes/scenes/water_drop.gdshader):
// billboard circular, borda nítida, levemente mais escura no lado de baixo.

uniform vec4 water_color : source_color = vec4(0.88, 0.98, 1.0, 1.0);
uniform vec4 shade_color : source_color = vec4(0.45, 0.78, 0.92, 1.0);
uniform float daylight = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 center_uv = UV - vec2(0.5);
	if (length(center_uv) > 0.48) {
		discard;
	}
	float shade = smoothstep(-0.1, 0.35, center_uv.y);
	ALBEDO = mix(water_color.rgb, shade_color.rgb, shade * 0.6) * COLOR.rgb * mix(0.3, 1.0, daylight);
}
