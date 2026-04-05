shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.15;
uniform float radius : hint_range(0.0, 1.0) = 0.75;
uniform float softness : hint_range(0.0, 1.0) = 0.45;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	float vignette = smoothstep(radius, radius + softness, dist);
	COLOR = vec4(vignette_color.rgb, vignette * intensity);
}
