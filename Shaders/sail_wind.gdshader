shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform float bottom;
uniform float height;
uniform float wind_strength=0.085;
uniform sampler2D jolly_roger : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 wind_direction=vec3(1.0,0.0,0.0);
uniform float boat_speed=0.0;
varying vec3 sail_rest;
void vertex() {
	sail_rest=VERTEX;
	vec3 paint=textureLod(albedo_map,UV,0.0).rgb;
	float white=smoothstep(0.38,0.68,min(paint.r,min(paint.g,paint.b)));
	float h=(VERTEX.y-bottom)/height;
	float cloth=white*smoothstep(0.35,0.48,h)*(1.0-smoothstep(0.78,0.88,h));
	cloth *= 1.0-smoothstep(0.05,0.30,VERTEX.x);
	float gust=0.52+0.42*sin(TIME*1.15+VERTEX.z*3.0);
	float flutter=sin(TIME*(5.0+boat_speed*0.14)+VERTEX.z*17.0+VERTEX.y*9.0)*0.012;
	VERTEX+=normalize(wind_direction)*wind_strength*cloth*(gust+flutter);
}
void fragment() {
	vec3 base=texture(albedo_map,UV).rgb;
	// Project onto the main white sail. A Decal cannot render in WebGL 2 Compatibility.
	vec2 emblem_uv=vec2((sail_rest.z+0.32)/0.64,1.0-(sail_rest.y+0.13)/0.52);
	vec2 q=(emblem_uv-vec2(0.5))*2.0;
	float ink_mask=smoothstep(1.0,0.83,length(q));
	ink_mask*=1.0-smoothstep(-0.12,-0.005,sail_rest.x);
	ink_mask*=smoothstep(0.56,0.79,min(base.r,min(base.g,base.b)));
	vec3 ink=texture(jolly_roger,clamp(emblem_uv,vec2(0.0),vec2(1.0))).rgb;
	ALBEDO=mix(base,ink,ink_mask*0.9);
	ROUGHNESS=0.82;
	SPECULAR=0.16;
}
