shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 tint_color : source_color = vec4(1.0);
uniform sampler2D icon_texture : source_color, filter_nearest;

void fragment() {
	vec4 tex = texture(icon_texture, UV);
	if (tex.a < 0.1) {
		discard;
	}
	ALBEDO = tint_color.rgb;
	ALPHA = tex.a;
}
