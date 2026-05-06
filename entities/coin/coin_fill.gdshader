shader_type spatial;
render_mode unshaded;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 0.0, 1.0);
// 0.0 = fully transparent (empty), 1.0 = fully opaque (complete coin)
uniform float fill_progress : hint_range(0.0, 1.0) = 0.0;

varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
}

void fragment() {
	// Use model-space X/Z of the vertex to compute the radial angle.
	// CylinderMesh is oriented along Y; caps are in the XZ plane.
	// The mesh is rotated PI/2 on X by the coin, but VERTEX is pre-rotation.
	float angle = atan(-model_pos.x, model_pos.z); // 0 at top (+Z), clockwise
	// Normalize to [0, 1]
	float normalized = (angle + PI) / TAU;
	if (normalized > fill_progress) {
		discard;
	}
	ALBEDO = albedo_color.rgb;
}
