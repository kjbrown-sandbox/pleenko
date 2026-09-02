shader_type canvas_item;

// Screen-space shockwave distortion. Applied to a full-screen ColorRect.
// Warps pixels in an expanding ring around a center point.
//
// The optional tint is additive to that behaviour: `color_strength` defaults to
// 0.0, so with default uniforms the output is bit-identical to the original
// pure-refraction ring (mix(x, y, 0.0) == x). The tint is applied INSIDE the
// ring band and scaled by the same `intensity` falloff, so raising the strength
// colours the ring itself rather than washing the whole screen.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius = 0.0;
uniform float ring_width = 0.08;
uniform float distortion_strength = 0.02;
uniform vec4 ring_color : source_color = vec4(1.0);
uniform float color_strength = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float dist = distance(uv, center);

	float ring_dist = abs(dist - radius);
	float intensity = 0.0;
	if (ring_dist < ring_width) {
		intensity = 1.0 - (ring_dist / ring_width);
		intensity *= intensity;

		vec2 dir = normalize(uv - center);
		uv -= dir * distortion_strength * intensity;
	}

	vec4 sampled = texture(screen_texture, uv);
	sampled.rgb = mix(sampled.rgb, ring_color.rgb, color_strength * intensity);
	COLOR = sampled;
}
