shader_type spatial;
render_mode cull_disabled;

// Old industrial garage gate, drawn without textures: red painted steel leaves
// with ribs, seams, handles, chipped paint and rust, under a strip of small
// greenish window panes.
// UV: 0..1 across the whole gate and bottom to top. UV2: size of the part in metres.

uniform int part = 0; // 0 the leaves, 1 the glazed strip above them

const float PANELS = 4.0;
const float ROWS = 4.0;

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

float fbm(vec2 p) {
	return noise(p) * 0.5 + noise(p * 2.1 + 7.3) * 0.3 + noise(p * 4.7 + 1.9) * 0.2;
}

// 1 inside a band of the given half width around `centre`, fading at its edges.
float band(float x, float centre, float half_width) {
	return 1.0 - smoothstep(half_width, half_width * 1.5, abs(x - centre));
}

void fragment() {
	vec2 m = UV * UV2; // metres
	vec3 col;
	float rough = 0.75;
	float metal = 0.0;

	if (part == 0) {
		float panel = floor(UV.x * PANELS);
		float px = fract(UV.x * PANELS); // across one panel
		float row = floor(UV.y * ROWS);
		float panel_w = UV2.x / PANELS;

		// Paint, a little different on every sheet.
		float tone = hash(vec2(panel, row));
		col = vec3(0.30, 0.028, 0.022) * (0.84 + 0.28 * tone);
		// Sun-faded and streaked top to bottom.
		col *= 0.9 + 0.2 * fbm(vec2(m.x * 1.3, m.y * 0.35));

		// Chipped paint showing pale primer, and rust that gathers low down and at seams.
		float chips = smoothstep(0.71, 0.76, fbm(m * 5.0 + panel * 3.1));
		col = mix(col, vec3(0.36, 0.25, 0.21), chips * 0.8);
		float rust = smoothstep(0.55, 0.8, fbm(m * 3.2 + 11.0) + 0.35 * (1.0 - UV.y) - 0.15);
		col = mix(col, vec3(0.10, 0.04, 0.02), rust * 0.65);

		// Upright ribs at the edges of each panel and the seams between sheets.
		float rib = max(band(px, 0.0, 0.045), band(px, 1.0, 0.045));
		col = mix(col, col * 0.4 + vec3(0.012, 0.008, 0.008), rib);
		float seam = band(fract(UV.y * ROWS), 0.0, 0.012) + band(fract(UV.y * ROWS), 1.0, 0.012);
		col = mix(col, vec3(0.03, 0.012, 0.01), clamp(seam, 0.0, 1.0) * 0.85);
		// The gap where the two leaves meet.
		col = mix(col, vec3(0.03), band(UV.x, 0.5, 0.004));

		// A pull handle on every panel, and bolts down the ribs.
		vec2 h = vec2((px - 0.5) * panel_w, m.y - UV2.y * 0.44);
		float handle = step(abs(h.x), 0.09) * step(abs(h.y), 0.022);
		col = mix(col, vec3(0.05, 0.05, 0.05), handle);
		float plate = step(abs(h.x), 0.12) * step(abs(h.y), 0.045) * (1.0 - handle);
		col = mix(col, col * 0.7, plate);

		rough = mix(0.7, 0.95, max(rust, chips));
		metal = 0.15 * (1.0 - rust);
	} else {
		// Two rows of small panes in a steel frame.
		vec2 cell = vec2(UV.x * 10.0, UV.y * 2.0);
		vec2 f = fract(cell);
		float frame = max(max(band(f.x, 0.0, 0.05), band(f.x, 1.0, 0.05)), max(band(f.y, 0.0, 0.07), band(f.y, 1.0, 0.07)));
		// The heavy post in the middle and the rail it stands on.
		frame = max(frame, max(band(UV.x, 0.5, 0.012), band(UV.y, 0.0, 0.08)));
		float pane = hash(floor(cell));
		vec3 glass = mix(vec3(0.10, 0.19, 0.20), vec3(0.20, 0.31, 0.30), pane);
		glass *= 0.85 + 0.3 * fbm(m * 6.0);
		col = mix(glass, vec3(0.03, 0.035, 0.03), frame);
		rough = mix(0.25, 0.8, frame);
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
