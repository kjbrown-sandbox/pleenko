shader_type canvas_item;

// Backdrop blur for modal overlays. Reads the already-rendered screen
// (everything below this node, captured into the back buffer) and blurs it,
// then darkens toward `tint_color` so the panel on top still reads as modal.
// `fade` drives the whole reveal 0->1 (tweened by FrostedOverlay) — a plain
// modulate:a fade does NOT work because this shader overwrites COLOR.a.
uniform sampler2D screen_texture: hint_screen_texture, repeat_disable, filter_linear;
uniform float blur_size: hint_range(0.0, 30.0) = 8.0;
uniform vec4 tint_color: source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float tint_strength: hint_range(0.0, 1.0) = 0.6;
uniform float fade: hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 texel = 1.0 / vec2(textureSize(screen_texture, 0));

	// 5×5 Gaussian kernel (sigma ≈ 1.5, sum = 273)
	float weights[25] = float[25](
		 1.0,  4.0,  7.0,  4.0,  1.0,
		 4.0, 16.0, 26.0, 16.0,  4.0,
		 7.0, 26.0, 41.0, 26.0,  7.0,
		 4.0, 16.0, 26.0, 16.0,  4.0,
		 1.0,  4.0,  7.0,  4.0,  1.0
	);

	vec4 blurred = vec4(0.0);
	float total = 0.0;
	for (int y = 0; y < 5; y++) {
		for (int x = 0; x < 5; x++) {
			float w = weights[y * 5 + x];
			vec2 offset = vec2(float(x) - 2.0, float(y) - 2.0) * texel * blur_size;
			blurred += texture(screen_texture, uv + offset) * w;
			total += w;
		}
	}
	blurred /= total;

	// Vibrancy: mild saturation boost so colors bleed through attractively.
	float lum = dot(blurred.rgb, vec3(0.2126, 0.7152, 0.0722));
	blurred.rgb = mix(vec3(lum), blurred.rgb, 1.1);

	// Darkened frost: pull toward the theme dim color so the screen still reads
	// as dimmed/modal behind the panel.
	blurred.rgb = mix(blurred.rgb, tint_color.rgb, tint_strength);

	COLOR = vec4(blurred.rgb, fade);
}
