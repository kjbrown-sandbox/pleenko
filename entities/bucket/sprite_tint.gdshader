shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;

uniform vec4 tint_color : source_color = vec4(1.0);
uniform sampler2D icon_texture : source_color;

void fragment() {
    vec4 tex = texture(icon_texture, UV);
    ALBEDO = tint_color.rgb;
    ALPHA = tex.a;
}
