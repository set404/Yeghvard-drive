shader_type spatial;

// COLOR.a: 1 wall with windows, 0.5 plain wall, 0 roof.
//          0.78 + 0.02 * n: wall with windows and a garage door in window column n.
// UV: metres along the wall, metres down from the roofline.
// UV2: wall length, building height. A negative height marks pink tuff masonry.

// Keep in step with FLOOR_HEIGHT and WINDOW_SPACING in tools/build_world.gd.
const float FLOOR_HEIGHT = 3.0;
const float WINDOW_SPACING = 3.2;

// Tuff blocks, in metres.
const vec2 BLOCK = vec2(0.58, 0.29);
const float JOINT = 0.012;

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

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

// Armenian pink tuff laid in even courses: every block its own shade of rose,
// salmon or mauve, with the stone's pores and pale lime joints.
vec3 pink_tuff(vec2 m, out float rough) {
	float course = floor(m.y / BLOCK.y);
	// Each course is shifted by half a block.
	vec2 cell = vec2(m.x / BLOCK.x + 0.5 * mod(course, 2.0), m.y / BLOCK.y);
	vec2 id = floor(cell);
	vec2 f = fract(cell);

	float pick = hash(id);
	vec3 stone = srgb(vec3(0.80, 0.55, 0.50));
	stone = mix(stone, srgb(vec3(0.87, 0.66, 0.60)), smoothstep(0.55, 0.8, pick));
	stone = mix(stone, srgb(vec3(0.66, 0.44, 0.44)), smoothstep(0.25, 0.05, pick));
	stone = mix(stone, srgb(vec3(0.78, 0.53, 0.44)), step(0.94, pick));
	stone *= 0.74 + 0.16 * hash(id + 17.0);

	// Cloudy colour inside a block, then the pores tuff is known for.
	stone *= 0.88 + 0.24 * noise(m * 9.0 + id * 3.0);
	float pores = smoothstep(0.74, 0.86, noise(m * 55.0)) * 0.5 + smoothstep(0.8, 0.9, noise(m * 21.0 + 5.0)) * 0.35;
	stone *= 1.0 - 0.45 * pores;

	vec2 edge = min(f, 1.0 - f) * BLOCK;
	float joint = 1.0 - smoothstep(JOINT * 0.5, JOINT, min(edge.x, edge.y));
	rough = mix(0.95, 1.0, joint);
	return mix(stone, srgb(vec3(0.70, 0.66, 0.60)), joint * 0.85);
}

void fragment() {
	vec3 col = COLOR.rgb;
	float rough = 0.9;
	float height = abs(UV2.y);
	if (UV2.y < 0.0) {
		col = pink_tuff(UV, rough);
	}
	if (COLOR.a > 0.75) {
		float columns = max(1.0, floor(UV2.x / WINDOW_SPACING));
		float floors = max(1.0, floor(height / FLOOR_HEIGHT));
		float across = UV.x / UV2.x * columns;
		float fx = fract(across);
		float fy = fract(UV.y / FLOOR_HEIGHT);
		float win = step(0.24, fx) * step(fx, 0.76) * step(0.28, fy) * step(fy, 0.74);
		win *= step(UV.y, floors * FLOOR_HEIGHT) * step(2.0, UV2.x);

		if (COLOR.a < 0.97) {
			float garage_column = round((COLOR.a - 0.78) / 0.02);
			if (abs(floor(across) - garage_column) < 0.5 && UV.y > (floors - 1.0) * FLOOR_HEIGHT) {
				// The doorway (real geometry) takes the place of this ground-floor window.
				win = 0.0;
			}
		}

		col = mix(col, vec3(0.03, 0.05, 0.08), win);
		rough = mix(rough, 0.15, win);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
