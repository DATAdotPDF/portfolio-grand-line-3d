shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float energy=0.0;
varying float travel;
void vertex() { travel=clamp((70.0-VERTEX.y)/140.0,0.0,1.0); }
void fragment() {
	ALBEDO=vec3(1.0,0.85,0.49);
	ALPHA=energy*0.055*pow(1.0-travel,2.0)*(1.0-smoothstep(0.65,0.95,travel))*pow(abs(dot(normalize(NORMAL),normalize(VIEW))),0.6);
}
