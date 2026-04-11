shader_type spatial;
render_mode unshaded, blend_add, cull_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform float opacity_mult = 1.0;

void fragment() {
	float dist = length(UV - vec2(0.5)) * 2.0;  // 0 at center, 1 at edge
	float falloff = exp(-dist * dist * 2.0);     // soft gaussian — spreads across quad
	float circle = 1.0 - smoothstep(0.3, 1.0, dist);  // gradual fade to quad edge
	float alpha = falloff * circle * opacity_mult;
	ALBEDO = glow_color.rgb;
	ALPHA = alpha * glow_color.a;
}
