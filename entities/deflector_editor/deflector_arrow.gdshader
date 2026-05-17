shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// Isosceles triangle with ONLY the apex (point) rounded — the flat base and
// its two corners (the side next to the peg) stay sharp. Apex points +Y in the
// quad's local space; the editor rotates the quad ±90° to aim it left/right.
//
// Built as the intersection of three half-planes (sharp everywhere), then the
// apex — the corner where the two slanted sides meet — is rounded by `r`.
// Worked in WORLD units (tri_size = (base, length)) so proportions and the
// rounding radius stay correct regardless of the quad's aspect ratio.

uniform vec4 tint_color : source_color = vec4(1.0);
uniform vec2 tri_size = vec2(0.16, 0.32);
uniform float corner_radius : hint_range(0.0, 0.1) = 0.03;

void fragment() {
	vec2 p = (vec2(UV.x, 1.0 - UV.y) - 0.5) * tri_size;
	// Small inset so the rounded apex never clips the quad edge / AA.
	float hb = tri_size.x * 0.5 * 0.94;   // half base
	float hl = tri_size.y * 0.5 * 0.94;   // half length
	float r = corner_radius;

	vec2 apex = vec2(0.0, hl);
	// Outward normals of the two slanted edges (edge dir = base_corner - apex).
	vec2 nR = normalize(vec2(2.0 * hl, hb));
	vec2 nL = normalize(vec2(-2.0 * hl, hb));
	float dR = dot(nR, p - apex);          // >0 outside the right edge
	float dL = dot(nL, p - apex);          // >0 outside the left edge
	float dB = -(p.y + hl);                // >0 below the (sharp) base line

	// Round ONLY the apex, without moving the side edges: push the two side
	// half-planes inward by r, take their (sharp) intersection, then expand
	// back out by r. Net = edges in their original place, apex filleted by r.
	float aL = dL + r;
	float aR = dR + r;
	float m = max(aL, aR);
	float apex_corner = length(max(vec2(aL, aR), vec2(0.0))) + min(m, 0.0) - r;
	// Sharp base clipped in with a plain max → base + its corners stay crisp.
	float d = max(dB, apex_corner);

	float aa = fwidth(d);
	float alpha = 1.0 - smoothstep(0.0, aa, d);
	if (alpha <= 0.001) {
		discard;
	}
	ALBEDO = tint_color.rgb;
	ALPHA = alpha * tint_color.a;
}
