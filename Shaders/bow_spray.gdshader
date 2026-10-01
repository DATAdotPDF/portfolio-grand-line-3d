shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
#include "res://Shaders/ocean_shared.gdshaderinc"
uniform float side = 1.0;
uniform float strength = 0.0;
uniform float turn = 0.0;
varying vec3 surface_point;
varying float lip;

vec3 sheet(vec2 uv) {
	float taper=pow(max(sin(uv.x*3.14159265),0.0),0.65);
	float width=(0.17+sin(uv.x*2.67)*0.65)+uv.y*0.65*strength*taper;
	vec3 base=boat_position+boat_forward*(1.6-uv.x*3.0)+boat_right*side*width;
	vec3 up=normalize(base);
	float bank=clamp(1.0+side*turn*0.28,0.65,1.35);
	float scallop=0.75+0.25*sin(uv.x*18.0-phase.x*2.0);
	float rise=sin(uv.y*2.5)*0.70*strength*taper*bank*scallop-0.14;
	return up*(ocean_radius+water_height(base)+rise);
}
void vertex() {
	VERTEX=sheet(UV);
	vec3 du=sheet(vec2(min(UV.x+0.002,1.0),UV.y))-sheet(vec2(max(UV.x-0.002,0.0),UV.y));
	vec3 dv=sheet(vec2(UV.x,min(UV.y+0.002,1.0)))-sheet(vec2(UV.x,max(UV.y-0.002,0.0)));
	NORMAL=normalize(cross(du,dv));
	surface_point=VERTEX;
	lip=smoothstep(0.66,1.0,UV.y);
}
void fragment() {
	if(inside_hull(surface_point)) discard;
	ALBEDO=mix(water_color(surface_point),foam_color,lip*0.95);
	ROUGHNESS=0.6;
	SPECULAR=0.18;
}
