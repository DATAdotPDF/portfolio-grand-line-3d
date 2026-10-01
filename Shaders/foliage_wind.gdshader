shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float root_height = 0.2;
uniform float tree_height = 0.7;
void vertex() {
 vec3 paint=textureLod(albedo_map,UV,0.0).rgb;
 float leaf=smoothstep(0.035,0.12,paint.g-max(paint.r,paint.b)*0.9);
 float anchor=pow(clamp((VERTEX.y-root_height)/tree_height,0.0,1.0),2.0)*leaf;
 VERTEX.x+=sin(TIME*1.6+VERTEX.z*5.0)*0.008*anchor;
 VERTEX.z+=sin(TIME*1.1+VERTEX.x*4.0)*0.005*anchor;
}
void fragment() {
 ALBEDO=texture(albedo_map,UV).rgb*tint.rgb;
 ROUGHNESS=0.85;
 SPECULAR=0.2;
}
