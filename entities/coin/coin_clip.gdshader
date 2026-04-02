shader_type spatial;
render_mode unshaded;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 0.0, 1.0);
// World-space Y below which fragments are discarded. Defaults to very low so no clipping occurs.
uniform float clip_y = -9999.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (world_position.y < clip_y) {
		discard;
	}
	ALBEDO = albedo_color.rgb;
}
