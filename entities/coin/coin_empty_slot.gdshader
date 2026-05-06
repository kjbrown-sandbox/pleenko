shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 0.25);
uniform float ring_width : hint_range(0.01, 0.2) = 0.08;
uniform int dash_count : hint_range(4, 16) = 8;
uniform float dash_gap : hint_range(0.0, 0.5) = 0.35;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float dist = length(centered);
	// Ring mask: only draw near the edge
	float inner = 1.0 - ring_width;
	if (dist < inner || dist > 1.0) {
		discard;
	}
	// Dash pattern based on angle
	float angle = atan(centered.y, centered.x) + PI; // [0, TAU]
	float segment = angle / TAU * float(dash_count);
	float frac_part = fract(segment);
	if (frac_part > (1.0 - dash_gap)) {
		discard;
	}
	ALBEDO = ring_color.rgb;
	ALPHA = ring_color.a;
}
