shader_type spatial;

// Floors of the house built by tools/build_house.gd, drawn without textures.
// COLOR.a: 1 oak parquet planks, 0.5 ceramic tiles, 0 smooth concrete.
// UV: metres across the floor.

const vec2 PLANK = vec2(1.2, 0.14);
const float TILE = 0.4;

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

void fragment() {
	vec2 m = UV;
	vec3 col;
	float rough;
	if (COLOR.a > 0.75) {
		// Planks in staggered rows, each its own shade, with grain along its length.
		float row = floor(m.y / PLANK.y);
		vec2 cell = vec2(m.x / PLANK.x + hash(vec2(row, 3.0)), m.y / PLANK.y);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		col = srgb(vec3(0.62, 0.43, 0.27)) * (0.8 + 0.3 * hash(id));
		col *= 0.9 + 0.2 * noise(vec2(m.x * 3.0, m.y * 60.0) + id * 7.0);
		vec2 edge = min(f, 1.0 - f) * PLANK;
		col *= mix(0.55, 1.0, smoothstep(0.0, 0.004, min(edge.x, edge.y)));
		rough = 0.45;
	} else if (COLOR.a > 0.25) {
		// Square tiles with grout lines.
		vec2 id = floor(m / TILE);
		vec2 f = fract(m / TILE);
		col = srgb(vec3(0.78, 0.76, 0.72)) * (0.92 + 0.12 * hash(id));
		col *= 0.95 + 0.1 * noise(m * 12.0);
		vec2 edge = min(f, 1.0 - f) * TILE;
		float grout = 1.0 - smoothstep(0.002, 0.005, min(edge.x, edge.y));
		col = mix(col, srgb(vec3(0.45, 0.43, 0.4)), grout);
		rough = mix(0.25, 0.9, grout);
	} else {
		col = srgb(vec3(0.5, 0.5, 0.48)) * (0.85 + 0.25 * noise(m * 1.5)) * (0.94 + 0.08 * noise(m * 17.0));
		rough = 0.85;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
