shader_type spatial;
render_mode cull_back, depth_draw_always, diffuse_toon, specular_toon;

uniform float planet_radius = 200.0;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 deep_ocean_color : source_color = vec3(0.015, 0.29, 0.53);
uniform vec3 shallow_ocean_color : source_color = vec3(0.04, 0.61, 0.75);
uniform vec3 foam_color : source_color = vec3(0.91, 0.98, 1.0);
uniform float wave_strength = 3.0;
uniform float wavelength_scale = 1.0;
uniform float wave_speed = 1.0;
uniform vec3 wind_direction = vec3(0.9, 0.15, 0.3);
uniform float swell_foam_threshold : hint_range(0.0, 5.0) = 3.1;
uniform float swell_foam_amount : hint_range(0.0, 1.0) = 0.16;
uniform float ocean_time = 0.0;
uniform bool use_simulation_time = false;
uniform float shoreline_width = 1.2;
uniform vec4 ripple_points[20];
uniform int ripple_count = 0;
uniform vec4 wake_points[24];
uniform int wake_count = 0;
uniform vec3 boat_position;
uniform vec3 boat_forward;
uniform vec3 boat_right;
uniform bool boat_cutout_enabled = false;
uniform vec3 island_centers[5];
uniform float island_radii[5];

const vec3 DIR_1 = vec3(0.866, 0.0, 0.5);
const vec3 DIR_2 = vec3(-0.5, 0.707, 0.5);
const vec3 DIR_3 = vec3(-0.3, -0.6, 0.74);
const vec3 DIR_4 = vec3(0.43, -0.27, -0.86);

varying vec3 radial_direction;
varying float wave_height;

float wave_component(
	vec3 point,
	vec3 direction,
	float amplitude,
	float wavelength,
	float phase_offset,
	inout vec3 height_gradient
) {
	vec3 travel = normalize(direction);
	float wave_number = TAU / max(wavelength * wavelength_scale, 0.1);
	float omega = sqrt(9.8 * wave_number);
	float wave_time = use_simulation_time ? ocean_time : TIME;
	float wave_phase = wave_number * dot(point, travel) - omega * wave_time * wave_speed + phase_offset;
	float crest_base = 0.5 + 0.5 * sin(wave_phase);
	float crest_shape = pow(crest_base, 2.4);
	float derivative = 1.2 * pow(max(crest_base, 0.0001), 1.4)
		* cos(wave_phase) * wave_number;
	height_gradient += amplitude * derivative * travel;
	return amplitude * (crest_shape - 0.37);
}

float ripple_height(vec3 point) {
	float result = 0.0;
	for (int i = 0; i < ripple_count; i++) {
		float age = ripple_points[i].w;
		float distance_from_ring = distance(point, ripple_points[i].xyz) - age * 2.4;
		result += 0.12 * cos(distance_from_ring * 4.0)
			* exp(-distance_from_ring * distance_from_ring / 1.44)
			* (1.0 - age / 4.0) * smoothstep(0.0, 0.15, age);
	}
	return result;
}

float coast_wave_factor(vec3 point) {
	float factor = 1.0;
	for (int index = 0; index < 5; index++) {
		if (island_radii[index] > 0.0) {
			float chord = distance(point, island_centers[index] * planet_radius);
			factor = min(factor, smoothstep(
				island_radii[index] * 0.6,
				island_radii[index] + 12.0,
				chord
			));
		}
	}
	return mix(0.08, 1.0, factor);
}

void vertex() {
	vec3 radial = normalize(VERTEX);
	vec3 point = radial * planet_radius;
	vec3 height_gradient = vec3(0.0);
	float height = 0.0;
	height += wave_component(point, DIR_1, 1.55, 54.0, 0.0, height_gradient);
	height += wave_component(point, DIR_2, 0.18, 32.0, 1.7, height_gradient);
	height += wave_component(point, DIR_3, 0.07, 19.0, 3.8, height_gradient);
	height += wave_component(point, DIR_4, 0.03, 11.0, 5.1, height_gradient);
	height *= wave_strength;
	height_gradient *= wave_strength;
	float coast_factor = coast_wave_factor(point);
	height *= coast_factor;
	height_gradient *= coast_factor;
	height += ripple_height(point);

	VERTEX = radial * (planet_radius + height);
	vec3 tangent_gradient = height_gradient - radial * dot(height_gradient, radial);
	NORMAL = normalize(radial - tangent_gradient * 0.9);
	radial_direction = radial;
	wave_height = height;
}

void fragment() {
	vec3 point = normalize(radial_direction) * planet_radius;
	if (boat_cutout_enabled) {
		vec3 from_boat = point - boat_position;
		vec2 hull = vec2(
			dot(from_boat, boat_forward) / 1.72,
			dot(from_boat, boat_right) / 0.62
		);
		if (dot(hull, hull) < 1.0) {
			discard;
		}
	}

	float height_tint = smoothstep(-2.2, 3.3, wave_height);
	vec3 ocean_color = mix(deep_ocean_color, shallow_ocean_color, height_tint);
	float open_sea_foam = smoothstep(
		swell_foam_threshold,
		swell_foam_threshold + 0.6,
		wave_height
	) * swell_foam_amount;

	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	float clip_depth;
	float has_geometry;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	clip_depth = raw_depth * 2.0 - 1.0;
	has_geometry = 1.0 - step(0.9999, raw_depth);
#else
	clip_depth = raw_depth;
	has_geometry = step(0.0001, raw_depth);
#endif
	vec4 terrain_view = INV_PROJECTION_MATRIX * vec4(
		SCREEN_UV * 2.0 - 1.0,
		clip_depth,
		1.0
	);
	terrain_view.xyz /= terrain_view.w;
	float gap = max(0.0, -terrain_view.z + VERTEX.z);
	float shoreline_foam =
		(1.0 - smoothstep(0.04, shoreline_width, gap)) * has_geometry;

	float wake_foam = 0.0;
	for (int i = 0; i < wake_count - 1; i++) {
		vec3 start = wake_points[i].xyz;
		vec3 segment = wake_points[i + 1].xyz - start;
		float along = clamp(
			dot(point - start, segment) / max(dot(segment, segment), 0.001),
			0.0,
			1.0
		);
		float life = mix(wake_points[i].w, wake_points[i + 1].w, along);
		float distance_to_wake = length(point - start - segment * along);
		float width = 0.45 + (1.0 - life) * 1.7;
		wake_foam = max(
			wake_foam,
			(1.0 - smoothstep(width * 0.2, width, distance_to_wake)) * life
		);
	}

	float foam = max(open_sea_foam, max(shoreline_foam, wake_foam * 0.7));
	ALBEDO = mix(ocean_color, foam_color, clamp(foam, 0.0, 0.98));
	ROUGHNESS = mix(0.5, 0.82, foam);
	METALLIC = 0.0;
	SPECULAR = 0.14;
	ALPHA = 1.0;
}
