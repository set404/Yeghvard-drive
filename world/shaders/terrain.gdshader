shader_type spatial;

uniform sampler2D ground : source_color, filter_linear_mipmap, repeat_disable;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The ground map is 4 m per pixel; break it up with detail noise up close.
	float n = noise(wpos.xz * 0.21) * 0.5 + noise(wpos.xz * 1.7) * 0.3 + noise(wpos.xz * 9.0) * 0.2;
	ALBEDO = texture(ground, UV).rgb * (0.82 + 0.36 * n);
	ROUGHNESS = 1.0;
}
