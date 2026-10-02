shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Bolha de nuvem toon (referência Seagazer / Wind Waker): topo claro, base
// lavanda, borda iluminada. Sem iluminação real: barata no Compatibility/mobile.

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 light_color : source_color = vec3(1.0, 0.99, 0.96);
uniform vec3 shade_color : source_color = vec3(0.74, 0.76, 0.92);
uniform vec3 night_light : source_color = vec3(0.26, 0.31, 0.48);
uniform vec3 night_shade : source_color = vec3(0.12, 0.15, 0.28);
uniform float daylight = 1.0;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float lit = smoothstep(-0.25, 0.35, dot(n, normalize(sun_direction)));
	// Bandas suaves (toon) em vez de gradiente contínuo.
	lit = (floor(lit * 3.0) + smoothstep(0.4, 0.6, fract(lit * 3.0))) / 3.0;
	vec3 light = mix(night_light, light_color, daylight);
	vec3 shade = mix(night_shade, shade_color, daylight);
	vec3 color = mix(shade, light, lit);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = color + rim * 0.12 * daylight;
}
