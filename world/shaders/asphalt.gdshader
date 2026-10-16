shader_type spatial;

// The parking lot by the supermarket (tools/build_supermarket.gd).
// COLOR.rgb: colour (linear). COLOR.a: 1 asphalt, 0 painted lines.
// UV: metres across the ground.

varying float paint;

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
	paint = 1.0 - COLOR.a;
	// Like the roads: drawn a little nearer the camera along the line of sight,
	// so the terrain just under it does not show through, and the paint nearer
	// still than the asphalt it lies on.
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = length(view.xyz);
	float pull = min((0.04 + 0.004 * dist) * (1.0 + paint), 0.5 * dist);
	view.xyz -= view.xyz / max(dist, 0.001) * pull;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	float n = noise(UV * 0.5) * 0.5 + noise(UV * 5.0) * 0.5;
	vec3 col = COLOR.rgb;
	if (paint < 0.5) {
		col *= 0.82 + 0.3 * n;
		// Fine grit.
		col *= 0.9 + 0.2 * hash(floor(UV * 40.0));
		ROUGHNESS = 0.93;
	} else {
		// Worn paint: the asphalt shows through in places.
		col = mix(col, vec3(0.05), smoothstep(0.62, 0.9, noise(UV * 3.0)) * 0.25);
		ROUGHNESS = 0.7;
	}
	ALBEDO = col;
}
