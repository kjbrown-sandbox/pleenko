shader_type canvas_item;
render_mode blend_add;

uniform float time_offset = 0.0;
uniform float intensity = 0.0;
uniform float band_width : hint_range(0.01, 1.0) = 0.18;
uniform vec4 highlight_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	float sweep_pos = fract(time_offset);
	float dist = abs(UV.x - sweep_pos);
	float band = smoothstep(band_width, 0.0, dist);
	COLOR = vec4(highlight_color.rgb * band * intensity, 1.0);
}
