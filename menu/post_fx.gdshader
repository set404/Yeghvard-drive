shader_type canvas_item;
// Full-screen pass over the finished 3D image, drawn under the HUD:
// a contrast-adaptive sharpen (undoes the softness of TAA / upscaling),
// a gentle warm grade and a vignette.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float sharpness : hint_range(0.0, 1.0) = 0.4;
uniform float vignette : hint_range(0.0, 1.0) = 0.3;
uniform vec3 tint = vec3(1.02, 1.0, 0.97);

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 n = textureLod(screen_tex, SCREEN_UV + vec2(0.0, -px.y), 0.0).rgb;
	vec3 s = textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), 0.0).rgb;
	vec3 e = textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), 0.0).rgb;
	vec3 w = textureLod(screen_tex, SCREEN_UV + vec2(-px.x, 0.0), 0.0).rgb;

	// Sharpen less where there is already strong contrast, so edges don't ring.
	vec3 lo = min(c, min(min(n, s), min(e, w)));
	vec3 hi = max(c, max(max(n, s), max(e, w)));
	vec3 amount = sqrt(clamp(min(lo, 1.0 - hi) / max(hi, 1e-4), 0.0, 1.0)) * sharpness;
	vec3 col = clamp(c + (4.0 * c - n - s - e - w) * amount * 0.25, lo, hi);

	col *= tint;
	vec2 d = (SCREEN_UV - 0.5) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	col *= mix(1.0, smoothstep(0.95, 0.25, length(d)), vignette);
	COLOR = vec4(col, 1.0);
}
