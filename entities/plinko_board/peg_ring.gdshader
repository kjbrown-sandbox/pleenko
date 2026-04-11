shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float opacity_mult = 1.0;
uniform float ring_radius : hint_range(0.0, 1.0) = 0.0;
uniform float ring_thickness : hint_range(0.0, 0.5) = 0.04;
uniform float ring_softness : hint_range(0.0, 0.5) = 0.03;

void fragment() {
	float dist = length(UV - vec2(0.5)) * 2.0;
	float edge_dist = abs(dist - ring_radius);
	float ring = 1.0 - smoothstep(ring_thickness, ring_thickness + ring_softness, edge_dist);
	ALBEDO = ring_color.rgb;
	ALPHA = ring * ring_color.a * opacity_mult;
}
