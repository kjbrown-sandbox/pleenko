shader_type canvas_item;

// Screen-space shockwave distortion. Applied to a full-screen ColorRect.
// Warps pixels in an expanding ring around a center point.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius = 0.0;
uniform float ring_width = 0.08;
uniform float distortion_strength = 0.02;

void fragment() {
	vec2 uv = SCREEN_UV;
	float dist = distance(uv, center);

	float ring_dist = abs(dist - radius);
	if (ring_dist < ring_width) {
		float intensity = 1.0 - (ring_dist / ring_width);
		intensity *= intensity;

		vec2 dir = normalize(uv - center);
		uv -= dir * distortion_strength * intensity;
	}

	COLOR = texture(screen_texture, uv);
}
